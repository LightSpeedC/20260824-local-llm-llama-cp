@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make-offline-bundle.ps1" %*
pause
