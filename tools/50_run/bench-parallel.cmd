@echo off
REM 並列スロットのスループットを測る（p260825-01）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bench-parallel.ps1" %*
pause
