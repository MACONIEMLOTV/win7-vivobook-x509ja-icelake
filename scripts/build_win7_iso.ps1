<#
===============================================================================
 build_win7_iso.ps1
 Prepara una ISO di Windows 7 SP1 x64 (Professional) per ASUS VivoBook X509JA
   - USB  : Intel USB 3.1 xHCI   PCI\VEN_8086&DEV_34ED
   - SSD  : SK hynix NVMe        PCI\VEN_1C5C&DEV_1327
   - Avvio: solo UEFI, Secure Boot disattivato, UefiSeven 1.30

 Cosa fa:
   1. controlla di essere eseguito come Amministratore
   2. controlla i montaggi DISM rimasti aperti e li pulisce (chiede conferma)
   3. controlla che cartelle e file necessari esistano
   4. fa il backup di boot.wim e install.wim originali (una sola volta)
   5. (consigliato) esporta solo l'indice 3 (Professional) di install.wim
   6. integra aggiornamenti e driver in boot.wim (indici 1 e 2) e in install.wim
   7. copia il boot manager UEFI aggiornato (KB4474419) in efi\boot\bootx64.efi
      e, se vuoi, mette subito UefiSeven davanti (bootx64.original.efi)
   8. ricrea la ISO con oscdimg (Windows ADK), avviabile BIOS + UEFI

 Struttura attesa (modificabile con i parametri -Root e -UefiSevenDir):
   D:\Win7Work\ISO             copia estratta della ISO Microsoft originale
   D:\Win7Work\Mount           cartella di montaggio (vuota)
   D:\Win7Work\Updates         file .msu (KB4490628, KB4474419, KB2864202,
                               KB2990941, KB3087873)
   D:\Win7Work\Drivers\USB3    driver xHCI generico (cartella x64 dell'archivio
                               XHCI_UASP_WIN7_MUI.7z di daniel_k)
   D:\Win7Work\Drivers\NVMe    facoltativa: driver NVMe extra (.inf)
   D:\Win7Work\Drivers\Extra   facoltativa: altri driver (.inf)
   D:\UefiSeven 1.30           contenuto di UefiSeven_1.30.zip

 Log: D:\Win7Work\build.log  (dettaglio DISM: D:\Win7Work\dism_dettaglio.log)

 Avvio: doppio clic su build_win7_iso.cmd (chiede i permessi di amministratore)
 oppure, da PowerShell come amministratore:
   powershell -ExecutionPolicy Bypass -File D:\Win7Work\build_win7_iso.ps1
===============================================================================
#>
param(
    [string]$Root         = 'D:\Win7Work',
    [string]$UefiSevenDir = 'D:\UefiSeven 1.30'
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Percorsi
# --------------------------------------------------------------------------
$IsoDir     = Join-Path $Root 'ISO'
$MountDir   = Join-Path $Root 'Mount'
$UpdDir     = Join-Path $Root 'Updates'
$CabDir     = Join-Path $Root 'Updates\_cab'
$DrvUsb     = Join-Path $Root 'Drivers\USB3'
$DrvNvme    = Join-Path $Root 'Drivers\NVMe'
$DrvExtra   = Join-Path $Root 'Drivers\Extra'
$BackupDir  = Join-Path $Root 'Backup_originali'
$LogFile    = Join-Path $Root 'build.log'
$DismLog    = Join-Path $Root 'dism_dettaglio.log'
$IsoOut     = Join-Path $Root 'Win7_SP1_x64_X509JA.iso'
$BootWim    = Join-Path $IsoDir 'sources\boot.wim'
$InstallWim = Join-Path $IsoDir 'sources\install.wim'
$BootMgrTmp = Join-Path $Root '_bootmgfw_da_install_wim.efi'

# Codici di uscita DISM
$RC_OK            = 0
$RC_REBOOT        = 3010          # completato, riavvio richiesto (normale offline)
$RC_NOTAPPLICABLE = -2146498530   # 0x800F081E: pacchetto non applicabile all'immagine

# Hash SHA-256 dei file .msu verificati (scaricati e controllati il 15/11/2026)
$KnownHashes = @{
    'KB4490628' = '8075F6D889BCB27BE6F52ED47081675E5BB8A5390F2F5BFE4EC27A2BB70CBF5E'
    'KB4474419' = '99312DF792B376F02E25607D2EB3355725C47D124D8DA253193195515FE90213'
    'KB2864202' = 'C5B5566B71B8C2965BF72A239131FF0CE3A9A1AD5687AA0C60125C9B648FDF17'
    'KB2990941' = 'D1ACBDD8652D6C78CE284BF511F3A7F5F776A0A91357ACA060039A99C6A93A16'
    'KB3087873' = '6D511FB126495579F681ECF5F4052DCB2C4C21154A0A9FAA5D9D8AE06D4BE538'
}
# Ordine di integrazione: prima lo stack di servizio, poi SHA-2, KMDF, NVMe
$KbOrder    = @('KB4490628','KB4474419','KB2864202','KB2990941','KB3087873')
$KbRequired = @('KB4474419','KB2864202','KB2990941','KB3087873')

$script:Mounted  = $false
$script:Warnings = New-Object System.Collections.Generic.List[string]

# --------------------------------------------------------------------------
# Funzioni di supporto
# --------------------------------------------------------------------------
function Write-Log {
    param([string]$Msg, [string]$Color = 'Gray')
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

function Add-Warn {
    param([string]$Msg)
    $script:Warnings.Add($Msg) | Out-Null
    Write-Log ('ATTENZIONE: ' + $Msg) 'Yellow'
}

function Ask-YesNo {
    param([string]$Question, [bool]$DefaultYes = $true)
    $suffix = if ($DefaultYes) { '[S/n]' } else { '[s/N]' }
    while ($true) {
        $a = Read-Host ("{0} {1}" -f $Question, $suffix)
        if ([string]::IsNullOrWhiteSpace($a)) { return $DefaultYes }
        switch -Regex ($a.Trim().ToLower()) {
            '^(s|si|sì|y|yes)$' { return $true }
            '^(n|no)$'          { return $false }
        }
        Write-Host 'Rispondi S oppure N.' -ForegroundColor Yellow
    }
}

function Invoke-Dism {
    # Esegue dism.exe, mostra e registra l'output, restituisce il codice di uscita
    param([string[]]$DismArgs)
    $ErrorActionPreference = 'Continue'   # evita che l'output su stderr blocchi lo script
    $all = @($DismArgs) + @("/LogPath:$DismLog", '/English')
    Write-Log ('> dism ' + ($all -join ' ')) 'DarkCyan'
    & dism.exe @all 2>&1 | ForEach-Object {
        $t = "$_"
        if ($t.Trim().Length -gt 0) {
            Write-Host "    $t"
            try { Add-Content -Path $LogFile -Value "    $t" -Encoding UTF8 } catch {}
        }
    }
    $rc = $LASTEXITCODE
    Write-Log ("  codice di uscita DISM: {0} (0x{1:X8})" -f $rc, $rc) 'DarkGray'
    return $rc
}

function Dismount-Discard {
    if ($script:Mounted) {
        Write-Log "Smonto l'immagine SENZA salvare (/Discard)..." 'Yellow'
        Invoke-Dism @('/Unmount-Image', "/MountDir:$MountDir", '/Discard') | Out-Null
        $script:Mounted = $false
    }
}

function Stop-Script {
    param([string]$Msg)
    Write-Log ('ERRORE: ' + $Msg) 'Red'
    if ($script:Mounted) {
        if (Ask-YesNo "C'è un'immagine ancora montata. La smonto scartando le modifiche?" $true) {
            Dismount-Discard
        } else {
            Write-Log "Immagine lasciata montata in $MountDir. Prima di rilanciare: dism /Unmount-Image /MountDir:`"$MountDir`" /Discard" 'Yellow'
        }
    }
    Write-Log "Lo script si è fermato. Il log completo è in $LogFile" 'Red'
    Read-Host 'Premi INVIO per chiudere'
    exit 1
}

function Get-KbId {
    param([string]$Name)
    if ($Name -match '(KB\d{6,7})') { return $Matches[1].ToUpper() }
    return $null
}

function Get-InfFiles {
    # Tutti i .inf in una cartella (ricorsivo), escluse le sottocartelle a 32 bit
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return @() }
    return @(Get-ChildItem -Path $Dir -Filter *.inf -Recurse -File |
             Where-Object { $_.FullName -notmatch '\\(x86|i386|32bit|win32)\\' })
}

function Clear-ReadOnly {
    param([string]$Path)
    if (Test-Path $Path) {
        $it = Get-Item $Path -Force
        if ($it.IsReadOnly) { $it.IsReadOnly = $false; Write-Log "Rimosso attributo sola lettura: $Path" }
    }
}

# --------------------------------------------------------------------------
# 0. Amministratore e log
# --------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Questo script va eseguito come Amministratore.' -ForegroundColor Red
    Write-Host 'Usa build_win7_iso.cmd oppure apri PowerShell con "Esegui come amministratore".' -ForegroundColor Red
    Read-Host 'Premi INVIO per chiudere'
    exit 1
}

if (-not (Test-Path $Root)) {
    Write-Host "Cartella di lavoro non trovata: $Root" -ForegroundColor Red
    Write-Host 'Controlla il percorso oppure lancia lo script con -Root <percorso>.' -ForegroundColor Red
    Read-Host 'Premi INVIO per chiudere'
    exit 1
}

Write-Log '=================================================================' 'Cyan'
Write-Log ' Preparazione ISO Windows 7 SP1 x64 per ASUS VivoBook X509JA' 'Cyan'
Write-Log '=================================================================' 'Cyan'
Write-Log ("Host: {0} - PowerShell {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)
$dismVer = (Get-Item "$env:WINDIR\System32\dism.exe").VersionInfo.ProductVersion
Write-Log "Versione DISM: $dismVer"

# --------------------------------------------------------------------------
# 1. Controllo percorsi
# --------------------------------------------------------------------------
Write-Log '--- 1. Controllo cartelle e file ---' 'Cyan'
$missing = @()
foreach ($p in @($IsoDir, $BootWim, $InstallWim, $UpdDir, $DrvUsb)) {
    if (-not (Test-Path $p)) { $missing += $p }
}
if ($missing.Count -gt 0) {
    Stop-Script ("Mancano questi percorsi:`r`n  " + ($missing -join "`r`n  ") + "`r`nLeggi LEGGIMI.txt: cosa scaricare e dove metterlo.")
}
foreach ($d in @($MountDir, $BackupDir, $CabDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null; Write-Log "Creata cartella $d" }
}
if (-not (Test-Path $DrvNvme)) { New-Item -ItemType Directory -Path $DrvNvme | Out-Null }

# Spazio libero (servono circa 15 GB)
$drive = (Get-Item $Root).PSDrive
$freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
Write-Log "Spazio libero su $($drive.Name):  $freeGB GB"
if ($freeGB -lt 15) {
    Add-Warn "Meno di 15 GB liberi su $($drive.Name):. DISM potrebbe fallire a metà."
    if (-not (Ask-YesNo 'Continuare lo stesso?' $false)) { Stop-Script 'Interrotto: spazio insufficiente.' }
}

# Info sull'install.wim (per sicurezza mostriamo gli indici)
Invoke-Dism @('/Get-WimInfo', "/WimFile:$InstallWim") | Out-Null

# --------------------------------------------------------------------------
# 2. Montaggi DISM rimasti aperti
# --------------------------------------------------------------------------
Write-Log '--- 2. Controllo montaggi DISM rimasti aperti ---' 'Cyan'
Invoke-Dism @('/Get-MountedWimInfo') | Out-Null
$mounted = @()
try { $mounted = @(Get-WindowsImage -Mounted -ErrorAction Stop) } catch { Add-Warn "Get-WindowsImage -Mounted non disponibile: controlla a mano l'output qui sopra." }
if ($mounted.Count -gt 0) {
    foreach ($m in $mounted) { Write-Log ("Montata: {0}  (file: {1}, indice {2}, stato {3})" -f $m.Path, $m.ImagePath, $m.ImageIndex, $m.MountStatus) 'Yellow' }
    if (Ask-YesNo 'Trovate immagini ancora montate. Le smonto SCARTANDO eventuali modifiche e pulisco DISM (/Cleanup-Wim)?' $true) {
        foreach ($m in $mounted) { Invoke-Dism @('/Unmount-Image', "/MountDir:$($m.Path)", '/Discard') | Out-Null }
        Invoke-Dism @('/Cleanup-Wim') | Out-Null
    } else {
        Stop-Script 'Ci sono immagini montate. Smontale prima di rilanciare lo script.'
    }
}
if (@(Get-ChildItem -Path $MountDir -Force -ErrorAction SilentlyContinue).Count -gt 0) {
    Add-Warn "La cartella $MountDir non è vuota."
    if (Ask-YesNo 'Eseguo dism /Cleanup-Wim per liberarla?' $true) { Invoke-Dism @('/Cleanup-Wim') | Out-Null }
    if (@(Get-ChildItem -Path $MountDir -Force -ErrorAction SilentlyContinue).Count -gt 0) {
        Stop-Script "La cartella $MountDir non è ancora vuota. Svuotala a mano (dopo aver verificato che non ci sia nulla montato) e rilancia."
    }
}
Write-Log 'Nessun montaggio attivo: OK' 'Green'

# --------------------------------------------------------------------------
# 3. Aggiornamenti (.msu / .cab)
# --------------------------------------------------------------------------
Write-Log '--- 3. Controllo aggiornamenti ---' 'Cyan'
$updFiles = @(Get-ChildItem -Path $UpdDir -File | Where-Object { $_.Extension -in '.msu', '.cab' })
if ($updFiles.Count -eq 0) { Stop-Script "Nessun file .msu/.cab in $UpdDir." }

$byKb = @{}
foreach ($f in $updFiles) {
    $kb = Get-KbId $f.Name
    if (-not $kb) { Add-Warn "File senza numero KB nel nome, lo ignoro: $($f.Name)"; continue }
    if ($f.Name -notmatch 'x64') { Add-Warn "$($f.Name) non sembra x64: lo ignoro."; continue }
    $byKb[$kb] = $f
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    $sig  = (Get-AuthenticodeSignature -FilePath $f.FullName).Status
    $hashInfo = if ($KnownHashes.ContainsKey($kb)) {
        if ($KnownHashes[$kb] -eq $hash) { 'hash VERIFICATO' } else { 'hash DIVERSO da quello verificato' }
    } else { 'hash non in elenco' }
    Write-Log ("{0}: {1}  firma={2}  {3}" -f $kb, $f.Name, $sig, $hashInfo)
    if ($sig -ne 'Valid') { Add-Warn "$($f.Name): firma digitale non valida ($sig). Riscaricalo dalla fonte indicata in LEGGIMI.txt." }
    if ($hashInfo -like '*DIVERSO*') { Add-Warn "$($f.Name): hash diverso da quello atteso (forse altra versione). Controlla la fonte." }
}
$missingKb = @($KbRequired | Where-Object { -not $byKb.ContainsKey($_) })
if ($missingKb.Count -gt 0) {
    Stop-Script ("Mancano aggiornamenti indispensabili: " + ($missingKb -join ', ') + ". Vedi LEGGIMI.txt.")
}
if (-not $byKb.ContainsKey('KB4490628')) { Add-Warn 'KB4490628 (stack di servizio) assente: KB4474419 potrebbe non integrarsi.' }

# Ordine finale: prima quelli noti nell'ordine giusto, poi eventuali altri
$ordered = @()
foreach ($kb in $KbOrder) { if ($byKb.ContainsKey($kb)) { $ordered += $byKb[$kb] } }
foreach ($kb in ($byKb.Keys | Sort-Object)) { if ($KbOrder -notcontains $kb) { $ordered += $byKb[$kb] } }

# Estrae il .cab dai .msu (DISM su Windows 10/11 gestisce meglio i .cab per immagini Windows 7)
$packages = @()
foreach ($f in $ordered) {
    $kb = Get-KbId $f.Name
    if ($f.Extension -eq '.cab') { $packages += [pscustomobject]@{ Kb = $kb; Path = $f.FullName }; continue }
    $dest = Join-Path $CabDir $kb
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest | Out-Null
    Write-Log "Estraggo $($f.Name)..."
    & expand.exe -F:Windows6.1-KB*.cab "$($f.FullName)" "$dest" | Out-Null
    $cab = Get-ChildItem -Path $dest -Filter 'Windows6.1-KB*.cab' -File | Select-Object -First 1
    if (-not $cab) { Stop-Script "Impossibile estrarre il .cab da $($f.Name). Il file è danneggiato?" }
    $packages += [pscustomobject]@{ Kb = $kb; Path = $cab.FullName }
}
Write-Log ('Ordine di integrazione: ' + (($packages | ForEach-Object { $_.Kb }) -join ' -> ')) 'Green'

# --------------------------------------------------------------------------
# 4. Driver
# --------------------------------------------------------------------------
Write-Log '--- 4. Controllo driver ---' 'Cyan'
$drivers = @(Get-InfFiles $DrvUsb) + @(Get-InfFiles $DrvNvme) + @(Get-InfFiles $DrvExtra)
foreach ($d in $drivers) { Write-Log ("Driver: {0}" -f $d.FullName) }
if (-not ($drivers | Where-Object { $_.Name -ieq 'usbxhci.inf' })) {
    Add-Warn "Non trovo usbxhci.inf in $DrvUsb. Senza driver xHCI il kernel perde la chiavetta durante 'Avvio di Windows'."
    if (-not (Ask-YesNo 'Continuare comunque?' $false)) { Stop-Script 'Interrotto: manca il driver USB 3 (xHCI).' }
}
if (@(Get-InfFiles $DrvNvme).Count -eq 0) {
    Write-Log 'Drivers\NVMe vuota: va bene, il driver NVMe Microsoft (stornvme) arriva con KB2990941.'
}

# --------------------------------------------------------------------------
# 5. Backup dei WIM originali
# --------------------------------------------------------------------------
Write-Log '--- 5. Backup dei WIM originali ---' 'Cyan'
Clear-ReadOnly $BootWim
Clear-ReadOnly $InstallWim
$backupWasPresent = (Test-Path (Join-Path $BackupDir 'boot.wim')) -and (Test-Path (Join-Path $BackupDir 'install.wim'))
foreach ($w in @($BootWim, $InstallWim)) {
    $bk = Join-Path $BackupDir (Split-Path $w -Leaf)
    if (-not (Test-Path $bk)) {
        Write-Log "Copio $w -> $bk (può richiedere qualche minuto)..."
        Copy-Item -Path $w -Destination $bk
        Write-Log 'Backup creato.' 'Green'
    } else {
        Write-Log "Backup già presente: $bk"
    }
}
if ($backupWasPresent -and (Ask-YesNo 'Ripartire dai WIM originali del backup? (consigliato se hai già fatto altri tentativi)' $true)) {
    foreach ($n in @('boot.wim', 'install.wim')) {
        Copy-Item -Path (Join-Path $BackupDir $n) -Destination (Join-Path $IsoDir "sources\$n") -Force
        Clear-ReadOnly (Join-Path $IsoDir "sources\$n")
    }
    Write-Log 'WIM originali ripristinati nella cartella ISO.' 'Green'
}

# --------------------------------------------------------------------------
# Funzione: integra pacchetti e driver in un indice
# --------------------------------------------------------------------------
function Update-WimIndex {
    param([string]$Wim, [int]$Index, [string]$Label, [bool]$IsInstall)

    Write-Log "=== $Label  ($Wim, indice $Index) ===" 'Cyan'
    $rc = Invoke-Dism @('/Mount-Image', "/ImageFile:$Wim", "/Index:$Index", "/MountDir:$MountDir")
    if ($rc -ne $RC_OK) { Stop-Script "Montaggio non riuscito: $Label." }
    $script:Mounted = $true

    # Aggiornamenti
    foreach ($p in $packages) {
        Write-Log "Aggiungo $($p.Kb) a $Label..."
        $rc = Invoke-Dism @("/Image:$MountDir", '/Add-Package', "/PackagePath:$($p.Path)")
        if ($rc -eq $RC_OK -or $rc -eq $RC_REBOOT) {
            Write-Log "  $($p.Kb): OK" 'Green'
        } elseif ($rc -eq $RC_NOTAPPLICABLE) {
            Add-Warn "$($p.Kb) non applicabile a $Label (0x800F081E). Proseguo."
        } else {
            Add-Warn "$($p.Kb) NON integrato in $Label (codice $rc)."
            if (-not (Ask-YesNo 'Continuare con il resto?' ($KbRequired -notcontains $p.Kb))) {
                Stop-Script "Integrazione di $($p.Kb) fallita in $Label."
            }
        }
    }

    # Driver (uno per volta, così vediamo esattamente quale fallisce;
    # equivale a /Add-Driver /Recurse ma salta le cartelle x86)
    foreach ($d in $drivers) {
        Write-Log "Aggiungo driver $($d.Name) a $Label..."
        $rc = Invoke-Dism @("/Image:$MountDir", '/Add-Driver', "/Driver:$($d.FullName)")
        if ($rc -ne $RC_OK) {
            Add-Warn "$($d.Name) rifiutato (codice $rc): riprovo con /ForceUnsigned."
            $rc = Invoke-Dism @("/Image:$MountDir", '/Add-Driver', "/Driver:$($d.FullName)", '/ForceUnsigned')
            if ($rc -eq $RC_OK) {
                Add-Warn "$($d.Name) integrato con /ForceUnsigned in ${Label}: all'avvio Windows 7 controllerà comunque la firma."
            } else {
                Add-Warn "$($d.Name) NON integrato in $Label (codice $rc)."
                if (-not (Ask-YesNo 'Continuare?' ($d.Name -ine 'usbxhci.inf'))) { Stop-Script "Driver $($d.Name) non integrato in $Label." }
            }
        }
    }

    # Verifica
    try {
        $drv = @(Get-WindowsDriver -Path $MountDir -ErrorAction Stop)
        $names = ($drv | ForEach-Object { Split-Path $_.OriginalFileName -Leaf } | Sort-Object -Unique) -join ', '
        Write-Log "Driver di terze parti presenti in ${Label}: $names"
        if ($drivers.Count -gt 0 -and -not ($drv | Where-Object { $_.OriginalFileName -like '*usbxhci.inf' })) {
            Add-Warn "usbxhci.inf non risulta in $Label."
        }
    } catch { Add-Warn "Verifica driver non riuscita in $Label ($($_.Exception.Message))." }
    try {
        $pk = @(Get-WindowsPackage -Path $MountDir -ErrorAction Stop)
        foreach ($kb in $KbOrder) {
            $hit = $pk | Where-Object { $_.PackageName -like "*$kb*" }
            if ($hit) { Write-Log "  $kb presente in $Label" 'Green' } else { Write-Log "  $kb NON presente in $Label" 'Yellow' }
        }
    } catch { Add-Warn "Verifica pacchetti non riuscita in $Label ($($_.Exception.Message))." }

    # Boot manager UEFI aggiornato da KB4474419 (serve per la chiavetta)
    if ($IsInstall) {
        $bm = Join-Path $MountDir 'Windows\Boot\EFI\bootmgfw.efi'
        if (Test-Path $bm) {
            Copy-Item $bm $BootMgrTmp -Force
            Write-Log ("bootmgfw.efi da install.wim: versione {0}" -f (Get-Item $BootMgrTmp).VersionInfo.FileVersion)
        } else { Add-Warn 'bootmgfw.efi non trovato in install.wim.' }
    }

    Write-Log "Salvo e smonto $Label (/Commit)..."
    $rc = Invoke-Dism @('/Unmount-Image', "/MountDir:$MountDir", '/Commit')
    if ($rc -ne $RC_OK) { Stop-Script "Salvataggio (commit) non riuscito per $Label." }
    $script:Mounted = $false
    Write-Log "$Label completato." 'Green'
}

# --------------------------------------------------------------------------
# 6. install.wim: esportazione del solo Professional (consigliata)
# --------------------------------------------------------------------------
Write-Log '--- 6. install.wim ---' 'Cyan'
$exportOnly = Ask-YesNo "Tenere SOLO Windows 7 Professional (indice 3)? Più veloce, ISO più piccola, install.wim sotto i 4 GB per FAT32" $true
$installIndex = 3
if ($exportOnly) {
    $tmpWim = Join-Path $IsoDir 'sources\install_pro.wim'
    if (Test-Path $tmpWim) { Remove-Item $tmpWim -Force }
    $rc = Invoke-Dism @('/Export-Image', "/SourceImageFile:$InstallWim", '/SourceIndex:3', "/DestinationImageFile:$tmpWim", '/Compress:max', '/CheckIntegrity')
    if ($rc -ne $RC_OK) { Stop-Script 'Esportazione dell''indice 3 non riuscita.' }
    Remove-Item $InstallWim -Force
    Rename-Item $tmpWim 'install.wim'
    $installIndex = 1
    Write-Log 'install.wim ora contiene solo Professional (indice 1).' 'Green'
}

# --------------------------------------------------------------------------
# 7. Integrazione
# --------------------------------------------------------------------------
Update-WimIndex -Wim $BootWim    -Index 1 -Label 'boot.wim [1] Windows PE'    -IsInstall $false
Update-WimIndex -Wim $BootWim    -Index 2 -Label 'boot.wim [2] Windows Setup' -IsInstall $false
Update-WimIndex -Wim $InstallWim -Index $installIndex -Label "install.wim [$installIndex] Professional" -IsInstall $true

# Ricompatta install.wim (dopo il commit il file contiene anche dati vecchi)
if ($exportOnly) {
    $tmpWim = Join-Path $IsoDir 'sources\install_compact.wim'
    if (Test-Path $tmpWim) { Remove-Item $tmpWim -Force }
    $rc = Invoke-Dism @('/Export-Image', "/SourceImageFile:$InstallWim", '/SourceIndex:1', "/DestinationImageFile:$tmpWim", '/Compress:max', '/CheckIntegrity')
    if ($rc -eq $RC_OK) {
        Remove-Item $InstallWim -Force
        Rename-Item $tmpWim 'install.wim'
        Write-Log 'install.wim ricompattato.' 'Green'
    } else {
        Add-Warn 'Ricompattazione non riuscita: tengo install.wim così com''è (funziona lo stesso, è solo più grande).'
        if (Test-Path $tmpWim) { Remove-Item $tmpWim -Force }
    }
}

$sizeGB = [math]::Round((Get-Item $InstallWim).Length / 1GB, 2)
Write-Log "Dimensione install.wim: $sizeGB GB"
if ((Get-Item $InstallWim).Length -ge 4294967295) {
    Add-Warn 'install.wim supera i 4 GB: non entra in una chiavetta FAT32 (che serve per UefiSeven).'
    Write-Log 'Soluzione consigliata: rilancia lo script rispondendo S alla domanda "Tenere SOLO Professional".' 'Yellow'
}

# --------------------------------------------------------------------------
# 8. File di avvio UEFI (boot manager aggiornato + UefiSeven)
# --------------------------------------------------------------------------
Write-Log '--- 8. File di avvio UEFI ---' 'Cyan'
$efiBootDir = Join-Path $IsoDir 'efi\boot'
if (Test-Path $BootMgrTmp) {
    if (-not (Test-Path $efiBootDir)) { New-Item -ItemType Directory -Path $efiBootDir | Out-Null }
    $oldBx = Join-Path $efiBootDir 'bootx64.efi'
    $bkBx  = Join-Path $BackupDir 'bootx64.efi.originale'
    if ((Test-Path $oldBx) -and -not (Test-Path $bkBx)) { Copy-Item $oldBx $bkBx; Write-Log "Backup del vecchio bootx64.efi in $bkBx" }

    $useSeven = $false
    $sevenEfi = $null
    if (Test-Path $UefiSevenDir) {
        $sevenEfi = Get-ChildItem -Path $UefiSevenDir -Filter 'bootx64.efi' -Recurse -File | Select-Object -First 1
    }
    if ($sevenEfi) {
        $useSeven = Ask-YesNo "Mettere UefiSeven già nella ISO (efi\boot\bootx64.efi = UefiSeven, bootx64.original.efi = boot manager Windows 7)?" $true
    } else {
        Add-Warn "UefiSeven non trovato in ${UefiSevenDir}: dovrai metterlo a mano sulla chiavetta dopo Rufus."
    }

    if ($useSeven) {
        Copy-Item $BootMgrTmp (Join-Path $efiBootDir 'bootx64.original.efi') -Force
        Copy-Item $sevenEfi.FullName $oldBx -Force
        $ini = Get-ChildItem -Path $UefiSevenDir -Filter 'UefiSeven.ini' -Recurse -File | Select-Object -First 1
        if ($ini) { Copy-Item $ini.FullName (Join-Path $efiBootDir 'UefiSeven.ini') -Force }
        Write-Log 'UefiSeven integrato in efi\boot (bootx64.efi + bootx64.original.efi).' 'Green'
    } else {
        Copy-Item $BootMgrTmp $oldBx -Force
        Write-Log 'Boot manager aggiornato copiato in efi\boot\bootx64.efi (senza UefiSeven).' 'Green'
    }
    # Il vecchio bootx64.original.efi di prove precedenti non serve più se non usiamo UefiSeven
    if (-not $useSeven -and (Test-Path (Join-Path $efiBootDir 'bootx64.original.efi'))) {
        Add-Warn 'In efi\boot c''è un vecchio bootx64.original.efi: rinominalo/eliminalo se non usi UefiSeven.'
    }
} else {
    Add-Warn 'Boot manager aggiornato non disponibile: efi\boot non modificato.'
}

# --------------------------------------------------------------------------
# 9. Creazione ISO con oscdimg
# --------------------------------------------------------------------------
Write-Log '--- 9. Creazione ISO ---' 'Cyan'
$oscdimg = $null
$cands = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe"
)
foreach ($c in $cands) { if ($c -and (Test-Path $c)) { $oscdimg = $c; break } }
if (-not $oscdimg) { $cmd = Get-Command oscdimg.exe -ErrorAction SilentlyContinue; if ($cmd) { $oscdimg = $cmd.Source } }

if (-not $oscdimg) {
    Add-Warn 'oscdimg.exe non trovato: la ISO non è stata creata.'
    Write-Log 'Installa Windows ADK (basta la funzione "Strumenti di distribuzione"/"Deployment Tools"):' 'Yellow'
    Write-Log '  https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install' 'Yellow'
    Write-Log 'poi rilancia lo script (rifarà l''integrazione) oppure lancia solo questo comando:' 'Yellow'
    Write-Log "  oscdimg -m -o -u2 -udfver102 -lWIN7_X509JA -bootdata:2#p0,e,b`"$IsoDir\boot\etfsboot.com`"#pEF,e,b`"$IsoDir\efi\microsoft\boot\efisys.bin`" `"$IsoDir`" `"$IsoOut`"" 'Yellow'
    Write-Log 'In alternativa vedi LEGGIMI.txt (copia manuale della cartella ISO su chiavetta FAT32).' 'Yellow'
} else {
    Write-Log "oscdimg: $oscdimg"
    $etfs = Join-Path $IsoDir 'boot\etfsboot.com'
    $efis = Join-Path $IsoDir 'efi\microsoft\boot\efisys.bin'
    $adkDir = Split-Path $oscdimg
    if (-not (Test-Path $etfs)) { $etfs = Join-Path $adkDir 'etfsboot.com' }
    if (-not (Test-Path $efis)) { $efis = Join-Path $adkDir 'efisys.bin' }
    if (-not (Test-Path $etfs) -or -not (Test-Path $efis)) { Stop-Script 'etfsboot.com o efisys.bin non trovati.' }
    if (Test-Path $IsoOut) { Remove-Item $IsoOut -Force }
    $bootdata = "2#p0,e,b`"$etfs`"#pEF,e,b`"$efis`""
    $oscArgs = @('-m', '-o', '-u2', '-udfver102', '-lWIN7_X509JA', "-bootdata:$bootdata", "`"$IsoDir`"", "`"$IsoOut`"")
    Write-Log ('> oscdimg ' + ($oscArgs -join ' ')) 'DarkCyan'
    $p = Start-Process -FilePath $oscdimg -ArgumentList $oscArgs -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0 -or -not (Test-Path $IsoOut)) { Stop-Script "oscdimg non è riuscito (codice $($p.ExitCode))." }
    Write-Log "ISO creata: $IsoOut" 'Green'
}

# --------------------------------------------------------------------------
# Riepilogo
# --------------------------------------------------------------------------
Write-Log '=================================================================' 'Cyan'
Write-Log ' FINITO' 'Cyan'
if ($script:Warnings.Count -gt 0) {
    Write-Log 'Avvisi da controllare:' 'Yellow'
    foreach ($w in $script:Warnings) { Write-Log "  - $w" 'Yellow' }
} else {
    Write-Log 'Nessun avviso.' 'Green'
}
Write-Log 'Prossimi passi:' 'Cyan'
Write-Log ' 1. Rufus: seleziona la ISO, schema GPT, destinazione UEFI (non CSM), file system FAT32.'
Write-Log ' 2. Sulla chiavetta controlla EFI\Boot: bootx64.efi deve essere UefiSeven (circa 95 KB)'
Write-Log '    e bootx64.original.efi il boot manager di Windows 7. Se Rufus li ha cambiati, rimettili.'
Write-Log ' 3. Prima di installare: backup della partizione EFI e chiave BitLocker (vedi post_install_laptop.txt).'
Write-Log ' 4. Alla fine della prima fase NON lasciare riavviare dal disco: segui post_install_laptop.txt.'
Write-Log "Log completo: $LogFile"
Read-Host 'Premi INVIO per chiudere'
