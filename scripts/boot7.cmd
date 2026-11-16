@echo off
setlocal
set U=%~d0
set G={11111111-1111-1111-1111-111111111111}
set BCD=S:\EFI\Microsoft\Boot\BCD
echo Chiavetta: %U%
if not exist W:\Windows\System32\winload.efi (echo ERRORE: W:\Windows non trovato & goto fine)
if not exist S:\ (echo ERRORE: S: non trovato & goto fine)
if not exist %U%\efi\boot\bootx64.efi (echo ERRORE: FlashBoot non trovato su %U% & goto fine)

echo == Copia file di avvio ==
xcopy W:\Windows\Boot\EFI S:\EFI\Microsoft\Boot\ /s /e /h /i /y >nul
if not exist S:\EFI\Boot mkdir S:\EFI\Boot
copy /y %U%\efi\boot\bootx64.efi S:\EFI\Microsoft\Boot\bootmgfw.efi
copy /y %U%\efi\boot\bootx64.efi S:\EFI\Boot\bootx64.efi

echo == Creazione BCD ==
if exist %BCD% (attrib -h -s -r %BCD% & del /f %BCD%)
bcdedit /createstore %BCD%
bcdedit /store %BCD% /create {bootmgr} /d "Windows Boot Manager"
bcdedit /store %BCD% /set {bootmgr} device partition=S:
bcdedit /store %BCD% /set {bootmgr} path \EFI\Microsoft\Boot\bootmgfw.efi
bcdedit /store %BCD% /set {bootmgr} locale en-US
bcdedit /store %BCD% /set {bootmgr} timeout 5
bcdedit /store %BCD% /create %G% /d "Windows 7" /application osloader
bcdedit /store %BCD% /set %G% device partition=W:
bcdedit /store %BCD% /set %G% osdevice partition=W:
bcdedit /store %BCD% /set %G% path \Windows\system32\winload.efi
bcdedit /store %BCD% /set %G% systemroot \Windows
bcdedit /store %BCD% /set %G% locale en-US
bcdedit /store %BCD% /set %G% testsigning on
bcdedit /store %BCD% /set %G% nx OptIn
bcdedit /store %BCD% /set {bootmgr} default %G%
bcdedit /store %BCD% /set {bootmgr} displayorder %G%

echo.
echo == Risultato ==
bcdedit /store %BCD% /enum all
:fine
echo.
echo Fatto. Manda una foto di questa schermata.
pause
