@echo off
rem —á: start-agent.cmd -Agent pi -Model gemma-4-E4B-it-Q4_K_M
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-agent.ps1" %*
pause
