param(
	# 出力先。空なら _releases/offline/llm-bundle-yyyyMMdd
	[string]$OutDir = '',
	# 入れるモデル（ファイル名の拡張子を除いた部分）
	[string[]]$Models = @('gemma-4-E4B-it-Q4_K_M', 'gemma-4-E4B-it-qat-UD-Q4_K_XL', 'gemma-4-12B-it-Q4_K_M', 'gemma-4-12B-it-QAT-Q4_0', 'Qwen3.5-9B-Q4_K_M', 'gemma-4-E2B-it-Q4_K_M', 'Ornith-1.0-9B-Q4_K_M'),
	# モデルの出力先。モデルは大きいので配布物とは別に置く。空なら _releases/models
	[string]$ModelsDir = '',
	# モデルを写さない（現地にモデルがあるとき）
	[switch]$NoModels,
	# 入れる版
	[string]$NodeVersion = '26.11.1',
	[string[]]$Packages = @('@anthropic-ai/claude-code@2.1.299', '@earendil-works/pi-coding-agent@1.2.0', 'opencode-ai@1.19.0'),
	# llama.cpp の版（bin の下のフォルダ名と、配布物の中のフォルダ名に使う。実際の版と合うかを組み立てる前に確かめる）
	[string]$LlamaVersion = 'b11609',
	# 作り置きの node（エージェント入り）を作り直す
	[switch]$RebuildNode,
	# 7z を作らず、フォルダだけにする
	[switch]$NoArchive
)
# 閉域網へ持っていく配布物を組み立てる（p261002-01）
# 持ち込むものは 3 つに分ける。offline（llama.cpp・Node.js とエージェント・bun・単体の claude.exe・試験スクリプト・起動用の cmd・資料。1 つの 7z）、
# models（モデル。1 本ずつ別の 7z。現地で offline の配布物の下の models に展開する）、drivers（Intel GPU のドライバ。_releases/drivers をそのまま持っていく）
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
. (Join-Path $root 'tools/50_run/paths.ps1')
$show = { param($s) $s.Replace($root, '<proj>').Replace($env:USERPROFILE, '~') }
if (-not $OutDir) { $OutDir = Join-Path $root "_releases/offline/llm-bundle-$(Get-Date -Format 'yyyyMMdd')" }
if (-not $ModelsDir) { $ModelsDir = Join-Path $root '_releases/models' }
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
	# -f を付けないと、404 などでもエラーの HTML を保存して終了コード 0 で終わる
	curl.exe -fsSL -o (Join-Path $inst 'SHASUMS256.txt') "$base/SHASUMS256.txt"
	if ($LASTEXITCODE) { throw "取得に失敗: $base/SHASUMS256.txt（版 $NodeVersion が無いか、ネットに繋がらない）" }
	foreach ($f in "node-v$NodeVersion-win-x64.zip", "node-v$NodeVersion-x64.msi") {
		$p = Join-Path $inst $f
		if (-not (Test-Path $p)) { curl.exe -fsSL -o $p "$base/$f"; if ($LASTEXITCODE) { if (Test-Path $p) { Remove-Item $p }; throw "取得に失敗: $f" } }
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
# 開発用の PC の置き場: Vulkan 版・CPU 版は版の付いたフォルダ、CUDA 版は版の付かない bin/llama.cpp
# 配布物の中では 3 つとも版を付ける。コピーの前に、実際の版が $LlamaVersion と合っているかを確かめる（古い版を入れないため）
$llamaSrc = [ordered]@{ "llama.cpp-$LlamaVersion-vulkan" = "bin/llama.cpp-$LlamaVersion-vulkan"; "llama.cpp-$LlamaVersion-cpu" = "bin/llama.cpp-$LlamaVersion-cpu"; "llama.cpp-$LlamaVersion-cuda" = 'bin/llama.cpp' }
foreach ($d in $llamaSrc.Keys) {
	$exe = Join-Path $root "$($llamaSrc[$d])/llama-server.exe"
	if (-not (Test-Path $exe)) { throw "llama-server がありません: $(& $show $exe)" }
	$saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
	$ver = (& $exe --version 2>&1 | Select-String 'version' | Select-Object -First 1).Line
	$ErrorActionPreference = $saved
	if ($ver -notmatch "build $($LlamaVersion.TrimStart('b'))\b") { throw "llama.cpp の版が違います（期待: $LlamaVersion / 実際: $ver）: $(& $show $exe)" }
	Copy-Dir (Join-Path $root $llamaSrc[$d]) (Join-Path $OutDir "bin/$d")
}
Write-Host "  llama.cpp $LlamaVersion（Vulkan・CPU・CUDA）"
# bun（開発用の PC に入っている 1 本の exe）
$bunExe = (Get-Command bun.exe -ErrorAction Stop).Source
New-Item -ItemType Directory -Force (Join-Path $OutDir 'bin/bun') | Out-Null
Copy-Item $bunExe (Join-Path $OutDir 'bin/bun')
Write-Host "  bun $((& $bunExe --version).Trim())"
Copy-Dir $node (Join-Path $OutDir 'bin/node')
New-Item -ItemType Directory -Force (Join-Path $OutDir 'bin/claude') | Out-Null
$claudeExe = Join-Path $node 'node_modules/@anthropic-ai/claude-code/bin/claude.exe'
if (-not (Test-Path $claudeExe)) { throw "npm の Claude Code の中に claude.exe がありません。置き場が変わった可能性があります: $(& $show $claudeExe)" }
Copy-Item $claudeExe (Join-Path $OutDir 'bin/claude')
Write-Host '  Node.js（エージェント入り）・単体の claude.exe'
New-Item -ItemType Directory -Force (Join-Path $OutDir 'installers') | Out-Null
Copy-Item (Join-Path $inst "node-v$NodeVersion-x64.msi") (Join-Path $OutDir 'installers')
Write-Host '  インストーラ（Node.js の msi）'
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
Copy-Item (Join-Path $PSScriptRoot 'bundle/使い方.html') $OutDir
# 資料は README と notes を元の階層のまま写す。相対リンクがそのまま合い、どこから読んでも切れない（Markdown は写さない）
robocopy (Join-Path $root 'notes') (Join-Path $OutDir 'notes') /E /XF *.md /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'notes のコピーに失敗' }
Write-Host '  試験スクリプト・設定・使い方・資料（README と notes）'

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
	"`"%~dp0..\bin\llama.cpp-$LlamaVersion-vulkan\llama-server.exe`" --list-devices"
	'pause'
) -join "`n"
[IO.File]::WriteAllText($cmd, $body + "`n")
convert-encoding $cmd --to cmd | Out-Null
$count++
Write-Host "  起動用の cmd $count 本"

# 4. 7z を作る。モデル以外（ツール類）は 1 つ、モデルは大きいので 1 本ずつ別の 7z にする
# モデルに mmproj（画像を読むためのファイル）があれば、同じ 7z に入れる。圧縮はほとんど効かないので、モデルは速さを優先する
$sevenZip = 'C:/Program Files/7-Zip/7z.exe'
function New-Archive([string]$archive, [string[]]$items, [int]$level) {
	if (Test-Path $archive) { Remove-Item $archive }
	& $sevenZip a "-mx=$level" -mmt=on $archive @items | Out-Null
	if ($LASTEXITCODE) { throw "7z の作成に失敗: $(& $show $archive)" }
}
if (-not $NoArchive) {
	if (-not (Test-Path $sevenZip)) { throw "7z が見つかりません: $sevenZip" }
	# フォルダごと入れる。展開すると llm-bundle-yyyyMMdd のフォルダができる
	New-Archive "$OutDir.7z" @($OutDir) 5
	Write-Host ("  ツール類の 7z: {0}（{1:N2} GB）" -f (& $show "$OutDir.7z"), ((Get-Item "$OutDir.7z").Length / 1GB))
	if (-not $NoModels) {
		New-Item -ItemType Directory -Force $ModelsDir | Out-Null
		$all = Get-ChildItem $LlmModelDir -Recurse -Filter *.gguf
		foreach ($name in $Models) {
			$m = $all | Where-Object { $_.BaseName -eq $name } | Select-Object -First 1
			if (-not $m) { throw "モデルが見つかりません: $name" }
			$items = @($m.FullName)
			$mm = @(Get-ChildItem $m.DirectoryName -Filter 'mmproj*.gguf')
			if ($mm.Count -gt 1) { throw "mmproj が複数あります: $name" }
			if ($mm.Count -eq 1) { $items += $mm[0].FullName }
			$arc = Join-Path $ModelsDir "$name.7z"
			New-Archive $arc $items 1
			Write-Host ("  モデル {0}{1}（{2:N1} GB）" -f $name, $(if ($mm.Count) { ' ＋ mmproj' } else { '' }), ((Get-Item $arc).Length / 1GB))
		}
	}
}

$size = (Get-ChildItem $OutDir -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("完成: {0}（フォルダ {1:N1} GB）" -f (& $show $OutDir), ($size / 1GB))
if (-not $NoModels -and (Test-Path $ModelsDir)) {
	Write-Host ("モデル: {0}（モデルごとの 7z。現地では配布物の下の models に展開する）" -f (& $show $ModelsDir))
}
Write-Host 'ドライバ: <proj>\_releases\drivers をそのまま持っていく'
