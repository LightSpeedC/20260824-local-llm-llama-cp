@echo off
REM Claude Code 向けに llama-server を起動する（Qwen3-4B / コンテキスト 65536）
REM Claude Code は最初の要求だけで約 63,000 トークンある
REM VRAM 4GB には KV キャッシュが載らないため、RAM 側に置く（-nkvo）
REM 停止するには このウィンドウで Ctrl+C
echo Claude Code 向けに llama-server を起動します (http://127.0.0.1:8080)
"%~dp0..\..\bin\llama.cpp\llama-server.exe" ^
  -m "C:\AI_Models\qwen\Qwen3-4B-Instruct-2507-GGUF\Qwen3-4B-Instruct-2507-Q4_K_M.gguf" ^
  -ngl 99 ^
  -c 65536 ^
  -np 1 ^
  -nkvo ^
  -ctk q8_0 -ctv q8_0 ^
  -fa on ^
  --alias qwen3-4b-instruct-2507 ^
  --host 127.0.0.1 ^
  --port 8080
pause
