@echo off
setlocal
title LeanADB Installer by leodroid99

if not exist "%~dp0LeanADB.ps1" (
  echo LeanADB.ps1 was not found next to this installer.
  echo Extract the entire ZIP to a folder before running Install.cmd.
  pause
  exit /b 2
)

if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Install
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Install -OfflineZipPath "%~f1"
)
set "LEANADB_INSTALL_EXIT=%ERRORLEVEL%"
if "%LEANADB_INSTALL_EXIT%"=="20" exit /b 0
if "%LEANADB_INSTALL_EXIT%"=="0" exit /b 0

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action FailureHelp
pause
exit /b %LEANADB_INSTALL_EXIT%
