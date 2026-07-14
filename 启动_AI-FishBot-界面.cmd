@echo off
setlocal
cd /d "%~dp0"
start "AI-FishBot" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0AI-FishBot.GUI.ps1"
endlocal
