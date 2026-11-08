@echo off
rem Installs Computer Help for this Windows user and puts a "Computer Help" icon on the desktop.
rem Put a filled-in config.json next to this file first (copy config.example.json).
if not exist "%~dp0config.json" (
  echo config.json is missing. Copy config.example.json to config.json and fill it in.
  pause
  exit /b 1
)
set "DEST=%LOCALAPPDATA%\ComputerHelp"
if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0Launcher.ps1" "%DEST%\" >nul
copy /Y "%~dp0ComputerHelp.ps1" "%DEST%\" >nul
copy /Y "%~dp0config.json" "%DEST%\" >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop') + '\Computer Help.lnk');" ^
  "$s.TargetPath = 'powershell.exe';" ^
  "$s.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"' + $env:LOCALAPPDATA + '\ComputerHelp\Launcher.ps1\"';" ^
  "$s.IconLocation = 'shell32.dll,23';" ^
  "$s.Save()"
echo Done. There is now a "Computer Help" icon on the desktop.
pause
