@echo off
rem Start services and open the public URL.
setlocal
set "PUBLIC_URL=http://8.166.118.106"
if not exist "%~dp0windows-start.ps1" (
  echo ERROR: windows-start.ps1 not found
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '%~dp0'; .\windows-start.ps1"
if errorlevel 1 (
  echo ERROR: service start failed
  pause
  exit /b 1
)
echo Service started.
echo Public URL: %PUBLIC_URL%
echo Opening browser in 5 seconds...
timeout /t 5 /nobreak
start "" "%PUBLIC_URL%"
echo Done. Press any key to close.
pause >nul
endlocal
