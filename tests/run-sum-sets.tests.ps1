# sum を何セットも流すスクリプト（tools/50_run/run-sum-sets.ps1）が、試験スクリプトへ -LlamaDir を名前付きで渡すことのテスト（i261014-01）
# 単独でも動くが、ふだんは tools/40_test/run-tests.ps1 から呼ぶ
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path

$script:failed = 0
$script:passed = 0
function Assert-Equal($name, $expected, $actual) {
	if ($expected -eq $actual) { $script:passed++; Write-Host "  ✅ $name" }
	else { $script:failed++; Write-Host "  ❌ $name（期待: $expected / 実際: $actual）" }
}

Write-Host '■ run-sum-sets：-LlamaDir を試験スクリプトへ名前付きで渡す'
# 配列で渡すと位置引数になり、-LlamaDir の名前が消えて、値が -Ctx に入った（試験が始まる前に止まった）
# 本物の試験スクリプトは llama-server を立てるので、受けた引数を書き出すだけの代役に差し替えて確かめる
$work = Join-Path $root 'tmp/tests-run-sum-sets'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$t = Join-Path $work 'tools/50_run'
New-Item -ItemType Directory -Force $t | Out-Null
Copy-Item (Join-Path $root 'tools/50_run/run-sum-sets.ps1') $t
$stub = @'
param([string]$Only = '', [double]$MaxSizeGB = 10, [int]$Ctx = 65536, [switch]$UseTemplates, [switch]$NoRules, [string]$Tests = '', [string]$ExtraArgs = '', [string]$LlamaDir = '', [string]$Agent = '')
[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'received.txt'), "LlamaDir=$LlamaDir;Ctx=$Ctx;Only=$Only`n")
'@
[IO.File]::WriteAllText((Join-Path $t 'test-cc-tools.ps1'), $stub)
[IO.File]::WriteAllText((Join-Path $t 'test-agents.ps1'), $stub)

function Invoke-Sets([string]$llamaDir) {
	$received = Join-Path $t 'received.txt'
	if (Test-Path $received) { Remove-Item $received }
	$a = @('-NoProfile', '-File', (Join-Path $t 'run-sum-sets.ps1'), '-Sets', '1', '-Until', '23:59', '-SkipInFirst', 'none', '-Agents', 'cc,pi', '-Models', 'model-a')
	if ($llamaDir) { $a += @('-LlamaDir', $llamaDir) }
	powershell @a | Out-Null
	if (Test-Path $received) { return @(Get-Content $received) } else { return @() }
}

$got = Invoke-Sets 'llama.cpp-b11609-vulkan'
Assert-Equal 'cc と pi の 2 回呼ばれる' 2 $got.Count
Assert-Equal 'cc には -LlamaDir が名前付きで届く' 'LlamaDir=llama.cpp-b11609-vulkan;Ctx=65536;Only=model-a' $got[0]
Assert-Equal 'pi にも -LlamaDir が名前付きで届く' 'LlamaDir=llama.cpp-b11609-vulkan;Ctx=65536;Only=model-a' $got[1]
$got = Invoke-Sets ''
Assert-Equal '-LlamaDir を渡さなければ、空のまま（各スクリプトが config.cmd から決める）' 'LlamaDir=;Ctx=65536;Only=model-a' $got[0]

Remove-Item $work -Recurse -Force

Write-Host ''
Write-Host "合格 $script:passed 件 / 不合格 $script:failed 件"
if ($script:failed) { exit 1 }
