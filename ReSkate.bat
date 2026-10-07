@echo off
setlocal
cd /d "%~dp0"
title ReSkate

if /I "%~1"=="allow" goto :allow

set "DRIVEARG="
echo %~1| findstr /R /I "^[A-Z]$" >nul && set "DRIVEARG=-Drive %~1"

start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Source\Launch\Select.ps1" %DRIVEARG%
goto :eof

:allow
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Source\Setup\Allow.ps1" -RepoRoot "%~dp0"
if errorlevel 1 (
  echo.
  echo Windows antivirus exclusion was not added.
  pause
  exit /b 1
)
goto :eof
