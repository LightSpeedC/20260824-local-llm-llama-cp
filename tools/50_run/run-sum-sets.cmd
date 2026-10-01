@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-sum-sets.ps1" %*
pause
