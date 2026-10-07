@echo off
setlocal
cd /d "%~dp0"
title ReSkate

if /I "%~1"=="allow" goto :allow

set "RESKATE_SCRIPT=%~dp0Source\Launch\Select.ps1"
set "EXTRA="
echo %~1| findstr /R /I "^[A-Z]$" >nul && set "EXTRA=-Drive %~1"
start "ReSkate" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%RESKATE_SCRIPT%" %EXTRA%
goto :eof

:allow
"%~dp0Source\Setup\ReSkate.exe" -RepoRoot "%~dp0"
if errorlevel 1 (
  echo.
  echo Windows antivirus exclusion was not added.
  pause
  exit /b 1
)
goto :eof
