@echo off
rem Installs Computer Help for this Windows user: desktop icon, signed auto-update, 5-minute recorder.
rem Put a filled-in config.json next to this file first (copy config.example.json).
if not exist "%~dp0config.json" (
  echo config.json is missing. Copy config.example.json to config.json and fill it in.
  pause
  exit /b 1
)
set "DEST=%LOCALAPPDATA%\ComputerHelp"
if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0ComputerHelp.ps1" "%DEST%\" >nul
copy /Y "%~dp0config.json" "%DEST%\" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\ComputerHelp.ps1" -Setup
echo Done. There is now a "Computer Help" icon on the desktop.
pause
