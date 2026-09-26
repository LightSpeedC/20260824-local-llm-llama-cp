@echo off
REM 速度計測: 第9章の No1 相当 (Qwen3-4B / Q4_K_M / 全層GPU)
echo llama-bench を実行します。数分かかります。
"%~dp0..\..\bin\llama.cpp\llama-bench.exe" ^
  -m "C:\AI_Models\qwen\Qwen3-4B-Instruct-2507-GGUF\Qwen3-4B-Instruct-2507-Q4_K_M.gguf" ^
  -ngl 99
pause