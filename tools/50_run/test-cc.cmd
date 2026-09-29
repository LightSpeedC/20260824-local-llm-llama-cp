@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-cc.ps1" %*
pause
