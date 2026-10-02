param(
	[Parameter(Mandatory)][ValidateSet('pi', 'opencode', 'aider', 'codex')][string]$Agent,
	[Parameter(Mandatory)][string]$Only,
	[string]$ModelDir = 'C:\AI_Models',
	[int]$Ctx = 65536,
	[int]$TimeoutSec = 600,
	[int]$Port = 8080,
	[switch]$UseTemplates,
	[string]$ExtraArgs = '',
	[ValidateSet('responses', 'chat')][string]$CodexWireApi = 'responses',
	# read・write・sum（初期プログラミング）・echo（日本語が届くかの確認）をカンマ区切りで
	[string]$Tests = 'read,write',
	# 使う llama.cpp の bin 下のフォルダ名（Intel GPU は llama.cpp-b11320-vulkan、CPU だけは llama.cpp-b11320-cpu）
	[string]$LlamaDir = 'llama.cpp'
)
# Claude Code 以外のエージェント（Pi・OpenCode・Aider）を llama-server に繋ぎ、読み・書きができるかを試す
# 試験の中身は test-cc-tools.ps1 と同じ。結果は logs/test-agents/ に 1 モデル 1 行の JSON Lines で追記する
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sum-judge.ps1')
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$exe = Join-Path $root "bin/$LlamaDir/llama-server.exe"
$logDir = Join-Path $root 'logs/test-agents'
New-Item -ItemType Directory -Force $logDir | Out-Null
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultFile = Join-Path $logDir "$runStamp-$Agent-results.jsonl"
if ($LlamaDir -ne 'llama.cpp') { $resultFile = $resultFile.Replace('-results.jsonl', "-$LlamaDir-results.jsonl") }
$utf8 = New-Object Text.UTF8Encoding($false)
# エージェントは作業用のコピーの中で動かす。プロジェクトの本物のファイルを書き換えさせない（Aider が README.html を上書きした）
# git のリポジトリの外に置く。中に置くと、モデルがリポジトリの root を推測して本物を読みにいく
# 中身は 1 問ごとに消すので、専用のフォルダにする（W:/temp そのものにしない）
$work = 'W:/temp/llama-cp-sandbox'
function Reset-Sandbox {
	if (Test-Path $work) { Get-ChildItem -LiteralPath $work -Force | Remove-Item -Recurse -Force }
	New-Item -ItemType Directory -Force (Join-Path $work 'tmp') | Out-Null
	Copy-Item (Join-Path $root 'README.html') $work
}
# 設定は空のホームに置く。利用者のいつもの設定には触れない
# プロジェクトの外に置く（中に置くと、そのパスからモデルがプロジェクトの場所を推測することがある）
$agentHome = "W:/temp/llama-cp-agent-home/$Agent"
New-Item -ItemType Directory -Force $agentHome | Out-Null
$aider = Join-Path $env:USERPROFILE '.local/bin/aider.exe'

$keys = $Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$all = Get-ChildItem $ModelDir -Recurse -Filter *.gguf | Where-Object { $_.Name -notmatch 'mmproj' }
$models = foreach ($k in $keys) { $all | Where-Object { $_.BaseName -like "*$k*" } }
$models = $models | Select-Object -Unique
if (-not $models) { throw 'モデルが見つかりません' }

function Invoke-Agent([string]$prompt, [string]$name, [string]$tag, [switch]$Trace) {
	$out = Join-Path $logDir "$tag-out.txt"
	$err = Join-Path $logDir "$tag-err.txt"
	# コマンド行の日本語は化けずに届く（cmd.exe → npm の起動口 → node で確かめた。p260930-02）。化けるのは出力を CP932 として読んだとき
	$p = $prompt.Replace('"', "'")
	# -Trace: 道具の呼び出しを残す。Pi はセッションのファイル、OpenCode は JSON の出来事で受ける
	$piSession = Join-Path $logDir "$tag-pi-session"
	$cmdLine = switch ($Agent) {
		'pi' { if ($Trace) { "pi -p --session-dir `"$piSession`" --provider llamacpp --model `"$name`" `"$p`"" } else { "pi -p --no-session --provider llamacpp --model `"$name`" `"$p`"" } }
		'opencode' { if ($Trace) { "opencode run --format json -m `"llamacpp/$name`" `"$p`"" } else { "opencode run -m `"llamacpp/$name`" `"$p`"" } }
		# Windows では -s workspace-write だと Codex のシェル実行（ファイルの読み書きに使う）が policy で止まるため、安全装置を外す。
		# 作業フォルダは W:/temp の下のコピーなので、外に出なければ本物には届かない（出ない保証はない）
		'codex' { "codex exec --skip-git-repo-check --ephemeral --dangerously-bypass-approvals-and-sandbox -m `"$name`" `"$p`"" }
		'aider' { "`"$aider`" --model `"openai/$name`" --openai-api-base http://127.0.0.1:$Port/v1 --openai-api-key llamacpp --no-git --yes-always --no-show-model-warnings --no-check-update --no-pretty --message `"$p`"" }
	}
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$cc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/d /s /c `"$cmdLine < nul > `"$out`" 2> `"$err`"`"" -WorkingDirectory $work -PassThru -WindowStyle Hidden
	$done = $cc.WaitForExit($TimeoutSec * 1000)
	$sw.Stop()
	if (-not $done) { taskkill /PID $cc.Id /T /F | Out-Null }
	$text = if (Test-Path $out) { [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8) } else { '' }
	$toolLog = $text
	if ($Trace -and $Agent -eq 'pi' -and (Test-Path $piSession)) {
		$toolLog = (Get-ChildItem $piSession -Recurse -Filter *.jsonl | ForEach-Object { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8) }) -join "`n"
	}
	if ($Trace -and $Agent -eq 'opencode') {
		# JSON の出来事から、答えの文だけを拾う
		$parts = foreach ($line in ($text -split "`n")) {
			if (-not $line.TrimStart().StartsWith('{')) { continue }
			try { $j = $line | ConvertFrom-Json } catch { continue }
			if ($j.type -eq 'text' -and $j.part.text) { $j.part.text }
		}
		if ($parts) { $text = $parts -join "`n" }
	}
	return [ordered]@{ status = $(if ($done) { 'ok' } else { 'timeout' }); sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1); result = $text.Trim(); toolLog = $toolLog }
}

# いつ・どの版で試したかを結果に残す（版が上がると結果が変わりうる）
# Windows PowerShell 5.1 は 2>&1 で受けた標準エラーの行をエラーとして扱い、Stop のままだと止まる
$ErrorActionPreference = 'Continue'
$agentVersion = switch ($Agent) {
	'pi' { (pi --version 2>&1 | Select-Object -First 1) }
	'opencode' { (opencode --version 2>&1 | Select-Object -First 1) }
	'codex' { (codex --version 2>&1 | Select-Object -First 1) }
	'aider' { (& $aider --version 2>&1 | Select-Object -Last 1) }
}
$llamaVersion = (& $exe --version 2>&1 | Select-String 'version' | Select-Object -First 1).Line
$versions = [ordered]@{ agent = "$agentVersion".Trim(); llama = "$llamaVersion".Trim(); node = (node --version) }
$ErrorActionPreference = 'Stop'
Write-Host "版: $Agent $($versions.agent) / llama.cpp $($versions.llama) / node $($versions.node)"

$readExpect = 'ローカルLLM 実行環境'
foreach ($m in $models) {
	$name = $m.BaseName
	$tag = "$runStamp-$Agent-$name"
	$ngl = if ($m.Length -le 3.2GB) { '-ngl 99' } else { '' }
	$tpl = Join-Path $PSScriptRoot "templates/$name.jinja"
	$tplArg = if ($UseTemplates -and (Test-Path $tpl)) { "--chat-template-file `"$tpl`"" } else { '' }
	$argList = "-m `"$($m.FullName)`" -c $Ctx -np 1 $ngl -nkvo -ctk q8_0 -ctv q8_0 -fa on $tplArg $ExtraArgs --alias $name --host 127.0.0.1 --port $Port"
	Write-Host "=== $Agent / $name"
	$rec = [ordered]@{ agent = $Agent; model = $name; versions = $versions; server = $argList; load = ''; read = $null; write = $null; echo = $null; sum = $null }

	# エージェントごとの接続設定を空のホームに書く
	switch ($Agent) {
		'pi' {
			$cfg = @{ providers = @{ llamacpp = @{ baseUrl = "http://127.0.0.1:$Port/v1"; api = 'openai-completions'; apiKey = 'llamacpp'; models = @(@{ id = $name }) } } }
			[IO.File]::WriteAllText((Join-Path $agentHome 'models.json'), ($cfg | ConvertTo-Json -Depth 6), $utf8)
			$env:PI_CODING_AGENT_DIR = $agentHome
		}
		'opencode' {
			$cfg = @{ '$schema' = 'https://opencode.ai/config.json'; provider = @{ llamacpp = @{ npm = '@ai-sdk/openai-compatible'; name = 'llama.cpp'; options = @{ baseURL = "http://127.0.0.1:$Port/v1"; apiKey = 'llamacpp' }; models = @{ $name = @{ name = $name; tool_call = $true; limit = @{ context = $Ctx; output = 4096 } } } } }; model = "llamacpp/$name" }
			$cfgPath = Join-Path $agentHome 'opencode.json'
			[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 8), $utf8)
			$env:OPENCODE_CONFIG = $cfgPath
		}
		'codex' {
			# CODEX_HOME を空のホームに向ける。利用者のいつもの ~/.codex（設定・AGENTS.md）は読ませない
			$toml = @(
				"model = `"$name`""
				"model_provider = `"llamacpp`""
				''
				'[model_providers.llamacpp]'
				'name = "llama.cpp"'
				"base_url = `"http://127.0.0.1:$Port/v1`""
				"wire_api = `"$CodexWireApi`""
				'env_key = "LLAMACPP_API_KEY"'
			) -join "`n"
			[IO.File]::WriteAllText((Join-Path $agentHome 'config.toml'), $toml + "`n", $utf8)
			$env:CODEX_HOME = $agentHome
			$env:LLAMACPP_API_KEY = 'llamacpp'
		}
	}

	$srvLog = Join-Path $logDir "$tag-server.log"
	$srv = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardError $srvLog -RedirectStandardOutput "$srvLog.out"
	try {
		$ready = $false
		for ($i = 0; $i -lt 150; $i++) {
			Start-Sleep -Seconds 2
			if ($srv.HasExited) { break }
			try { $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2; if ($h.status -eq 'ok') { $ready = $true; break } } catch {}
		}
		if (-not $ready) { $rec.load = 'サーバが起動しない'; continue }
		$rec.load = 'ok'

		if ($Tests -match 'read') {
			Reset-Sandbox
			$r = Invoke-Agent 'Read the file README.html and answer with only the text of its first h1 element.' $name "$tag-read"
			$r.Remove('toolLog')
			$r.pass = ($r.status -eq 'ok' -and $r.result -like "*$readExpect*")
			$rec.read = $r
			Write-Host "  読み: $($r.status) $($r.sec) 秒 合格 $($r.pass)"
		}

		if ($Tests -match 'write') {
			Reset-Sandbox
			$wf = Join-Path $work "tmp/cc-write-$Agent-$name.txt"
			if (Test-Path $wf) { Remove-Item -LiteralPath $wf }
			$token = "written-by-$Agent-$name-$runStamp"
			$r = Invoke-Agent "Create the file tmp/cc-write-$Agent-$name.txt whose content is exactly this single line: $token" $name "$tag-write"
			$r.Remove('toolLog')
			$got = if (Test-Path $wf) { ([IO.File]::ReadAllText($wf, [Text.Encoding]::UTF8)).Trim() } else { '' }
			$r.pass = ($got -eq $token)
			$r.file = $(if (Test-Path $wf) { 'あり' } else { 'なし' })
			$rec.write = $r
			Write-Host "  書き: $($r.status) $($r.sec) 秒 合格 $($r.pass)"
			if (Test-Path $wf) { Remove-Item -LiteralPath $wf }
		}

		# 日本語が化けずに届き、化けずに返るか
		if ($Tests -match 'echo') {
			Reset-Sandbox
			$r = Invoke-Agent $EchoPrompt $name "$tag-echo" -Trace
			$r.Remove('toolLog')
			$r.pass = ($r.status -eq 'ok' -and $r.result.Contains($EchoText))
			$rec.echo = $r
			Write-Host "  日本語: $($r.status) $($r.sec) 秒 合格 $($r.pass)  答え: $($r.result.Substring(0, [Math]::Min(60, $r.result.Length)))"
		}

		# 初期プログラミング（p260930-02）
		if ($Tests -match 'sum') {
			Reset-Sandbox
			$r = Invoke-Agent $SumPrompt $name "$tag-sum" -Trace
			$j = Test-SumResult $work $r.result $r.toolLog (Join-Path $logDir "$tag-sum")
			$r.Remove('toolLog')
			foreach ($k in $j.Keys) { $r[$k] = $j[$k] }
			$rec.sum = $r
			Write-Host "  sum: $($r.status) $($r.sec) 秒 合格 $($r.pass)（作成 $($r.file)・実行 $($r.run_pass)・報告 $($r.report_pass)・ログ $($r.log_ran)）"
		}
	} finally {
		if (-not $srv.HasExited) { taskkill /PID $srv.Id /T /F | Out-Null }
		Start-Sleep -Seconds 3
		[IO.File]::AppendAllText($resultFile, (($rec | ConvertTo-Json -Compress -Depth 4) + "`n"), $utf8)
	}
}
Write-Host "結果: logs/test-agents/$runStamp-$Agent-results.jsonl"
