@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-agents.ps1" %*
pause
