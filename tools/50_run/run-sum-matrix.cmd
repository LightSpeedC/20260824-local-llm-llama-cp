@echo off
rem sum を決めた組み合わせだけ流す。引数はそのまま ps1 に渡す（例: -Combos "gemma-4-E4B:cc,pi" -LlamaDir llama.cpp-b11320-vulkan -TimeoutSec 1800）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-sum-matrix.ps1" %*
pause
