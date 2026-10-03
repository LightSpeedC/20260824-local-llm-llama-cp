@echo off
REM Claude Code 向けに llama-server を起動する（gemma-4-E4B / コンテキスト 65536 / 思考なし）
REM 試験で読み・書きとも合格した設定（r260929-01）
REM VRAM 4GB には KV キャッシュが載らないため、RAM 側に置く（-nkvo）
REM 4.97 GB あり全層は GPU に載らないので、-ngl は渡さず自動配置に任せる
REM 停止するには このウィンドウで Ctrl+C
echo Claude Code 向けに llama-server を起動します (http://127.0.0.1:8080)
"%~dp0..\..\bin\llama.cpp\llama-server.exe" ^
  -m "C:\AI-models\Gemma\gemma-4-E4B-it-GGUF\gemma-4-E4B-it-Q4_K_M.gguf" ^
  -c 65536 ^
  -np 1 ^
  -nkvo ^
  -ctk q8_0 -ctv q8_0 ^
  -fa on ^
  --reasoning off ^
  --alias gemma-4-E4B-it-Q4_K_M ^
  --host 127.0.0.1 ^
  --port 8080
pause
