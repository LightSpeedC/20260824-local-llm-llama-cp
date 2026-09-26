@echo off
REM Qwen3-4B-Instruct-2507 を全層GPUで起動する
REM 停止するには このウィンドウで Ctrl+C
echo llama-server を起動します (http://127.0.0.1:8080)
"%~dp0..\..\bin\llama.cpp\llama-server.exe" ^
  -m "C:\AI_Models\qwen\Qwen3-4B-Instruct-2507-GGUF\Qwen3-4B-Instruct-2507-Q4_K_M.gguf" ^
  -ngl 99 ^
  -c 8192 ^
  --host 127.0.0.1 ^
  --port 8080
pause