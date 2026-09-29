param(
	[Parameter(Mandatory)][ValidateSet('pi', 'opencode', 'aider')][string]$Agent,
	[Parameter(Mandatory)][string]$Only,
	[string]$ModelDir = 'C:\AI_Models',
	[int]$Ctx = 65536,
	[int]$TimeoutSec = 600,
	[int]$Port = 8080,
	[switch]$UseTemplates,
	[string]$ExtraArgs = ''
)
# Claude Code 以外のエージェント（Pi・OpenCode・Aider）を llama-server に繋ぎ、読み・書きができるかを試す
# 試験の中身は test-cc-tools.ps1 と同じ。結果は logs/test-agents/ に 1 モデル 1 行の JSON Lines で追記する
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$exe = Join-Path $root 'bin/llama.cpp/llama-server.exe'
$logDir = Join-Path $root 'logs/test-agents'
New-Item -ItemType Directory -Force $logDir | Out-Null
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultFile = Join-Path $logDir "$runStamp-$Agent-results.jsonl"
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
$agentHome = Join-Path $root "tmp/agent-home/$Agent"
New-Item -ItemType Directory -Force $agentHome | Out-Null
$aider = Join-Path $env:USERPROFILE '.local/bin/aider.exe'

$keys = $Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$all = Get-ChildItem $ModelDir -Recurse -Filter *.gguf | Where-Object { $_.Name -notmatch 'mmproj' }
$models = foreach ($k in $keys) { $all | Where-Object { $_.BaseName -like "*$k*" } }
$models = $models | Select-Object -Unique
if (-not $models) { throw 'モデルが見つかりません' }

function Invoke-Agent([string]$prompt, [string]$name, [string]$tag) {
	$out = Join-Path $logDir "$tag-out.txt"
	$err = Join-Path $logDir "$tag-err.txt"
	# 質問は ASCII に限る。コマンド行に日本語を載せると CP932 に化けるため
	$p = $prompt.Replace('"', "'")
	$cmdLine = switch ($Agent) {
		'pi' { "pi -p --no-session --provider llamacpp --model `"$name`" `"$p`"" }
		'opencode' { "opencode run -m `"llamacpp/$name`" `"$p`"" }
		'aider' { "`"$aider`" --model `"openai/$name`" --openai-api-base http://127.0.0.1:$Port/v1 --openai-api-key llamacpp --no-git --yes-always --no-show-model-warnings --no-check-update --no-pretty --message `"$p`"" }
	}
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$cc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/d /s /c `"$cmdLine < nul > `"$out`" 2> `"$err`"`"" -WorkingDirectory $work -PassThru -WindowStyle Hidden
	$done = $cc.WaitForExit($TimeoutSec * 1000)
	$sw.Stop()
	if (-not $done) { taskkill /PID $cc.Id /T /F | Out-Null }
	$text = if (Test-Path $out) { [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8) } else { '' }
	return [ordered]@{ status = $(if ($done) { 'ok' } else { 'timeout' }); sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1); result = $text.Trim() }
}

$readExpect = 'ローカルLLM 実行環境'
foreach ($m in $models) {
	$name = $m.BaseName
	$tag = "$runStamp-$Agent-$name"
	$ngl = if ($m.Length -le 3.2GB) { '-ngl 99' } else { '' }
	$tpl = Join-Path $PSScriptRoot "templates/$name.jinja"
	$tplArg = if ($UseTemplates -and (Test-Path $tpl)) { "--chat-template-file `"$tpl`"" } else { '' }
	$argList = "-m `"$($m.FullName)`" -c $Ctx -np 1 $ngl -nkvo -ctk q8_0 -ctv q8_0 -fa on $tplArg $ExtraArgs --alias $name --host 127.0.0.1 --port $Port"
	Write-Host "=== $Agent / $name"
	$rec = [ordered]@{ agent = $Agent; model = $name; server = $argList; load = ''; read = $null; write = $null }

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

		Reset-Sandbox
		$r = Invoke-Agent 'Read the file README.html and answer with only the text of its first h1 element.' $name "$tag-read"
		$r.pass = ($r.status -eq 'ok' -and $r.result -like "*$readExpect*")
		$rec.read = $r
		Write-Host "  読み: $($r.status) $($r.sec) 秒 合格 $($r.pass)"

		Reset-Sandbox
		$wf = Join-Path $work "tmp/cc-write-$Agent-$name.txt"
		if (Test-Path $wf) { Remove-Item -LiteralPath $wf }
		$token = "written-by-$Agent-$name-$runStamp"
		$r = Invoke-Agent "Create the file tmp/cc-write-$Agent-$name.txt whose content is exactly this single line: $token" $name "$tag-write"
		$got = if (Test-Path $wf) { ([IO.File]::ReadAllText($wf, [Text.Encoding]::UTF8)).Trim() } else { '' }
		$r.pass = ($got -eq $token)
		$r.file = $(if (Test-Path $wf) { 'あり' } else { 'なし' })
		$rec.write = $r
		Write-Host "  書き: $($r.status) $($r.sec) 秒 合格 $($r.pass)"
		if (Test-Path $wf) { Remove-Item -LiteralPath $wf }
	} finally {
		if (-not $srv.HasExited) { taskkill /PID $srv.Id /T /F | Out-Null }
		Start-Sleep -Seconds 3
		[IO.File]::AppendAllText($resultFile, (($rec | ConvertTo-Json -Compress -Depth 4) + "`n"), $utf8)
	}
}
Write-Host "結果: logs/test-agents/$runStamp-$Agent-results.jsonl"
