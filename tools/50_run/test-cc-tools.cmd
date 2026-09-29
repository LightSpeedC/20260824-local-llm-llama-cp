@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-cc-tools.ps1" %*
pause
