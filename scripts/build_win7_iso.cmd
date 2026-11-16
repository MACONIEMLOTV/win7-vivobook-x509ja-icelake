@echo off
rem ==========================================================================
rem  build_win7_iso.cmd
rem  Avvia build_win7_iso.ps1 come Amministratore, senza dover cambiare
rem  la ExecutionPolicy di PowerShell. Tieni i due file nella stessa cartella
rem  (consigliato: D:\Win7Work).
rem ==========================================================================
setlocal
set "PS1=%~dp0build_win7_iso.ps1"
if not exist "%PS1%" (
  echo File non trovato: %PS1%
  echo Metti build_win7_iso.ps1 nella stessa cartella di questo file.
  pause
  exit /b 1
)

rem Controllo permessi di amministratore
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Servono i permessi di amministratore: confermo la richiesta di Windows...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
endlocal
