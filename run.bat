@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
if exist "%~dp0index.html" start "" "%~dp0index.html"
