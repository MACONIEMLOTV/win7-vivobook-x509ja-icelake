# Windows 7 SP1 x64 nativo su ASUS VivoBook X509JA

Resoconto tecnico di un'installazione nativa, riuscita, di Windows 7 SP1 x64 Professional su un portatile Intel Ice Lake con firmware solo UEFI (senza CSM). Lavoro svolto il 15 e 16 novembre 2026 (Europe/Rome) su un PC secondario, per nostalgia.

Non è una guida ufficiale ASUS o Microsoft.

## Avvertenze e licenza

Windows 7 è fuori supporto. Questa installazione usa file Microsoft modificati da terzi (`acpi.sys` e `bootmgfw.efi`), richiede `testsigning` e non ha accelerazione grafica né Wi-Fi ufficiale. È adatta a un PC secondario o a un esperimento, non a un uso quotidiano in rete senza capire i rischi.

**Questo repository non distribuisce file Microsoft, ISO, WIM, driver o binari di terze parti** (incluso `acpi.sys` patchato e il bootloader FlashBoot). Si indicano i progetti originali, gli hash SHA-256 da verificare e la procedura. Gli script e il testo di questa documentazione sono rilasciati sotto licenza [MIT](LICENSE), **senza alcuna garanzia**. I file Microsoft e i binari modificati restano dei rispettivi titolari; scaricateli solo dalle fonti degli autori e verificate gli hash.

Non distribuite ISO o product key.

## Indice

- [Sintesi](#sintesi)
- [Hardware](#hardware)
- [Cosa funziona e cosa no](#cosa-funziona-e-cosa-no)
- [Strumenti, file e hash](#strumenti-file-e-hash)
- [1. Preparazione dell'immagine](#1-preparazione-dellimmagine)
- [2. Avvio della chiavetta: da UefiSeven a FlashBoot](#2-avvio-della-chiavetta-da-uefiseven-a-flashboot)
- [3. Installazione manuale da WinRE di Windows 11](#3-installazione-manuale-da-winre-di-windows-11)
- [4. Costruzione del BCD](#4-costruzione-del-bcd)
- [5. Correzioni Specialize e OOBE](#5-correzioni-specialize-e-oobe)
- [Tabella degli errori](#tabella-degli-errori)
- [Dopo il desktop](#dopo-il-desktop)
- [Limiti noti](#limiti-noti)
- [Script in questo repository](#script-in-questo-repository)
- [Crediti](#crediti)

## Sintesi

Il 15 novembre 2026 Windows 7 SP1 x64 Professional è arrivato al desktop su un ASUS VivoBook X509JA, un portatile Intel Ice Lake (10a generazione) il cui firmware è solo UEFI: ASUS ha rimosso «Launch CSM» a partire dai processori Coffee Lake, quindi non esiste una modalità legacy con cui Windows 7 possa usare INT 10h. Secure Boot è stato tenuto spento. L'obiettivo era un'installazione nativa su un PC secondario, non un dual-boot.

Il percorso che ha funzionato non è stato il setup grafico di Windows 7. UefiSeven 1.30, lo shim INT 10h usato di solito su hardware UEFI-only, si bloccava dopo `disk.sys` con lo schermo fermo su «Please wait...», senza schermata blu visibile anche con AutoReboot attivo. La svolta è stata sostituirlo con il `bootmgfw.efi` patchato di FlashBoot 3.4b (incluso in [SevenESPManager](https://github.com/Sevoos/SevenESPManager) di Sevoos). Il setup è partito, ma ha chiesto un «driver del dispositivo CD/DVD» pur vedendo sia il disco interno sia la chiavetta. Si è quindi applicata a mano l'immagine da WinRE di Windows 11 (ancora presente sul disco), si è costruito il BCD a mano perché `bcdboot` falliva, e si sono saltati i passaggi Specialize/OOBE che andavano in errore sul BCD creato manualmente e sull'avvio dei servizi.

| | |
| --- | --- |
| Desktop raggiunto | 15 novembre 2026, circa 22:50 (Europe/Rome) |
| Firmware | Solo UEFI, nessun CSM sul X509JA |
| Edizione | Windows 7 SP1 x64 Professional (`install.wim` indice 1) |
| Bootloader | FlashBoot 3.4b, al posto di UefiSeven 1.30 |

## Hardware

Identificativi confermati durante il lavoro (script di build, Gestione dispositivi e disco visto da WinRE). Il modello esatto della CPU (SKU i3/i5/i7) non è stato annotato: risulta solo che è Ice Lake, 10a generazione. Il disco interno, visto da `diskpart`, è il Disk 0 da 238 GB.

| Voce | Valore |
| --- | --- |
| Portatile | ASUS VivoBook X509JA (PC secondario, uso nostalgia) |
| Piattaforma | Intel Ice Lake, 10a generazione |
| Firmware | Solo UEFI, senza «Launch CSM»; Secure Boot disattivato |
| USB 3 / xHCI | Intel USB 3.1 xHCI, `PCI\VEN_8086&DEV_34ED` |
| SSD | SK hynix NVMe, `PCI\VEN_1C5C&DEV_1327` |
| Wi-Fi / Bluetooth | Intel Wireless-AC 9461 (Bluetooth sullo stesso chip) |
| Lettore schede | Realtek USB2.0-CRW, `VID_0BDA&PID_0129` |
| SMBus / SPI (chipset) | Intel `8086:34A3` (SMBus) e `8086:34A4` (SPI), restati sconosciuti |
| PC di preparazione | Desktop Windows con cartella `D:\Win7Work`; DISM 10.0.26100.9549 |

In un primo momento si era pensato a un dual-boot con Windows 11: Riduci volume in Gestione disco è fallito («il volume potrebbe essere corrotto»). BitLocker era già spento (protezione off, «fully decrypted»). Poiché i file del portatile non servivano, il 15 novembre si è scelto di cancellare interamente Windows 11 e installare solo Windows 7.

Lo script [scripts/post_install_laptop.txt](scripts/post_install_laptop.txt) descrive ancora il percorso dual-boot con UefiSeven sulla EFI interna, che in questa sessione è stato abbandonato.

## Cosa funziona e cosa no

Stato osservato al 16 novembre 2026 (Europe/Rome), dopo il lavoro sul desktop.

| Componente | Stato | Note |
| --- | --- | --- |
| Avvio UEFI nativo | Funziona | FlashBoot 3.4b su ESP interna come `\EFI\Boot\bootx64.efi` e `bootmgfw.efi`; BCD con `testsigning` on |
| Kernel / ACPI | Funziona | `acpi.sys` patchato (Rireki, 6.1.7601.24056) in `boot.wim` e `install.wim` |
| USB 3 (xHCI) | Funziona | Driver generico di daniel_k; in `boot.wim` `Start=0` per `USBXHCI`, `UCX01000`, `USBHUB3` |
| SSD NVMe | Funziona | KB2990941 v3 + KB3087873 v2 slipstreamati |
| Desktop e account locale | Funziona | OOBE saltata; utente amministratore creato a mano |
| Attivazione | Funziona | Product key retail; il primo tentativo online ha dato `0x80072F8F`, poi l'attivazione è andata a buon fine (metodo del successo non annotato) |
| Rete | Funziona via tethering | Tethering USB iPhone dopo iTunes 12.10.11 x64 e driver Apple Mobile Device Ethernet. Wi-Fi AC 9461: nessun driver Win7 |
| Browser | Funziona | Supermium (fork di Chrome per Windows 7). Internet Explorer 8 non apre i siti moderni |
| Audio | Funziona | «High Definition Audio Device» generico, senza triangolo giallo. Il test di ascolto non è stato confermato esplicitamente nel diario |
| Lettore di schede | Driver disponibile | Realtek `0BDA:0129` ha driver Win7; l'installazione sul portatile non è stata confermata |
| SMBus / SPI Ice Lake | Voci gialle | Intel Chipset 10.1.x (ultimo con supporto Win7) si è installato ma non copre `34A3`/`34A4`. Effetto solo estetico |
| Grafica iGPU | Non disponibile | Standard VGA, niente Aero, interfaccia e video a scatti. Nessun driver Ice Lake Win7 affidabile trovato |
| Wi-Fi / Bluetooth interni | Non disponibile | Intel non ha mai pubblicato driver Win7 per la AC 9461; non risultano INF modificati affidabili. Stesso chip per il Bluetooth |
| Touchpad | Non Funzionante | Probabile dispositivo I2C pensato per Windows 10+; lo stato reale (funziona o no) non è stato verificato nel diario |

## Strumenti, file e hash

Tutti gli SHA-256 qui sotto sono stati controllati sul PC di preparazione (lo script di build per i `.msu`; `certutil` per `acpi.sys` e FlashBoot). Gli hash dei `.msu` risultano verificati il 15 novembre 2026.

| File / pacchetto | Ruolo | SHA-256 |
| --- | --- | --- |
| KB4490628 | Stack di servizio (integrare per primo) | `8075F6D889BCB27BE6F52ED47081675E5BB8A5390F2F5BFE4EC27A2BB70CBF5E` |
| KB4474419 v3 | Firme SHA-2 e boot manager EFI aggiornato | `99312DF792B376F02E25607D2EB3355725C47D124D8DA253193195515FE90213` |
| KB2864202 | KMDF 1.11, richiesto dallo stack USB 3 | `C5B5566B71B8C2965BF72A239131FF0CE3A9A1AD5687AA0C60125C9B648FDF17` |
| KB2990941 v3 | Driver NVMe (tolto dal Catalog Microsoft; mirror su GitHub con firma Microsoft) | `D1ACBDD8652D6C78CE284BF511F3A7F5F776A0A91357ACA060039A99C6A93A16` |
| KB3087873 v2 | Correzione NVMe | `6D511FB126495579F681ECF5F4052DCB2C4C21154A0A9FAA5D9D8AE06D4BE538` |
| `acpi.sys` (Rireki) | Patch ACPI 0xA5, versione 6.1.7601.24056, ri-firmato | `fc950f04912230e5645d634e859bdade5f35e2cd4f90785c33247f25af4c3971` |
| `bootmgfw.flashboot-3.4b.efi` | Bootloader FlashBoot 3.4b (Sevoos / SevenESPManager), 807.936 byte | `c3b47bc432853be748982d886a1e1c966f410d5e89606631fc052d436970c355` |

Altri strumenti usati: Windows ADK (solo oscdimg, «Strumenti di distribuzione»), Rufus (chiavetta GPT, UEFI senza CSM, FAT32), script `build_win7_iso.cmd` / `build_win7_iso.ps1` in `D:\Win7Work`, driver xHCI generico di daniel_k (archivio `XHCI_UASP_WIN7_MUI.7z`; la password dell'archivio è quella pubblicata da daniel_k nel [thread MDL](https://forums.mydigitallife.net/threads/usb-3-xhci-driver-stack-for-windows-7.81934/)), UefiSeven 1.30 (provato e poi sostituito), iTunes 12.10.11 x64, Supermium x64, Intel Chipset Device Software 10.1.x.

**Nota su `testsigning` e firme.** Il file `acpi.sys` di Rireki è ri-firmato e, secondo le note di integrazione, non dovrebbe richiedere `testsigning` né F8. Nella pratica `testsigning` è stato comunque lasciato attivo nel BCD, come precauzione per lo stack modificato. `nointegritychecks` è ignorato da Windows 7 e è stato rimosso.

## 1. Preparazione dell'immagine

Sul PC fisso, in `D:\Win7Work`, si è partiti da una ISO Microsoft di Windows 7 SP1 x64. Lo script `build_win7_iso.ps1` (lanciato da `build_win7_iso.cmd` come amministratore) ha: controllato i montaggi DISM aperti; fatto il backup dei WIM originali; verificato hash e firma digitale Microsoft dei `.msu`; esportato solo l'indice 3 (Professional), che nell'immagine finale diventa l'indice 1 e resta sotto i 4 GB per la FAT32 (in sessione `install.wim` misurava 2,9 GB); integrato i cinque aggiornamenti nell'ordine KB4490628, KB4474419, KB2864202, KB2990941, KB3087873, più il driver xHCI di daniel_k, in `boot.wim` (indici 1 e 2) e in `install.wim`. La creazione della ISO è andata a buon fine. UefiSeven andava messo in `EFI\Boot` della chiavetta (`bootx64.efi` ≈ 95 KB, boot manager originale come `bootx64.original.efi`): dopo Rufus c'era un file solo, e i due file sono stati copiati a mano.

Subito dopo, con SOS attivo, si è visto che `usbxhci.sys`, `ucx01000.sys` e `usbhub3.sys` non venivano caricati all'avvio: i file c'erano in `boot.wim` indice 2, ma i servizi avevano `Start=3` (avvio su richiesta). Sono stati portati a `Start=0`:

```bat
dism /Mount-Wim /WimFile:D:\Win7Work\ISO\sources\boot.wim /Index:2 /MountDir:D:\Win7Work\Mount
reg load HKLM\W7SETUP D:\Win7Work\Mount\Windows\System32\config\SYSTEM
reg add HKLM\W7SETUP\ControlSet001\Services\USBXHCI /v Start /t REG_DWORD /d 0 /f
reg add HKLM\W7SETUP\ControlSet001\Services\UCX01000 /v Start /t REG_DWORD /d 0 /f
reg add HKLM\W7SETUP\ControlSet001\Services\USBHUB3 /v Start /t REG_DWORD /d 0 /f
reg unload HKLM\W7SETUP
dism /Unmount-Wim /MountDir:D:\Win7Work\Mount /Commit
copy /y D:\Win7Work\ISO\sources\boot.wim E:\sources\boot.wim
```

Dopo questa modifica la lista SOS mostrava `USBXHCI.SYS`, `UCX01000.SYS`, `USBHUB3.SYS` e `USBD8.SYS`, ma il blocco dopo `disk.sys` restava. Si è quindi sostituito `acpi.sys` (Rireki) in `boot.wim` indice 2 e, più tardi, in tutte le copie dentro `install.wim` indice 1 (`System32\drivers`, DriverStore, WinSxS), con `takeown` + `icacls` + copia e verifica dell'hash. I comandi dettagliati sono in [scripts/fix_acpi_e_diagnosi.txt](scripts/fix_acpi_e_diagnosi.txt). L'indice 1 di `boot.wim` (WinPE «Ripristina il computer») era facoltativo. Non è stato necessario ricreare la ISO né rifare Rufus: è bastato copiare i `.wim` sulla chiavetta.

## 2. Avvio della chiavetta: da UefiSeven a FlashBoot

Con UefiSeven 1.30, SOS e `testsigning`, tutti i driver del loader venivano caricati e `disk.sys` era l'ultimo della lista. Subito dopo, all'ingresso nel kernel, lo schermo restava fermo. Le prove economiche sul BCD della chiavetta non hanno sbloccato nulla:

- Serie 1A: `x2apicpolicy disable`, `onecpu on`, `useplatformclock yes`, `quietboot on`, `pciexpress forcedisable` (e rimozione di `nointegritychecks`).
- Serie 1B: `vga on`, `xsavedisable 1`, `truncatememory 0x100000000` (primi 4 GB di RAM).
- `CrashControl AutoReboot=1` in `boot.wim`: dopo `disk.sys` il PC restava fermo e non si riavviava da solo, quindi non era una schermata blu «leggibile» in modo classico.

L'ipotesi di lavoro, confermata dal fatto che il setup è partito appena UefiSeven è stato tolto di mezzo, è questa: su Ice Lake lo shim INT 10h di UefiSeven 1.30 congela il display dopo `disk.sys`. Anche un eventuale crash passerebbe da quella grafica emulata, quindi non si vede una BSOD e AutoReboot può non scattare. Una pista analoga (Lenovo con lo stesso tipo di processore) puntava a un `bootmgfw.efi` modificato chiamato FlashBoot.

UefiSeven sulla chiavetta è stato rinominato e sostituito con FlashBoot 3.4b, hash verificato. Secure Boot è rimasto spento, il BCD invariato:

```bat
ren E:\efi\boot\bootx64.efi bootx64.uefiseven.efi
copy /y D:\Win7Work\flashboot.efi E:\efi\boot\bootx64.efi
```

L'ASUS è andato oltre `disk.sys` e ha mostrato la GUI del setup di Windows 7. Prima di installare, `acpi.sys` patchato è stato copiato anche in `install.wim`, altrimenti il sistema sul disco si sarebbe trovato l'acpi originale al primo avvio.

**Nota onesta:** quando FlashBoot ha sbloccato il video, `acpi.sys` patchato e i driver USB con `Start=0` erano già nell'immagine di setup, quindi questa sessione non isola un avvio FlashBoot con acpi originale. La pila riuscita comprende tutti e tre.

## 3. Installazione manuale da WinRE di Windows 11

Il setup grafico, sia quello avviato normalmente sia quello rilanciato con `D:\setup.exe`, si fermava chiedendo un driver per il «dispositivo CD/DVD». `diskpart` vedeva però il Disk 0 da 238 GB e la chiavetta (`D:`); `dir D:\sources\install.wim` trovava il file da 2,9 GB. Sfogliare la cartella dei driver USB di daniel_k non ha trovato nulla di utile, e cambiare porta USB non ha sbloccato il setup. Il messaggio è fuorviante: i file c'erano, ma il setup di Windows 7 non li agganciava.

Windows 11 era ancora sul disco (partizione visibile da circa 237 GB). Si è quindi entrati nel suo ambiente di ripristino (Start, Shift+Riavvia, Risoluzione dei problemi, Opzioni avanzate, Prompt dei comandi), che offre un DISM moderno e gira dalla RAM.

**Tastiera.** In quell'ambiente il layout era inglese (US) su tastiera fisica italiana. L'uguale è sul tasto ì, i due punti si fanno con Shift+ò, la barra rovesciata con il tasto ù oppure Alt+92 sul tastierino. In alternativa, dopo un `exit` da `diskpart`: `wpeutil SetKeyboardLayout 0410:00000410` (i due punti vanno ancora scritti col layout US; in questa sessione il cambio ha avuto effetto solo su una nuova finestra `start cmd`).

I comandi seguenti **cancellano l'intero disco interno**. Dopo un primo tentativo in cui il disco risultava ancora occupato (probabilmente `clean` non era partito o era selezionato il disco sbagliato), `list disk` / `list part` hanno confermato Disk 0 vuoto, già GPT, con la partizione EFI creata. Schema usato: EFI FAT32 da 260 MB (lettera `S:`), MSR da 16 MB, partizione primaria NTFS «Windows7» (lettera `W:`).

```bat
diskpart
list disk
select disk 0
clean
convert gpt
create partition efi size=260
format quick fs=fat32 label=System
assign letter=S
create partition msr size=16
create partition primary
format quick fs=ntfs label=Windows7
assign letter=W
exit

dism /Apply-Image /ImageFile:D:\sources\install.wim /Index:1 /ApplyDir:W:\
```

Su questo schema la partizione 1 è l'ESP (`S:`), la 2 è l'MSR e la 3 è Windows (`W:`). Servirà al passo successivo, perché al riavvio le lettere si perdono.

## 4. Costruzione del BCD

`bcdboot` non è riuscito in nessuno dei due ambienti provati. Quello di Windows 11 (`bcdboot W:\Windows /s S: /f UEFI`) fallisce perché cerca componenti più recenti, assenti in Windows 7 (nelle schermate della sessione: errore «EX bins»). Quello di Windows 7 (`W:\Windows\System32\bcdboot W:\Windows /s S: /l en-us`, senza `/f`, che su Win7 non esiste) è fallito con `c000003a`. Si è quindi deciso di copiare a mano i file di boot e di creare lo store BCD con `bcdedit`.

Un primo riavvio prima che il BCD esistesse ha mostrato l'errore `0xc000000f` (file di configurazione dell'avvio mancante). A quel punto Windows 11 non c'era più, quindi il prompt di WinRE di Windows 11 non era più raggiungibile: si è usato Shift+F10 dalla chiavetta di setup di Windows 7 (che con FlashBoot parte). Per evitare una lunga serie di comandi con layout scomodo è stato preparato lo script [scripts/boot7.cmd](scripts/boot7.cmd), da copiare nella radice della chiavetta. Prima di lanciarlo vanno riassegnate le lettere. Al primo lancio Windows 7 era comparso come `C:` e non `W:`, e lo script si è fermato: si è tolta la lettera `C:` e assegnata `W:`, poi lo script è stato rilanciato con successo (`testsigning` on, percorso `\Windows\system32\winload.efi`, FlashBoot copiato sia in `\EFI\Microsoft\Boot\bootmgfw.efi` sia in `\EFI\Boot\bootx64.efi`).

Riassegnazione delle lettere e avvio dello script (la lettera della chiavetta era `D:` in questa sessione):

```bat
diskpart
select disk 0
select partition 1
assign letter=S
select partition 3
assign letter=W
list vol
exit
D:\boot7.cmd
```

Il contenuto integrale di `boot7.cmd` è nel file collegato sopra.

## 5. Correzioni Specialize e OOBE

Con il BCD a posto, Windows 7 partiva dal disco e il kernel funzionava. Si bloccava però nella specializzazione («applying system settings»). Il log `C:\Windows\Panther\setuperr.log` indicava un fallimento in `spbcd.dll` (`Sysprep_Specialize_Bcd`): il passaggio non riusciva ad aprire il BCD creato a mano. Quel passo serve solo a sistemare il BCD, che era già pronto, e si è potuto togliere. La ricerca `reg query HKLM\SOFTWARE /f spbcd /s /d` ha trovato la voce nella chiave `Sysprep\Specialize`, valore GUID `{6a6b0fac-5606-6e68-30fc-1a64408619ba}`:

```bat
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\Sysprep\Specialize" /v {6a6b0fac-5606-6e68-30fc-1a64408619ba} /f
reg delete "HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Setup\Sysprep\Specialize" /v {6a6b0fac-5606-6e68-30fc-1a64408619ba} /f
```

Il primo comando è riuscito; il secondo può rispondere «unable to find» (su Windows 7 la chiave Wow6432Node è spesso solo un riflesso). Dopo, la stessa ricerca lasciava solo le righe Generalize, che non vanno toccate. Al riavvio il setup è andato avanti e si è fermato su «Setup is starting services». `setuperr.log` non aveva errori nuovi. In `HKLM\SYSTEM\Setup\Status\ChildCompletion` il valore `setup.exe` era `0x1` (il setup si riteneva ancora alla fase fallita). Impostarlo a `3` non è bastato ad arrivare alla schermata del nome utente. Si è quindi saltata del tutto la configurazione finale, creando l'utente a mano e dichiarando il setup concluso. Sostituire `<utente>` con il nome scelto:

```bat
net user <utente> /add
net localgroup administrators <utente> /add
reg add HKLM\SYSTEM\Setup /v SetupType /t REG_DWORD /d 0 /f
reg add HKLM\SYSTEM\Setup /v SystemSetupInProgress /t REG_DWORD /d 0 /f
reg add HKLM\SYSTEM\Setup /v OOBEInProgress /t REG_DWORD /d 0 /f
reg add HKLM\SYSTEM\Setup /v CmdLine /t REG_SZ /d "" /f
shutdown /r /t 0
```

Al riavvio è comparsa la schermata di accesso e, il 15 novembre 2026 verso le 22:50 (Europe/Rome), il desktop di Windows 7.

## Tabella degli errori

Errore o sintomo, causa individuata in questa sessione, e correzione che ha funzionato (o che è stata scartata).

| Errore o sintomo | Causa | Correzione |
| --- | --- | --- |
| Blocco su «Avvio di Windows» / animazione (ISO originale, tentativi precedenti) | `boot.wim` senza xHCI per `DEV_34ED`: il kernel perde la chiavetta | Integrare il driver daniel_k e, se `Start=3`, portarlo a 0 |
| F8 / menu avanzato non si apre dalla chiavetta | Timeout breve, o menu non esposto da quel boot manager | `bcdedit` sulla chiavetta: `sos`, `testsigning`, `displaybootmenu` |
| SOS si ferma dopo `disk.sys`; `usbxhci` assente dalla lista | Servizi USB 3 con `Start=3` | `Start=0` su `USBXHCI`, `UCX01000`, `USBHUB3` in `boot.wim` indice 2 |
| SOS carica già gli USB 3 ma si ferma ancora dopo `disk.sys`; AutoReboot non scatta | UefiSeven 1.30 congela il display (INT 10h) su questo Ice Lake; una BSOD può restare invisibile | Sostituire UefiSeven con FlashBoot 3.4b come `\EFI\Boot\bootx64.efi`. Le prove BCD 1A/1B e AutoReboot non sono bastate |
| Setup: «CD/DVD drive device driver missing», con disco e `install.wim` visibili | Il setup di Windows 7 non aggancia i sorgenti, non manca un driver di storage | Apply-Image da WinRE di Windows 11; Browse dei driver USB e cambio porta non hanno sbloccato la GUI |
| `bcdboot` di Windows 11: errore «EX bins» (schermate della sessione) | Cerca file di boot più recenti, assenti in Windows 7 | Non usare quel `bcdboot`; costruire il BCD a mano |
| `bcdboot` di Windows 7: `c000003a` (schermate della sessione) | `bcdboot` di Win7, lanciato da WinRE di Windows 11, non crea lo store | `xcopy` dei file EFI + `bcdedit /createstore`, oppure `boot7.cmd` |
| `0xc000000f` all'avvio dal disco | BCD ancora inesistente o lettere `S:`/`W:` sbagliate | Riassegnare `S:` e `W:` e lanciare `boot7.cmd` |
| `boot7.cmd` non trova `W:\Windows` | Dopo l'apply la partizione può comparire come `C:` | `remove letter=C` e `assign letter=W`, poi rilanciare |
| Specialize fallisce in `spbcd.dll` (`Sysprep_Specialize_Bcd`) | Quel passaggio non apre il BCD creato a mano | Eliminare il valore `{6a6b0fac-5606-6e68-30fc-1a64408619ba}` da `Sysprep\Specialize` |
| OOBE: «Setup is starting services» | `setup.exe` in ChildCompletion restava a `0x1`; portarlo a 3 non è bastato | `net user` + `administrators` e azzeramento di `SetupType`, `SystemSetupInProgress`, `OOBEInProgress`, `CmdLine` |
| iTunes: errore sulla libreria Visual C++ 2005 (VC80); in sessione indicato anche `0x8007054F` | TrustedInstaller (Programma di installazione moduli) non in esecuzione, dopo l'OOBE saltata | `sc config trustedinstaller start= demand` e `net start trustedinstaller`, poi rilanciare iTunes |
| Attivazione online `0x80072F8F` | Problema di connessione sicura verso i server Microsoft (data/ora o stack TLS di Win7 «nudo»), non necessariamente il codice | Controllare orologio; in alternativa `slui 4` (telefono). L'attivazione retail è poi andata a buon fine |
| Aero: il tema non può essere applicato | Serve un vero driver grafico; su Ice Lake con Standard VGA non c'è | Usare un tema Basic (per esempio Windows 7 Basic). Non è aggirabile su questo hardware |
| Intel Chipset 10.1.x «completato» ma SMBus/SPI ancora gialli | L'ultimo pacchetto chipset con supporto Win7 precede Ice Lake | Lasciare le voci `34A3`/`34A4`: sono estetiche |

## Dopo il desktop

1. **Rete con tethering USB, non con il Wi-Fi interno.** Il 16 novembre si è usato il tethering USB di un iPhone. Serve iTunes 12.10.11 a 64 bit (ultima versione che supporta Windows 7; installer Apple `iTunes64Setup.exe`). Dopo l'errore VC80 si è avviato TrustedInstaller e l'installazione è andata a buon fine. Un avviso sul driver Ethernet in chiusura è comparso perché il telefono era già collegato: dopo Finish, scollegare e ricollegare il telefono, autorizzare l'hotspot, e se serve aggiornare «Apple Mobile Device Ethernet» da `C:\Program Files\Common Files\Apple\Mobile Device Support\Drivers`. Con `ipconfig` su «Media disconnected» si è spento e riacceso «Consenti accesso ad altri» a telefono sbloccato; è comparso un indirizzo e la rete ha funzionato. Internet Explorer 8 non apre i siti moderni: il ping verso `8.8.8.8` è il controllo utile.
2. **Browser moderno.** Si è installato [Supermium](https://github.com/win32ss/supermium), fork di Chrome ancora mantenuto per Windows 7 (installer `x64_setup.exe` dal canale di release dell'autore win32ss). Da lì si naviga normalmente sul tethering.
3. **Chipset, audio, lettore di schede.** Intel Chipset Device Software 10.1.x (ultima linea con supporto Win7) si è installato dopo un tentativo di estrazione fallito e un riavvio legato a .NET Framework 4.7.2, ma non contiene i driver Ice Lake: `8086:34A3` e `8086:34A4` restano sconosciuti e si possono ignorare. L'audio compariva già come High Definition Audio Device generico, senza triangolo giallo. Per il lettore Realtek `0BDA:0129` esiste un driver Win7; in questa sessione non è stato confermato come installato.
4. **Attivazione.** È stata usata una product key retail. Il primo tentativo online ha restituito `0x80072F8F`. Successivamente l'attivazione è andata a buon fine. Il metodo esatto del tentativo riuscito (riprova dopo correzione di data/ora, oppure telefono con `slui 4`) non è stato annotato. La licenza di Windows 11 del portatile non vale per Windows 7. Non pubblicate il codice.

## Limiti noti

1. **Grafica:** niente driver iGPU Ice Lake per Windows 7. Si resta su Standard VGA, senza Aero né accelerazione. Finestre, scorrimento e video vanno a scatti. Si può alleggerire con un tema Basic, «Adjust for best performance», accelerazione grafica di Supermium disattivata e YouTube a 360p/480p. Non installare i pacchetti grafici Intel per Windows 10 (rischio Code 43).
2. **Wi-Fi e Bluetooth interni** (Intel AC 9461): nessun driver Win7 ufficiale né modificato affidabile. Per l'indipendenza dal tethering serve una chiavetta Wi-Fi USB con driver Win7 (tipicamente Realtek o chipset «N» classici) oppure Ethernet USB. Sostituire la schedina M.2 è spesso impratico (formato CNVi / saldatura).
3. **Touchpad:** probabilmente I2C HID / ASUS Precision Touchpad, con driver solo Win10/11. Lo stato reale su questa macchina è stato verificato e risulta non funzionante; un mouse USB resta la scelta sicura.
4. Voci gialle SMBus `34A3` e SPI `34A4`: cosmetiche.
5. Windows 7 è fuori supporto. Meglio non usare Windows Update in modo massiccio su questa installazione (può riscrivere file di boot o rompere firme). Restano gli `.msu` già slipstreamati.
6. `testsigning` resta acceso. FlashBoot e `acpi.sys` sono binari Microsoft modificati da terzi: Windows Defender sul PC di preparazione può segnalarli.
7. Questa installazione è standalone: Windows 11 è stato cancellato. Un dual-boot richiederebbe un altro percorso (backup EFI, attenzione a `bootmgfw` e BitLocker) e non è stato portato a termine qui. Vedi [scripts/post_install_laptop.txt](scripts/post_install_laptop.txt).

## Script in questo repository

| File | Ruolo |
| --- | --- |
| [scripts/build_win7_iso.cmd](scripts/build_win7_iso.cmd) / [scripts/build_win7_iso.ps1](scripts/build_win7_iso.ps1) | Preparazione dell'ISO (aggiornamenti, driver xHCI, export Professional) sul PC di lavoro |
| [scripts/fix_acpi_e_diagnosi.txt](scripts/fix_acpi_e_diagnosi.txt) | Diagnosi del blocco dopo `disk.sys`, prove BCD e integrazione di `acpi.sys` |
| [scripts/boot7.cmd](scripts/boot7.cmd) | Copia di FlashBoot sull'ESP e creazione manuale del BCD (`S:` / `W:`) |
| [scripts/post_install_laptop.txt](scripts/post_install_laptop.txt) | Note per un eventuale dual-boot e UefiSeven sulla EFI interna (percorso non seguito fino in fondo) |

Copiare `build_win7_iso.cmd` e `build_win7_iso.ps1` in `D:\Win7Work`. Non sono inclusi ISO, WIM, `.efi` o `acpi.sys`.

## Crediti

Questo risultato poggia sul lavoro di chi ha pubblicato gli strumenti usati.

- [FlashBoot 3.4b / SevenESPManager (Sevoos)](https://github.com/Sevoos/SevenESPManager)
- [Win7_ACPI_Patch (Rireki)](https://github.com/Rireki/Win7_ACPI_Patch)
- [USB 3 xHCI driver stack for Windows 7 (daniel_k)](https://forums.mydigitallife.net/threads/usb-3-xhci-driver-stack-for-windows-7.81934/)
- [Supermium (win32ss)](https://github.com/win32ss/supermium)
- [UefiSeven 1.30 (manatails)](https://github.com/manatails/uefiseven) — provato, poi sostituito da FlashBoot su questo hardware

Utile anche il contesto delle guide win-raid su ACPI 0xA5, il thread e il pastebin di daniel_k sul driver xHCI, e le discussioni di chi ha già usato FlashBoot su Ice Lake in UEFI puro (in questa sessione è stata una pista su un Lenovo con lo stesso tipo di CPU a suggerire il cambio di bootloader).

---

Resoconto redatto il 16 novembre 2026 (Europe/Rome), a partire dal lavoro sul VivoBook X509JA del 15–16 novembre 2026. Include solo quanto risulta dal diario di quella sessione e dai file di lavoro. Dove un dettaglio veniva solo da una schermata (errori `bcdboot` «EX bins» e `c000003a`, codice `0xc000000f`, `0x8007054F`) è indicato come tale. Non sono stati inventati modello esatto di CPU, esito del test audio, funzionamento del touchpad, né il metodo preciso con cui l'attivazione retail è infine riuscita.
