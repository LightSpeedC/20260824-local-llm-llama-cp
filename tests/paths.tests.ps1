# 試験スクリプトの既定値（tools/50_run/paths.ps1）のテスト（r260929-01「これからの時間切れの決め方」）
# 単独でも動くが、ふだんは tools/40_test/run-tests.ps1 から呼ぶ
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
. (Join-Path $root 'tools/50_run/paths.ps1')

$script:failed = 0
$script:passed = 0
function Assert-Equal($name, $expected, $actual) {
	if ($expected -eq $actual) { $script:passed++; Write-Host "  ✅ $name" }
	else { $script:failed++; Write-Host "  ❌ $name（期待: $expected / 実際: $actual）" }
}

Write-Host '■ Get-LlmTimeout：時間切れの既定（秒）'
# NVIDIA GPU（CUDA 版）は 10 分。合格はすべて 10 分以内だった
Assert-Equal 'NVIDIA GPU（llama.cpp）は 600 秒' 600 (Get-LlmTimeout 'llama.cpp' 'gemma-4-E4B-it-Q4_K_M')
Assert-Equal '配布物の CUDA 版も 600 秒' 600 (Get-LlmTimeout 'llama.cpp-b11320-cuda' 'gemma-4-E4B-it-Q4_K_M')
# Intel GPU（Vulkan 版）は 15 分。Claude Code の合格は最長 643 秒だった
Assert-Equal 'Intel GPU（Vulkan 版）は 900 秒' 900 (Get-LlmTimeout 'llama.cpp-b11320-vulkan' 'gemma-4-E4B-it-Q4_K_M')
# CPU 版は測っていないので、遅い側の Intel GPU に揃える
Assert-Equal 'CPU 版は Intel GPU と同じ 900 秒' 900 (Get-LlmTimeout 'llama.cpp-b11320-cpu' 'gemma-4-E4B-it-Q4_K_M')
# 名前に Thinking・Reasoning が入るモデルは、--reasoning off でも長く考えるので倍
Assert-Equal 'Thinking は NVIDIA GPU で倍の 1200 秒' 1200 (Get-LlmTimeout 'llama.cpp' 'Qwen3-4B-Thinking-2507-Q4_K_M')
Assert-Equal 'Reasoning は Intel GPU で倍の 1800 秒' 1800 (Get-LlmTimeout 'llama.cpp-b11320-vulkan' 'Ministral-3-14B-Reasoning-2512-Q4_K_M')
Assert-Equal '-Only の略した名前（Qwen3-4B-Thinking）でも倍' 1200 (Get-LlmTimeout 'llama.cpp' 'Qwen3-4B-Thinking')

Write-Host '■ Read-LlmText：エージェントの出力ファイルを読む'
# 時間切れで止めた後も、子プロセスが出力ファイルを開いたままのことがある（ReadAllText は失敗して試験全体が止まった）
$p = Join-Path $root 'tmp/tests-read-llm-text.txt'
[IO.File]::WriteAllText($p, '{"result":"55"}', (New-Object Text.UTF8Encoding($false)))
$fs = [IO.File]::Open($p, 'Open', 'ReadWrite', 'ReadWrite')
try { Assert-Equal 'ほかのプロセスが書き込み用に開いていても読める' '{"result":"55"}' (Read-LlmText $p) } finally { $fs.Dispose() }
Remove-Item $p
Assert-Equal '無いファイルは空' '' (Read-LlmText (Join-Path $root 'tmp/tests-no-such-file.txt'))

Write-Host '■ Test-LlmPortFree：llama-server を立てる前にポートの空きを見る'
# 別のプログラムが同じポートで待っていると、/health の確認がそちらに届いて通ってしまう（i261003-01）
$l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$l.Start()
$busy = $l.LocalEndpoint.Port
try { Assert-Equal 'ほかのプログラムが待っているポートは空いていない' $false (Test-LlmPortFree $busy) } finally { $l.Stop() }
Assert-Equal '閉じたあとのポートは空いている' $true (Test-LlmPortFree $busy)

Write-Host '■ LlmPort：llama-server のポート'
# 現地で変えるのは config.cmd だけ、を保つため、ポートも LLM_PORT で変えられるようにする（i261003-01）
# 読み込みは 1 回きりなので、別の PowerShell で読み直して確かめる
$pathsPs1 = Join-Path $root 'tools/50_run/paths.ps1'
$env:LLM_PORT = $null
Assert-Equal 'LLM_PORT が無ければ 8080' '8080' (powershell -NoProfile -Command ". '$pathsPs1'; `$LlmPort")
$env:LLM_PORT = '18081'
try { Assert-Equal 'LLM_PORT があればその値' '18081' (powershell -NoProfile -Command ". '$pathsPs1'; `$LlmPort") } finally { $env:LLM_PORT = $null }

Write-Host ''
Write-Host "合格 $script:passed 件 / 不合格 $script:failed 件"
if ($script:failed) { exit 1 }
