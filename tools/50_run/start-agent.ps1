param(
	# pi・opencode・claude（npm 版）・claude-exe（単体の claude.exe）・server（llama-server だけ）・bench（Vulkan 版と CPU 版で速さを測る）
	[Parameter(Mandatory)][ValidateSet('pi', 'opencode', 'claude', 'claude-exe', 'server', 'bench')][string]$Agent,
	# モデルのファイル名に含まれる語（例: gemma-4-E4B-it-Q4_K_M）
	[Parameter(Mandatory)][string]$Model,
	[int]$Ctx = 65536,
	[int]$Port = 8080,
	# エージェントが作業するフォルダ。空なら work の下の project
	[string]$WorkDir = ''
)
# llama-server を立て、エージェントをそれに繋いで開く。エージェントを閉じたらサーバも止める（p261002-01）
# サーバの設定は試験と同じ（思考なし・差し替えたテンプレートがあれば使う）
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'paths.ps1')
$utf8 = New-Object Text.UTF8Encoding($false)

$m = Get-ChildItem $LlmModelDir -Recurse -Filter *.gguf | Where-Object { $_.BaseName -like "*$Model*" -and $_.Name -notmatch 'mmproj' } | Select-Object -First 1
if (-not $m) { throw "モデルが見つかりません: $Model（場所: $LlmModelDir）" }
$name = $m.BaseName
if ($Agent -eq 'bench') {
	foreach ($b in 'llama.cpp-b11320-vulkan', 'llama.cpp-b11320-cpu') {
		$bench = Join-Path $LlmRoot "bin/$b/llama-bench.exe"
		if (-not (Test-Path $bench)) { continue }
		Write-Host "=== $b / $name"
		& $bench -m $m.FullName -p 512 -n 64 -r 2
	}
	return
}
$backend = Resolve-LlmBackend $LlmBackend
$exe = Join-Path $LlmRoot "bin/$backend/llama-server.exe"
if (-not (Test-Path $exe)) { throw "llama-server が見つかりません: bin/$backend" }
$ngl = if ($m.Length -le 3.2GB) { '-ngl 99' } else { '' }
$tpl = Join-Path $PSScriptRoot "templates/$name.jinja"
$tplArg = if (Test-Path $tpl) { "--chat-template-file `"$tpl`"" } else { '' }
$argList = "-m `"$($m.FullName)`" -c $Ctx -np 1 $ngl -nkvo -ctk q8_0 -ctv q8_0 -fa on $tplArg --reasoning off --alias $name --host 127.0.0.1 --port $Port"
$show = { param($s) $s.Replace($LlmRoot.TrimEnd('\'), '<配布先>').Replace($env:USERPROFILE, '~') }
Write-Host "モデル: $name"
Write-Host "llama.cpp: $backend"

if ($Agent -eq 'server') {
	Write-Host 'llama-server を開きます。止めるときは Ctrl+C'
	Write-Host "接続先: http://127.0.0.1:$Port/v1"
	Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -Wait
	return
}

$logDir = Join-Path $LlmRoot 'logs/start-agent'
New-Item -ItemType Directory -Force $logDir | Out-Null
$srvLog = Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$name-server.log"
$srv = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardError $srvLog -RedirectStandardOutput "$srvLog.out"
try {
	Write-Host 'llama-server を起動しています…'
	$ready = $false
	for ($i = 0; $i -lt 300; $i++) {
		Start-Sleep -Seconds 2
		if ($srv.HasExited) { break }
		try { $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2; if ($h.status -eq 'ok') { $ready = $true; break } } catch {}
	}
	if (-not $ready) { throw "llama-server が起動しません。ログ: $(& $show $srvLog)" }

	# エージェントは配布物の node を使う。設定は work の下の空のホームに置き、利用者のいつもの設定には触れない
	$env:PATH = (Join-Path $LlmRoot 'bin/node') + ';' + $env:PATH
	$home2 = Join-Path $LlmAgentHome $Agent
	New-Item -ItemType Directory -Force $home2 | Out-Null
	if (-not $WorkDir) { $WorkDir = Join-Path (Split-Path $LlmSandbox) 'project' }
	New-Item -ItemType Directory -Force $WorkDir | Out-Null
	Set-Location $WorkDir
	Write-Host "作業フォルダ: $(& $show $WorkDir)"
	switch ($Agent) {
		'pi' {
			$cfg = @{ providers = @{ llamacpp = @{ baseUrl = "http://127.0.0.1:$Port/v1"; api = 'openai-completions'; apiKey = 'llamacpp'; models = @(@{ id = $name }) } } }
			[IO.File]::WriteAllText((Join-Path $home2 'models.json'), ($cfg | ConvertTo-Json -Depth 6), $utf8)
			$env:PI_CODING_AGENT_DIR = $home2
			& pi.cmd --provider llamacpp --model $name
		}
		'opencode' {
			$cfg = @{ '$schema' = 'https://opencode.ai/config.json'; provider = @{ llamacpp = @{ npm = '@ai-sdk/openai-compatible'; name = 'llama.cpp'; options = @{ baseURL = "http://127.0.0.1:$Port/v1"; apiKey = 'llamacpp' }; models = @{ $name = @{ name = $name; tool_call = $true; limit = @{ context = $Ctx; output = 4096 } } } } }; model = "llamacpp/$name" }
			$cfgPath = Join-Path $home2 'opencode.json'
			[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 8), $utf8)
			$env:OPENCODE_CONFIG = $cfgPath
			& opencode.cmd -m "llamacpp/$name"
		}
		{ $_ -in 'claude', 'claude-exe' } {
			# Claude Code は llama-server の Anthropic 形式の口へ直接繋ぐ。ホームを空にして、いつもの設定・メモリを読ませない
			$env:USERPROFILE = $home2; $env:HOME = $home2
			$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$Port"
			$env:ANTHROPIC_AUTH_TOKEN = 'llamacpp'
			$env:ANTHROPIC_MODEL = $name
			$env:ANTHROPIC_SMALL_FAST_MODEL = $name
			$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$Ctx"
			$env:API_TIMEOUT_MS = '600000'
			$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
			$env:CLAUDE_CODE_USE_POWERSHELL_TOOL = $null
			if ($Agent -eq 'claude') { & claude.cmd } else { & (Join-Path $LlmRoot 'bin/claude/claude.exe') }
		}
	}
} finally {
	if (-not $srv.HasExited) { taskkill /PID $srv.Id /T /F | Out-Null }
	Write-Host 'llama-server を止めました'
}
