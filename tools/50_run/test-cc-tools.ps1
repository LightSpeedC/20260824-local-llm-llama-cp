param(
	[string]$ModelDir = 'C:\AI_Models',
	[double]$MaxSizeGB = 10,
	[int]$Ctx = 65536,
	[int]$TimeoutSec = 600,
	[int]$Port = 8080,
	[string]$Only = '',
	[switch]$UseTemplates,
	[string]$Tests = 'read,write',
	[switch]$NoRules,
	[string]$ExtraArgs = ''
)
# 10GB 以下の手持ちモデルを 1 本ずつ llama-server で起動し、Claude Code からファイルの読み・書きができるかを試す
# 結果は logs/test-cc-tools/ に 1 モデル 1 行の JSON Lines で追記する
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$exe = Join-Path $root 'bin/llama.cpp/llama-server.exe'
$logDir = Join-Path $root 'logs/test-cc-tools'
New-Item -ItemType Directory -Force $logDir | Out-Null
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultFile = Join-Path $logDir "$runStamp-results.jsonl"
$utf8 = New-Object Text.UTF8Encoding($false)
# エージェントは作業用のコピーの中で動かす。プロジェクトの本物のファイルを書き換えさせない（Aider が README.html を上書きした）
# git のリポジトリの外に置く。中に置くと、モデルがリポジトリの root を推測して本物を読みにいく
# 中身は 1 問ごとに消すので、専用のフォルダにする（W:/temp そのものにしない）
$work = 'W:/temp/llama-cp-sandbox'
function Reset-Sandbox {
	if (Test-Path $work) { Get-ChildItem -LiteralPath $work -Force | Remove-Item -Recurse -Force }
	New-Item -ItemType Directory -Force (Join-Path $work 'tmp'), (Join-Path $work '.claude') | Out-Null
	Copy-Item (Join-Path $root 'README.html') $work
	Copy-Item (Join-Path $root '.claude/settings.json') (Join-Path $work '.claude')
}

$models = Get-ChildItem $ModelDir -Recurse -Filter *.gguf |
	Where-Object { $_.Name -notmatch 'mmproj' -and $_.Length -lt $MaxSizeGB * 1GB } |
	Sort-Object Length
if ($Only) {
	# カンマ区切りで複数を指定できる。どれかを名前に含むものだけを対象にする
	$keys = $Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
	# 並びは -Only に書いた順にする（早く終わりそうなものから流せるように）
	$all = $models
	$models = foreach ($k in $keys) { $all | Where-Object { $_.BaseName -like "*$k*" } }
	$models = $models | Select-Object -Unique
}
if (-not $models) { throw 'モデルが見つかりません' }
Write-Host "対象 $(@($models).Count) 本"

# ルールなし: 空のホームに向け、利用者の CLAUDE.md・メモリ・フックを読ませない
# ホームもプロジェクトの外に置く。Claude Code は指示文にメモリの置き場（ホームの下）を書くため、
# プロジェクトの中に置くと、そのパスからモデルがプロジェクト本体を推測して書きにいく
$noRulesHome = 'W:/temp/llama-cp-home'
if ($NoRules) {
	New-Item -ItemType Directory -Force $noRulesHome | Out-Null
	$resultFile = $resultFile.Replace('-results.jsonl', '-norules-results.jsonl')
}

function Invoke-Claude([string]$prompt, [string]$tag) {
	if ($NoRules) { $tag = "$tag-norules" }
	$pf = Join-Path $logDir "$tag-prompt.txt"
	$out = Join-Path $logDir "$tag-raw.json"
	$err = Join-Path $logDir "$tag-raw.err"
	[IO.File]::WriteAllText($pf, $prompt, $utf8)
	$sw = [Diagnostics.Stopwatch]::StartNew()
	# 質問は標準入力、出力はファイルで受ける（コマンド行やパイプを通すと CP932 に化ける）
	$saved = @{ USERPROFILE = $env:USERPROFILE; HOME = $env:HOME }
	if ($NoRules) { $env:USERPROFILE = $noRulesHome; $env:HOME = $noRulesHome }
	$cc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/d /c claude -p --max-turns 6 --permission-mode acceptEdits --output-format json < `"$pf`" > `"$out`" 2> `"$err`"" -WorkingDirectory $work -PassThru -WindowStyle Hidden
	$env:USERPROFILE = $saved.USERPROFILE; $env:HOME = $saved.HOME
	$done = $cc.WaitForExit($TimeoutSec * 1000)
	$sw.Stop()
	if (-not $done) { taskkill /PID $cc.Id /T /F | Out-Null }
	$r = [ordered]@{ status = $(if ($done) { 'ok' } else { 'timeout' }); sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1); turns = $null; is_error = $null; result = '' }
	if ($done -and (Test-Path $out)) {
		$line = [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8) -split "`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1
		try {
			$j = $line | ConvertFrom-Json
			$r.turns = $j.num_turns; $r.is_error = $j.is_error; $r.result = "$($j.result)"; $r.input_tokens = $j.usage.input_tokens
		} catch { $r.status = 'parse-error' }
	}
	return $r
}

$readExpect = 'ローカルLLM 実行環境'
foreach ($m in $models) {
	$name = $m.BaseName
	$tag = "$runStamp-$name"
	$sizeGB = [Math]::Round($m.Length / 1GB, 2)
	# 3.2GB 以下は全層 GPU、それより大きいものは -ngl を渡さず llama-server の自動配置に任せる
	$ngl = if ($m.Length -le 3.2GB) { '-ngl 99' } else { '' }
	# 差し替えたチャットテンプレートがあれば使う（templates/<モデル名>.jinja）
	$tpl = Join-Path $PSScriptRoot "templates/$name.jinja"
	$tplArg = if ($UseTemplates -and (Test-Path $tpl)) { "--chat-template-file `"$tpl`"" } else { '' }
	$argList = "-m `"$($m.FullName)`" -c $Ctx -np 1 $ngl -nkvo -ctk q8_0 -ctv q8_0 -fa on $tplArg $ExtraArgs --alias $name --host 127.0.0.1 --port $Port"
	Write-Host "=== $name（$sizeGB GB）"
	$rec = [ordered]@{ model = $name; sizeGB = $sizeGB; server = $argList; load = ''; read = $null; write = $null }
	$srvLog = Join-Path $logDir "$tag-server.log"
	$srv = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardError $srvLog -RedirectStandardOutput "$srvLog.out"
	try {
		$ready = $false
		for ($i = 0; $i -lt 150; $i++) {
			Start-Sleep -Seconds 2
			if ($srv.HasExited) { break }
			try { $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2; if ($h.status -eq 'ok') { $ready = $true; break } } catch {}
		}
		if (-not $ready) {
			$rec.load = if ($srv.HasExited) { 'サーバが終了' } else { '準備が 300 秒で整わない' }
			Write-Host "  起動失敗: $($rec.load)"
			continue
		}
		$rec.load = 'ok'
		$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$Port"
		$env:ANTHROPIC_AUTH_TOKEN = 'llamacpp'
		$env:ANTHROPIC_MODEL = $name
		$env:ANTHROPIC_SMALL_FAST_MODEL = $name
		$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$Ctx"
		$env:API_TIMEOUT_MS = "$($TimeoutSec * 1000)"
		$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

		# 読み: 答えは README を読まないと分からない
		if ($Tests -match 'read') {
		Reset-Sandbox
		$r = Invoke-Claude "README.html を Read ツールで読み、最初の h1 要素の文字列だけを答えてください。" "$tag-read"
		$r.pass = ($r.status -eq 'ok' -and $r.result -like "*$readExpect*")
		$rec.read = $r
		Write-Host "  読み: $($r.status) $($r.sec) 秒 ターン $($r.turns) 合格 $($r.pass)"
		}
		if ($Tests -notmatch 'write') { continue }

		# 書き: 決めた中身のファイルが実際にできたかで判定する
		Reset-Sandbox
		$wf = Join-Path $work "tmp/cc-write-$name.txt"
		if (Test-Path $wf) { Remove-Item -LiteralPath $wf }
		$token = "written-by-$name-$runStamp"
		$r = Invoke-Claude "Write ツールで tmp/cc-write-$name.txt というファイルを作り、中身を次の1行だけにしてください: $token" "$tag-write"
		$got = if (Test-Path $wf) { ([IO.File]::ReadAllText($wf, [Text.Encoding]::UTF8)).Trim() } else { '' }
		$r.pass = ($got -eq $token)
		$r.file = $(if (Test-Path $wf) { 'あり' } else { 'なし' })
		$rec.write = $r
		Write-Host "  書き: $($r.status) $($r.sec) 秒 ターン $($r.turns) 合格 $($r.pass)"
		if (Test-Path $wf) { Remove-Item -LiteralPath $wf }
	} finally {
		if (-not $srv.HasExited) { taskkill /PID $srv.Id /T /F | Out-Null }
		Start-Sleep -Seconds 3
		[IO.File]::AppendAllText($resultFile, (($rec | ConvertTo-Json -Compress -Depth 4) + "`n"), $utf8)
	}
}
Write-Host "結果: logs/test-cc-tools/$runStamp-results.jsonl"
