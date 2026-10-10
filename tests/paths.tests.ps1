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
# Ollama と同じ 11434 を既定にする（クライアントの既定の接続先と揃う）
Assert-Equal 'LLM_PORT が無ければ 11434' '11434' (powershell -NoProfile -Command ". '$pathsPs1'; `$LlmPort")
$env:LLM_PORT = '18081'
try { Assert-Equal 'LLM_PORT があればその値' '18081' (powershell -NoProfile -Command ". '$pathsPs1'; `$LlmPort") } finally { $env:LLM_PORT = $null }

Write-Host '■ Add-LlmKillOnClose：起動した PowerShell が終わったら llama-server も止める'
# 窓を × で閉じる・強制終了すると finally が走らず、llama-server が残っていた（i261003-01）
# 子の PowerShell に ping を起動させてジョブに入れ、子を強制終了したあとに ping が残っていないことを見る
$pidFile = Join-Path $root 'tmp/tests-kill-on-close.txt'
if (Test-Path $pidFile) { Remove-Item $pidFile }
$childCmd = ". '$pathsPs1'; `$p = Start-Process ping -ArgumentList '-n 120 127.0.0.1' -PassThru -WindowStyle Hidden; Add-LlmKillOnClose `$p; [IO.File]::WriteAllText('$pidFile', [string]`$p.Id); Start-Sleep 120"
$child = Start-Process powershell -ArgumentList '-NoProfile', '-Command', $childCmd -PassThru -WindowStyle Hidden
for ($i = 0; $i -lt 40 -and -not (Test-Path $pidFile); $i++) { Start-Sleep -Milliseconds 250 }
$pingId = if (Test-Path $pidFile) { [int][IO.File]::ReadAllText($pidFile) } else { 0 }
Assert-Equal '子が ping を起動した' $true ($pingId -gt 0 -and [bool](Get-Process -Id $pingId -ErrorAction SilentlyContinue))
Stop-Process -Id $child.Id -Force
Start-Sleep -Seconds 2
$left = [bool](Get-Process -Id $pingId -ErrorAction SilentlyContinue)
if ($left) { Stop-Process -Id $pingId -Force }
Assert-Equal '子を強制終了すると ping も止まる' $false $left
if (Test-Path $pidFile) { Remove-Item $pidFile }

Write-Host '■ Read-LlmConfig：config.cmd を読む'
# config.cmd は SJIS。Encoding.Default で読むと pwsh 7 では UTF-8 になり、日本語のパスが化けた（i261003-01）
# %変数% は cmd なら展開されるので、こちらでも環境変数で展開する
$cfg = Join-Path $root 'tmp/tests-config.cmd'
[IO.File]::WriteAllText($cfg, "@echo off`r`nrem 設定`r`nset `"LLM_MODEL_DIR=%LLM_TEST_BASE%\モデル置き場`"`r`nset `"LLM_WORK_DIR=%~dp0work`"`r`n", [Text.Encoding]::GetEncoding(932))
$env:LLM_TEST_BASE = 'D:\base'
foreach ($ps in 'powershell', 'pwsh') {
	if (-not (Get-Command $ps -ErrorAction SilentlyContinue)) { continue }
	$got = & $ps -NoProfile -Command ". '$pathsPs1'; `$c = Read-LlmConfig '$cfg' 'X:\dist'; `$c['LLM_MODEL_DIR'] + '|' + `$c['LLM_WORK_DIR']"
	Assert-Equal "$ps で日本語と %変数% と %~dp0 を読める" 'D:\base\モデル置き場|X:\dist\work' ([string]$got)
}
$env:LLM_TEST_BASE = $null
Remove-Item $cfg

Write-Host '■ Get-LlmGpuArgs：GPU に何層載せるか'
# Vulkan 版で -ngl を渡さないと、12B は Intel に載らず CPU で動いた。NVIDIA も見える PC では NVIDIA に一部が載った（i261003-01）
# Intel に全部載せると、プロンプトの処理が CPU の 4.6 倍（68.8 対 14.8 tok/s）。エージェントは毎回 1〜2 万トークン送るので効く
$both = "Available devices:`n  Vulkan0: Intel(R) Iris(R) Xe Graphics (16256 MiB, 15488 MiB free)`n  Vulkan1: NVIDIA GeForce RTX 3050 Ti Laptop GPU (3962 MiB, 3367 MiB free)"
$intel = "Available devices:`n  Vulkan0: Intel(R) Iris(R) Xe Graphics (16256 MiB, 15488 MiB free)"
$nvFirst = "Available devices:`n  Vulkan0: NVIDIA GeForce RTX 3050 Ti Laptop GPU (3962 MiB, 3367 MiB free)`n  Vulkan1: Intel(R) Iris(R) Xe Graphics (16256 MiB, 15488 MiB free)"
Assert-Equal 'Vulkan 版で Intel だけなら、大きさに関わらず -ngl 99' '-ngl 99' (Get-LlmGpuArgs 'llama.cpp-b11320-vulkan' 7GB $intel)
Assert-Equal 'Vulkan 版で NVIDIA も見えるなら、Intel だけを使う' '-ngl 99 --device Vulkan0' (Get-LlmGpuArgs 'llama.cpp-b11320-vulkan' 7GB $both)
Assert-Equal 'NVIDIA が先に並んでも Intel を選ぶ' '-ngl 99 --device Vulkan1' (Get-LlmGpuArgs 'llama.cpp-b11320-vulkan' 2GB $nvFirst)
# Intel の空き（15488 MiB）に全部は載らない 15.7GB の Qwen3.6-35B は、-ngl 99 だとサーバが起動しなかった
# 空きの 8 割を超えるものは -ngl を付けず、Intel に入る分だけを自動で載せる
Assert-Equal 'Vulkan 版で空きの 8 割を超えるモデルは自動配置（Intel だけ）' '--device Vulkan0' (Get-LlmGpuArgs 'llama.cpp-b11320-vulkan' 15.7GB $both)
Assert-Equal 'Vulkan 版で Intel だけ・空きの 8 割を超えるモデルは何も付けない' '' (Get-LlmGpuArgs 'llama.cpp-b11320-vulkan' 15.7GB $intel)
Assert-Equal 'gpt-oss-20b（11.3GB）は全部載せる' '-ngl 99' (Get-LlmGpuArgs 'llama.cpp-b11320-vulkan' 11.3GB $intel)
Assert-Equal 'CPU 版は何も付けない' '' (Get-LlmGpuArgs 'llama.cpp-b11320-cpu' 2GB '')
# CUDA 版（RTX 3050 Ti 4GB）は、3.2GB 以下だけ全部載せ、大きいものは llama-server の自動配置に任せる（r260929-01 の試験条件）
Assert-Equal 'CUDA 版の 3.2GB 以下は -ngl 99' '-ngl 99' (Get-LlmGpuArgs 'llama.cpp' 3GB '')
Assert-Equal 'CUDA 版の 3.2GB を超えるものは自動配置' '' (Get-LlmGpuArgs 'llama.cpp' 5GB '')

Write-Host ''
Write-Host "合格 $script:passed 件 / 不合格 $script:failed 件"
if ($script:failed) { exit 1 }
