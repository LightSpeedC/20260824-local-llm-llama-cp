param(
	[string]$Model = 'C:\AI_Models\qwen\Qwen3-4B-Instruct-2507-GGUF\Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
	[string]$Alias = 'qwen3-4b-instruct-2507',
	[int]$Ctx = 65536,
	[string]$ServerArgs = '-ngl 99 -nkvo -ctk q8_0 -ctv q8_0 -fa on',
	[string]$Prompt = 'README.html の h1 見出しを1つだけ答えてください。',
	[int]$TimeoutSec = 900,
	[int]$Port = 8080
)
# llama-server を起動し、環境変数で接続先を切り替えた Claude Code に1問投げて、応答と所要時間を記録する
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$exe = Join-Path $root 'bin/llama.cpp/llama-server.exe'
$logDir = Join-Path $root 'logs/test-cc'
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$srvLog = Join-Path $logDir "$stamp-server.log"
$ccOut = Join-Path $logDir "$stamp-claude.txt"

if (-not (Test-Path $exe)) { throw "llama-server が見つかりません: bin/llama.cpp" }
if (-not (Test-Path $Model)) { throw "モデルが見つかりません: $Model" }

$argList = "-m `"$Model`" -c $Ctx -np 1 $ServerArgs --alias $Alias --host 127.0.0.1 --port $Port"
Write-Host "サーバ起動: $argList"
$srv = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardError $srvLog -RedirectStandardOutput "$srvLog.out"
try {
	$ready = $false
	for ($i = 0; $i -lt 180; $i++) {
		Start-Sleep -Seconds 2
		if ($srv.HasExited) { throw "サーバが起動中に終了しました（ログ: logs/test-cc/$stamp-server.log）" }
		try { $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2; if ($h.status -eq 'ok') { $ready = $true; break } } catch {}
	}
	if (-not $ready) { throw 'サーバの準備が 360 秒で整いませんでした' }
	Write-Host 'サーバ準備完了'

	$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$Port"
	$env:ANTHROPIC_AUTH_TOKEN = 'llamacpp'
	$env:ANTHROPIC_MODEL = $Alias
	$env:ANTHROPIC_SMALL_FAST_MODEL = $Alias
	$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$Ctx"
	$env:API_TIMEOUT_MS = "$($TimeoutSec * 1000)"
	$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

	$sw = [Diagnostics.Stopwatch]::StartNew()
	# claude は UTF-8 で出すので、PowerShell を通さず cmd のリダイレクトでファイルに落とし、UTF-8 として読む
	$rawOut = Join-Path $logDir "$stamp-raw.json"
	$rawErr = Join-Path $logDir "$stamp-raw.err"
	# 質問はコマンド行に載せると CP932 に化けるので、UTF-8 のファイルにして標準入力から渡す
	$promptFile = Join-Path $logDir "$stamp-prompt.txt"
	[IO.File]::WriteAllText($promptFile, $Prompt, (New-Object Text.UTF8Encoding($false)))
	$cc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/d /c claude -p --max-turns 5 --output-format json < `"$promptFile`" > `"$rawOut`" 2> `"$rawErr`"" -WorkingDirectory $root -PassThru -WindowStyle Hidden
	$done = $cc.WaitForExit($TimeoutSec * 1000)
	$sw.Stop()
	if ($done) { $status = 'ok' } else { taskkill /PID $cc.Id /T /F | Out-Null; $status = 'timeout' }
	$text = if (Test-Path $rawOut) { [IO.File]::ReadAllText($rawOut, [Text.Encoding]::UTF8) } else { '' }
	try {
		$j = ($text -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
		$text = "ターン数: $($j.num_turns) / is_error: $($j.is_error) / API 待ち: $([Math]::Round($j.duration_api_ms / 1000, 1)) 秒`n回答: $($j.result)"
	} catch {}
	$sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
	@("状態: $status", "所要: $sec 秒", "サーバ: $argList", "質問: $Prompt", '---', $text) | Set-Content -LiteralPath $ccOut -Encoding UTF8
	Write-Host "結果: $status（$sec 秒）"
	Write-Host $text
	Write-Host "記録: logs/test-cc/$stamp-claude.txt"
} finally {
	if (-not $srv.HasExited) { taskkill /PID $srv.Id /T /F | Out-Null }
	Write-Host 'サーバ停止'
}
