@echo off
setlocal
cd /d "%~dp0"
set "startOptions="
if defined AIFISHBOT_LAUNCHER_WAIT set "startOptions=/b /wait"
start "AI-FishBot" %startOptions% "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0AI-FishBot.GUI.ps1" -DataRoot "%~dp0." %*
set "exitCode=%errorlevel%"
endlocal & exit /b %exitCode%
