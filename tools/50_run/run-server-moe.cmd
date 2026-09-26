@echo off
REM gpt-oss-20b を MoEオフロードで起動 (実測 5.9 tok/s / 他アプリを閉じて使う)
REM 停止するには このウィンドウで Ctrl+C
echo llama-server を起動します (http://127.0.0.1:8080)
"%~dp0..\..\bin\llama.cpp\llama-server.exe" ^
  -m "C:\AI_Models\OpenAI\gpt-oss-20b-GGUF\gpt-oss-20b-MXFP4.gguf" ^
  -ngl 99 ^
  --n-cpu-moe 18 ^
  -c 4096 ^
  --host 127.0.0.1 ^
  --port 8080
pause
