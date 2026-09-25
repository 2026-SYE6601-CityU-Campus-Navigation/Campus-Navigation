@echo off
rem CityU Campus Navigation - Local AI one-click installer
rem Double-click this file to run. It launches the PowerShell script below.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_ollama.ps1"
if errorlevel 1 (
  echo.
  echo Script finished with errors. See the messages above.
)
pause
