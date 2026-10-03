# sum の判定（tools/50_run/sum-judge.ps1）のテスト（p260930-02）
# 判定を直したとき、これまで手で確かめた答えと同じになるかを見る。期待値は手で書いたもの
# 単独でも動くが、ふだんは tools/40_test/run-tests.ps1 から呼ぶ
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
. (Join-Path $root 'tools/50_run/sum-judge.ps1')

$script:failed = 0
$script:passed = 0
function Assert-Equal($name, $expected, $actual) {
	# 文字列は文字のコードで比べる。-eq はカルチャで比べ、⏱ と ⏱️（後ろに U+FE0F）を同じとみなす
	$same = if ($expected -is [string] -and $actual -is [string]) { [string]::Equals($expected, $actual, [StringComparison]::Ordinal) } else { $expected -eq $actual }
	if ($same) { $script:passed++; Write-Host "  ✅ $name" }
	else { $script:failed++; Write-Host "  ❌ $name（期待: $expected / 実際: $actual）" }
}

Write-Host '■ Test-SumTrace：作業ログに node sum を実行した跡があるか'
# 道具の呼び出しは JSON の "command" に入る。Claude Code・Pi・OpenCode とも同じ形
Assert-Equal 'command の node sum は跡あり' $true (Test-SumTrace '{"command": "node sum"}')
Assert-Equal 'command の node sum.js は跡あり' $true (Test-SumTrace '{"command":"node sum.js"}')
# モデルが作業フォルダの絶対パスで呼ぶことがある
Assert-Equal 'command の node /w/temp/…/sum.js は跡あり' $true (Test-SumTrace '{"command": "node /w/temp/llama-cp-sandbox/sum.js"}')
Assert-Equal 'command の node W:\\temp\\…\\sum.js（JSON のエスケープ）は跡あり' $true (Test-SumTrace '{"command": "node W:\\temp\\llama-cp-sandbox\\sum.js"}')
Assert-Equal 'cd してから node sum も跡あり' $true (Test-SumTrace '{"command": "cd /w/temp && node sum.js"}')
# Aider は道具を使わず、実行したコマンドを「Running」行で出す
Assert-Equal 'Aider の Running node sum.js は跡あり' $true (Test-SumTrace "Applied edit to sum.js`n  Running node sum.js`n55")
# ☑️補欠合格の元：書く道具だけを呼び、実行していない
Assert-Equal 'write の道具だけなら跡なし' $false (Test-SumTrace '{"name": "write", "input": {"path": "sum.js", "content": "console.log(55)"}}')
# 答えの文に「node sum で実行できます」と書いただけでは実行していない
Assert-Equal '答えの文の node sum は跡なし' $false (Test-SumTrace '"result": "node sum で実行できます"')
Assert-Equal 'node summary.js は別のファイルなので跡なし' $false (Test-SumTrace '{"command": "node summary.js"}')
Assert-Equal 'node sum.json は別のファイルなので跡なし' $false (Test-SumTrace '{"command": "node sum.json"}')
Assert-Equal '空のログは跡なし' $false (Test-SumTrace '')

Write-Host '■ Test-SumResult：sum.js・実行結果・答えから合否を出す'
$tmp = Join-Path $root 'tmp/tests-sum-judge'
function New-Work([string]$code) {
	if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
	New-Item -ItemType Directory -Force $tmp | Out-Null
	# [string] の引数は $null を '' にするため、空かどうかで見る
	if ($code) { [IO.File]::WriteAllText((Join-Path $tmp 'sum.js'), $code, (New-Object Text.UTF8Encoding($false))) }
	return $tmp
}
$save = Join-Path $root 'tmp/tests-sum-judge-save'

$w = New-Work 'console.log(55)'
$r = Test-SumResult $w '合計は 55 です' '{"command": "node sum.js"}' $save
Assert-Equal '書いて・実行して・55 と答えれば合格' $true $r.pass
Assert-Equal '　そのとき実行の跡あり（✅）' $true $r.log_ran

$r = Test-SumResult $w '合計は 55 です' '{"name": "write"}' $save
Assert-Equal '跡が無くても、55 が出て 55 と答えれば合格' $true $r.pass
Assert-Equal '　そのとき実行の跡なし（☑️補欠合格の元）' $false $r.log_ran

$w = New-Work 'console.log("1から10までの合計: " + 55)'
$r = Test-SumResult $w '55' '' $save
Assert-Equal '「1から10までの合計: 55」の表示も 55 が出たとみなす' $true $r.run_pass

$w = New-Work 'console.log(155)'
$r = Test-SumResult $w '55' '' $save
Assert-Equal '155 は 55 ではない' $false $r.run_pass
Assert-Equal '　出力が違えば不合格' $false $r.pass

$w = New-Work 'console.log(55)'
$r = Test-SumResult $w 'sum.js を作りました' '' $save
Assert-Equal '答えに 55 が無ければ答えは不合格' $false $r.report_pass
Assert-Equal '　答えが無ければ全体も不合格' $false $r.pass

$w = New-Work ''
$r = Test-SumResult $w '55' '' $save
Assert-Equal 'sum.js が無ければ file は なし' 'なし' $r.file
Assert-Equal '　sum.js が無ければ不合格' $false $r.pass

Write-Host '■ Get-SumMark：結果ファイルの 1 回分を ✅・☑️・❌・⏱️ にする'
# 結果ファイル（*-results.jsonl）の sum と同じ形。run_out は試験側で node sum を実行した出力
function New-Run($status, $file, $out, $report, $ran, $sec = 30) { [pscustomobject]@{ status = $status; file = $file; run_out = $out; report_pass = $report; log_ran = $ran; sec = $sec } }
Assert-Equal '書いて・実行して・55 と答えれば ✅' '✅' (Get-SumMark (New-Run 'ok' 'あり' '55' $true $true))
Assert-Equal '実行の跡が無ければ ☑️' '☑️' (Get-SumMark (New-Run 'ok' 'あり' '55' $true $false))
Assert-Equal 'sum.js が無ければ ❌' '❌' (Get-SumMark (New-Run 'ok' 'なし' '' $true $false))
Assert-Equal '55 が出なければ ❌' '❌' (Get-SumMark (New-Run 'ok' 'あり' '45' $true $true))
Assert-Equal '実行したが答えなければ ❌' '❌' (Get-SumMark (New-Run 'ok' 'あり' '55' $false $true))
Assert-Equal '時間切れは ⏱️' '⏱️' (Get-SumMark (New-Run 'timeout' 'あり' '55' $true $true))
Assert-Equal '結果が無ければ —' '—' (Get-SumMark $null)

Write-Host '■ Format-SumCell：1 回だけの表のマス'
Assert-Equal '✅ は秒数を添える' '✅ 合格 32 秒' (Format-SumCell (New-Run 'ok' 'あり' '55' $true $true 32.4))
Assert-Equal '☑️ は補欠合格と書く' '☑️ 補欠合格 80 秒' (Format-SumCell (New-Run 'ok' 'あり' '55' $true $false 80))
Assert-Equal '❌ は落ち方を添える（作らない）' '❌ 不合格 sum.js を作らない' (Format-SumCell (New-Run 'ok' 'なし' '' $false $false))
Assert-Equal '❌ は落ち方を添える（55 が出ない）' '❌ 不合格 書いたが 55 が出ない' (Format-SumCell (New-Run 'ok' 'あり' '45' $true $true))
Assert-Equal '❌ は落ち方を添える（答えない）' '❌ 不合格 実行したが結果を答えない' (Format-SumCell (New-Run 'ok' 'あり' '55' $false $true))
Assert-Equal '❌ は落ち方を添える（実行も報告もない）' '❌ 不合格 書いたが実行・報告なし' (Format-SumCell (New-Run 'ok' 'あり' '55' $false $false))
Assert-Equal '⏱️ は時間切れと書く' '⏱️ 時間切れ' (Format-SumCell (New-Run 'timeout' 'あり' '' $false $false))

Remove-Item $tmp -Recurse -Force
Get-ChildItem (Join-Path $root 'tmp') -Filter 'tests-sum-judge-save*' | Remove-Item -Force

Write-Host ''
Write-Host "合格 $script:passed 件 / 不合格 $script:failed 件"
if ($script:failed) { exit 1 }
