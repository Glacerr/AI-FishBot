@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0AI-FishBot.GUI.ps1"
