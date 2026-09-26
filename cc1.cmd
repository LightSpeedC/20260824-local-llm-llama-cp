@echo off
rem llama-server（http://127.0.0.1:8080）に接続して Claude Code を起動する
rem 先に tools\50_run\run-server-cc.cmd でサーバを起動しておく
rem 使い方: cc1 -p "こんにちは"   （引数はそのまま claude に渡す）
rem 環境変数はこの cmd の中だけで効く。呼び出し元のシェルには残らない
setlocal
set "ANTHROPIC_BASE_URL=http://127.0.0.1:8080"
set "ANTHROPIC_AUTH_TOKEN=llamacpp"
set "ANTHROPIC_MODEL=qwen3-4b-instruct-2507"
set "ANTHROPIC_SMALL_FAST_MODEL=qwen3-4b-instruct-2507"
set "CLAUDE_CODE_MAX_CONTEXT_TOKENS=65536"
set "API_TIMEOUT_MS=3600000"
call claude %*
exit /b %errorlevel%
