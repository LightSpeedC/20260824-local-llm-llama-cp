@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch-thermal.ps1" %*
pause
