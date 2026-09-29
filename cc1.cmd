@echo off
rem llama-server（http://127.0.0.1:8080）に接続して Claude Code を起動する
rem 先に tools\50_run\run-server-cc.cmd でサーバを起動しておく
rem 使い方: cc1 -p "こんにちは"   （引数はそのまま claude に渡す）
rem 環境変数はこの cmd の中だけで効く。呼び出し元のシェルには残らない
rem
rem ホームを W:\temp\cc1-home に替え、利用者の共通ルール（CLAUDE.md）・メモリ・フックを読ませない。
rem 読ませると最初の要求が約 60,000 トークンになり、このPCでは 1 往復に数分かかる（ルールなしで約 20,000）
rem 帰属ヘッダを切る設定（CLAUDE_CODE_ATTRIBUTION_HEADER=0）は、ホームが変わるとプロジェクトの設定しか効かないため、ここでも渡す
setlocal
set "ANTHROPIC_BASE_URL=http://127.0.0.1:8080"
set "ANTHROPIC_AUTH_TOKEN=llamacpp"
set "ANTHROPIC_MODEL=gemma-4-E4B-it-Q4_K_M"
set "ANTHROPIC_SMALL_FAST_MODEL=gemma-4-E4B-it-Q4_K_M"
set "CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536"
set "API_TIMEOUT_MS=3600000"
set "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
set "CLAUDE_CODE_ATTRIBUTION_HEADER=0"
if not exist "W:\temp\cc1-home\" mkdir "W:\temp\cc1-home"
set "USERPROFILE=W:\temp\cc1-home"
set "HOME=W:\temp\cc1-home"
call claude %*
exit /b %errorlevel%
