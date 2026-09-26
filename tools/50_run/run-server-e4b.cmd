@echo off
REM gemma-4-E4B-it を全層GPUで起動 (実測 45 tok/s / PLEはCPU側に分離される)
REM 停止するには このウィンドウで Ctrl+C
echo llama-server を起動します (http://127.0.0.1:8080)
"%~dp0..\..\bin\llama.cpp\llama-server.exe" ^
  -m "C:\AI_Models\gemma\gemma-4-E4B-it-GGUF\gemma-4-E4B-it-Q4_K_M.gguf" ^
  -ngl 99 ^
  -c 8192 ^
  --host 127.0.0.1 ^
  --port 8080
pause
