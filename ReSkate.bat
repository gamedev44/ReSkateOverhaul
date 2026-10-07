@echo off
setlocal
cd /d "%~dp0"
title ReSkate

set "DRIVEARG="
echo %~1| findstr /R /I "^[A-Z]$" >nul && set "DRIVEARG=-Drive %~1"

start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Source\Launch\Select.ps1" %DRIVEARG%

endlocal
