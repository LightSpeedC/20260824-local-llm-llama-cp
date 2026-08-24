@echo off
REM Qwen3.5-9B を部分オフロードで起動 (実測 8.1 tok/s / 待てる作業向け)
REM 停止するには このウィンドウで Ctrl+C
echo llama-server を起動します (http://127.0.0.1:8080)
"%~dp0..\bin\llama.cpp\llama-server.exe" ^
  -m "C:\AI_Models\qwen\Qwen3.5-9B-GGUF\Qwen3.5-9B-Q4_K_M.gguf" ^
  -ngl 24 ^
  -ctk q8_0 -ctv q8_0 -fa 1 ^
  -c 4096 ^
  --host 127.0.0.1 ^
  --port 8080
pause
