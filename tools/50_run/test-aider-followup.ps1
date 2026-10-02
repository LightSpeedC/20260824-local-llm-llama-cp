param(
	[string]$Only = 'gemma-4-E4B',
	# 空なら config.cmd の LLM_MODEL_DIR（paths.ps1）
	[string]$ModelDir = '',
	[int]$Repeat = 3,
	[int]$Ctx = 65536,
	[int]$TimeoutSec = 600,
	[int]$Port = 8080
)
# Aider に sum.js を書かせたあと、別の指示で実行・テストさせると node を実行するかを試す（i261001-01）
# 1 回目の指示は sum の試験と同じ。2 回目は同じ作業フォルダで Aider を起動し直して渡す
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sum-judge.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')
$root = $LlmRoot
if (-not $ModelDir) { $ModelDir = $LlmModelDir }
$exe = Join-Path $root 'bin/llama.cpp/llama-server.exe'
$logDir = Join-Path $root 'logs/test-aider-followup'
New-Item -ItemType Directory -Force $logDir | Out-Null
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultFile = Join-Path $logDir "$runStamp-results.jsonl"
$utf8 = New-Object Text.UTF8Encoding($false)
$work = $LlmSandbox
$aider = Join-Path $env:USERPROFILE '.local/bin/aider.exe'
$followups = [ordered]@{
	run  = 'node sum を実行して、表示された結果を教えて'
	test = 'sum.js をテストして'
}

$m = Get-ChildItem $ModelDir -Recurse -Filter *.gguf | Where-Object { $_.BaseName -like "*$Only*" -and $_.Name -notmatch 'mmproj' } | Select-Object -First 1
if (-not $m) { throw 'モデルが見つかりません' }
$name = $m.BaseName
$ngl = if ($m.Length -le 3.2GB) { '-ngl 99' } else { '' }
$tpl = Join-Path $PSScriptRoot "templates/$name.jinja"
$tplArg = if (Test-Path $tpl) { "--chat-template-file `"$tpl`"" } else { '' }
$argList = "-m `"$($m.FullName)`" -c $Ctx -np 1 $ngl -nkvo -ctk q8_0 -ctv q8_0 -fa on $tplArg --reasoning off --alias $name --host 127.0.0.1 --port $Port"

function Invoke-Aider([string]$prompt, [string]$tag, [string]$extra = '') {
	$out = Join-Path $logDir "$tag-out.txt"
	$p = $prompt.Replace('"', "'")
	$cmdLine = "`"$aider`" --model `"openai/$name`" --openai-api-base http://127.0.0.1:$Port/v1 --openai-api-key llamacpp --no-git --yes-always --no-show-model-warnings --no-check-update --no-pretty $extra --message `"$p`""
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$cc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/d /s /c `"$cmdLine < nul > `"$out`" 2>&1`"" -WorkingDirectory $work -PassThru -WindowStyle Hidden
	$done = $cc.WaitForExit($TimeoutSec * 1000)
	if (-not $done) { taskkill /PID $cc.Id /T /F | Out-Null }
	$text = if (Test-Path $out) { [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8) } else { '' }
	return [ordered]@{ status = $(if ($done) { 'ok' } else { 'timeout' }); sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1); text = $text }
}

Write-Host "=== aider / $name（2 回目の指示を足す）"
$srv = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $logDir "$runStamp-server.log") -RedirectStandardOutput (Join-Path $logDir "$runStamp-server.log.out")
try {
	$ready = $false
	for ($i = 0; $i -lt 150; $i++) {
		Start-Sleep -Seconds 2
		if ($srv.HasExited) { break }
		try { $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2; if ($h.status -eq 'ok') { $ready = $true; break } } catch {}
	}
	if (-not $ready) { throw 'サーバが起動しない' }
	foreach ($k in $followups.Keys) {
		for ($n = 1; $n -le $Repeat; $n++) {
			if (Test-Path $work) { Get-ChildItem -LiteralPath $work -Force | Remove-Item -Recurse -Force }
			New-Item -ItemType Directory -Force $work | Out-Null
			Copy-Item (Join-Path $root 'README.html') $work
			$tag = "$runStamp-$k-$n"
			$first = Invoke-Aider $SumPrompt "$tag-1"
			# 起動し直した Aider は前の会話も作業フォルダの中身も知らない（git なし・リポジトリマップなし）。sum.js を会話に載せて渡す
			$second = Invoke-Aider $followups[$k] "$tag-2" '--file sum.js'
			$file = Test-Path (Join-Path $work 'sum.js')
			$ran = Test-SumTrace $second.text
			# 「Tokens: 629 sent, 55 received」の 55 を答えと取り違えないよう、その行を除いて見る
			$answered = ($second.text -replace '(?m)^Tokens:.*$', '') -match '(?<!\d)55(?!\d)'
			$pass = $file -and $ran -and $answered
			Write-Host "  $k $n 回目: 1 回目 $($first.sec) 秒・2 回目 $($second.status) $($second.sec) 秒 合格 $pass（作成 $file・実行 $ran・55 $answered）"
			$rec = [ordered]@{ model = $name; followup = $k; n = $n; prompt2 = $followups[$k]; first = $first.sec; second = $second.sec; status = $second.status; file = $file; ran = $ran; answered = $answered; pass = $pass }
			[IO.File]::AppendAllText($resultFile, ($rec | ConvertTo-Json -Compress) + "`n", $utf8)
		}
	}
} finally {
	if (-not $srv.HasExited) { taskkill /PID $srv.Id /T /F | Out-Null }
}
Write-Host "結果: $($resultFile.Replace($root + [IO.Path]::DirectorySeparatorChar, ''))"
