param(
	# 出力先。空なら _releases/offline/llm-bundle-yyyyMMdd
	[string]$OutDir = '',
	# 入れるモデル（ファイル名の拡張子を除いた部分）
	[string[]]$Models = @('gemma-4-E4B-it-Q4_K_M', 'gemma-4-E2B-it-Q4_K_M', 'Ministral-3-3B-Instruct-2512-Q4_K_M', 'gemma-4-12B-it-QAT-Q4_0'),
	# モデルを入れない（現地にモデルがあるとき）
	[switch]$NoModels,
	# 入れる版
	[string]$NodeVersion = '26.10.0',
	[string[]]$Packages = @('@anthropic-ai/claude-code@2.1.287', '@earendil-works/pi-coding-agent@0.99.2', 'opencode-ai@1.18.34'),
	# 作り置きの node（エージェント入り）を作り直す
	[switch]$RebuildNode
)
# 閉域網へ持っていく配布物を組み立てる（p261002-01）
# llama.cpp・Node.js（エージェント入り）・単体の claude.exe・モデル・試験スクリプト・起動用の cmd を 1 つのフォルダにまとめる
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
. (Join-Path $root 'tools/50_run/paths.ps1')
$show = { param($s) $s.Replace($root, '<proj>').Replace($env:USERPROFILE, '~') }
if (-not $OutDir) { $OutDir = Join-Path $root "_releases/offline/llm-bundle-$(Get-Date -Format 'yyyyMMdd')" }
if (Test-Path $OutDir) { throw "出力先がすでにあります: $(& $show $OutDir)" }
function Copy-Dir([string]$from, [string]$to) {
	# robocopy は 8 未満が成功
	robocopy $from $to /E /NFL /NDL /NJH /NJS /NP | Out-Null
	if ($LASTEXITCODE -ge 8) { throw "コピーに失敗: $(& $show $from)" }
}

# 1. エージェント入りの node を作り置きする（_releases/staging/node）
$staging = Join-Path $root '_releases/staging'
$inst = Join-Path $staging 'installers'
$node = Join-Path $staging 'node'
if ($RebuildNode -and (Test-Path $node)) { Remove-Item $node -Recurse -Force }
if (-not (Test-Path $node)) {
	Write-Host "Node.js v$NodeVersion を取得して、エージェントを入れます"
	New-Item -ItemType Directory -Force $inst | Out-Null
	$base = "https://nodejs.org/dist/v$NodeVersion"
	curl.exe -sSL -o (Join-Path $inst 'SHASUMS256.txt') "$base/SHASUMS256.txt"
	foreach ($f in "node-v$NodeVersion-win-x64.zip", "node-v$NodeVersion-x64.msi") {
		$p = Join-Path $inst $f
		if (-not (Test-Path $p)) { curl.exe -sSL -o $p "$base/$f"; if ($LASTEXITCODE) { throw "取得に失敗: $f" } }
		$h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
		if (-not (Select-String -Path (Join-Path $inst 'SHASUMS256.txt') -Pattern "$h  $f" -SimpleMatch -Quiet)) { throw "SHA256 が合いません: $f" }
	}
	Expand-Archive (Join-Path $inst "node-v$NodeVersion-win-x64.zip") $staging -Force
	Rename-Item (Join-Path $staging "node-v$NodeVersion-win-x64") 'node'
	$savedPath = $env:PATH
	$env:PATH = "$node;$env:PATH"
	& (Join-Path $node 'npm.cmd') install -g --prefix $node @Packages
	$env:PATH = $savedPath
	if ($LASTEXITCODE) { throw 'npm install に失敗' }
}

# 2. フォルダを作って、中身をコピーする
Write-Host "組み立て先: $(& $show $OutDir)"
New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($d in 'llama.cpp-b11320-vulkan', 'llama.cpp-b11320-cpu') { Copy-Dir (Join-Path $root "bin/$d") (Join-Path $OutDir "bin/$d") }
Copy-Dir (Join-Path $root 'bin/llama.cpp') (Join-Path $OutDir 'bin/llama.cpp-b11320-cuda')
Write-Host '  llama.cpp（Vulkan・CPU・CUDA）'
Copy-Dir $node (Join-Path $OutDir 'bin/node')
New-Item -ItemType Directory -Force (Join-Path $OutDir 'bin/claude') | Out-Null
Copy-Item (Join-Path $node 'node_modules/@anthropic-ai/claude-code/bin/claude.exe') (Join-Path $OutDir 'bin/claude')
Write-Host '  Node.js（エージェント入り）・単体の claude.exe'
New-Item -ItemType Directory -Force (Join-Path $OutDir 'installers') | Out-Null
Copy-Item (Join-Path $inst "node-v$NodeVersion-x64.msi") (Join-Path $OutDir 'installers')
$drv = Join-Path $root '_releases/drivers'
if (Test-Path $drv) { Copy-Dir $drv (Join-Path $OutDir 'installers/drivers') }
Write-Host '  インストーラ（Node.js の msi・Intel GPU ドライバ）'
if (-not $NoModels) {
	New-Item -ItemType Directory -Force (Join-Path $OutDir 'models') | Out-Null
	$all = Get-ChildItem $LlmModelDir -Recurse -Filter *.gguf
	foreach ($name in $Models) {
		$m = $all | Where-Object { $_.BaseName -eq $name } | Select-Object -First 1
		if (-not $m) { throw "モデルが見つかりません: $name" }
		robocopy $m.DirectoryName (Join-Path $OutDir 'models') $m.Name /NFL /NDL /NJH /NJS /NP | Out-Null
		if ($LASTEXITCODE -ge 8) { throw "コピーに失敗: $name" }
		Write-Host ("  モデル {0}（{1:N1} GB）" -f $name, ($m.Length / 1GB))
	}
}
$t = Join-Path $OutDir 'tools/50_run'
New-Item -ItemType Directory -Force $t | Out-Null
foreach ($f in 'paths.ps1', 'sum-judge.ps1', 'start-agent.ps1', 'start-agent.cmd', 'test-agents.ps1', 'test-agents.cmd', 'test-cc-tools.ps1', 'test-cc-tools.cmd') {
	Copy-Item (Join-Path $root "tools/50_run/$f") $t
}
Copy-Dir (Join-Path $root 'tools/50_run/templates') (Join-Path $t 'templates')
# 試験は作業フォルダに README.html と .claude/settings.json を置いてから始める
Copy-Item (Join-Path $root 'README.html') $OutDir
New-Item -ItemType Directory -Force (Join-Path $OutDir '.claude') | Out-Null
Copy-Item (Join-Path $root '.claude/settings.json') (Join-Path $OutDir '.claude')
Copy-Item (Join-Path $PSScriptRoot 'bundle/config.cmd') $OutDir
Copy-Item (Join-Path $root 'notes/10_plan/p261002-01-閉域網へ持っていく配布物.html') (Join-Path $OutDir '配布物の説明.html')
Write-Host '  試験スクリプト・設定・説明'

# 3. 起動用の cmd を、エージェントとモデルの組み合わせごとに作る
$run = Join-Path $OutDir 'run'
New-Item -ItemType Directory -Force $run | Out-Null
$agents = [ordered]@{ pi = 'Pi を開く'; opencode = 'OpenCode を開く'; claude = 'Claude Code（npm 版）を開く'; 'claude-exe' = 'Claude Code（単体の claude.exe）を開く'; server = 'llama-server だけを開く'; bench = 'Vulkan 版（Intel GPU）と CPU 版で速さを測る' }
$count = 0
foreach ($name in $Models) {
	foreach ($a in $agents.Keys) {
		$cmd = Join-Path $run "$a-$name.cmd"
		$body = @(
			'@echo off'
			"rem $name で$($agents[$a])（p261002-01）"
			"powershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0..\tools\50_run\start-agent.ps1`" -Agent $a -Model $name"
			'pause'
		) -join "`n"
		[IO.File]::WriteAllText($cmd, $body + "`n")
		convert-encoding $cmd --to cmd | Out-Null
		$count++
	}
}
$cmd = Join-Path $run 'list-devices.cmd'
$body = @(
	'@echo off'
	'rem llama.cpp の Vulkan 版から見える GPU を表示する（p261002-01）'
	'"%~dp0..\bin\llama.cpp-b11320-vulkan\llama-server.exe" --list-devices'
	'pause'
) -join "`n"
[IO.File]::WriteAllText($cmd, $body + "`n")
convert-encoding $cmd --to cmd | Out-Null
$count++
Write-Host "  起動用の cmd $count 本"

$size = (Get-ChildItem $OutDir -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("完成: {0}（{1:N1} GB）" -f (& $show $OutDir), ($size / 1GB))
