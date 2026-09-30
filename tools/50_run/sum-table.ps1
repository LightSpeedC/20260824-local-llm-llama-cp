# 初期プログラミングの試験結果（sum）から、試験結果の第 4 章の表の行を作る（p260930-02）
# エージェント × モデルごとに、いちばん新しい結果を使う。判定は sum-judge.ps1 と同じ基準で出し直す
param([string]$Since = '20260930-2254')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$order = @(
	'gemma-4-E2B-it-Q4_K_M', 'gemma-4-E4B-it-Q4_K_M', 'Ministral-3-3B-Instruct-2512-Q4_K_M', 'Qwen3-4B-Instruct-2507-Q4_K_M',
	'Qwen3.5-9B-Q4_K_M', 'gpt-oss-20b-MXFP4', 'gemma-4-12B-it-QAT-Q4_0', 'gemma-4-12B-it-Q4_K_M', 'gemma-4-26B-A4B-it-UD-Q4_K_XL',
	'Qwen3-30B-A3B-Instruct-2507-UD-Q4_K_XL', 'Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL', 'GLM-4.7-Flash-UD-Q4_K_XL', 'Bonsai-27B-Q1_0',
	'Qwen3.6-35B-A3B-UD-Q3_K_XL', 'Ministral-3-14B-Reasoning-2512-Q4_K_M', 'Devstral-Small-2507-UD-Q4_K_XL',
	'NVIDIA-Nemotron-3-Nano-4B-Q4_K_M', 'Qwen3-4B-Thinking-2507-Q4_K_M', 'GLM-4.6V-Flash-Q4_K_M'
)
$agents = @('claude', 'pi', 'opencode', 'aider')
$cells = @{}
$sources = @(
	Get-ChildItem (Join-Path $root 'logs/test-cc-tools') -Filter '*-norules-results.jsonl' | ForEach-Object { @{ file = $_; agent = 'claude' } }
	Get-ChildItem (Join-Path $root 'logs/test-agents') -Filter '*-results.jsonl' | ForEach-Object { @{ file = $_; agent = $null } }
) | Where-Object { $_.file.Name -ge $Since } | Sort-Object { $_.file.Name }
foreach ($s in $sources) {
	foreach ($line in [IO.File]::ReadAllLines($s.file.FullName, [Text.Encoding]::UTF8)) {
		if (-not $line.Trim()) { continue }
		$o = $line | ConvertFrom-Json
		if (-not $o.sum) { continue }
		$agent = if ($s.agent) { $s.agent } else { $o.agent }
		$cells["$agent|$($o.model)"] = $o.sum
	}
}
function Format-Cell($r) {
	if (-not $r) { return '—' }
	$sec = [Math]::Round([double]$r.sec)
	if ($r.status -ne 'ok') { return "<span class=`"badge b-none`">時間切れ</span>" }
	$run = ($r.run_out -match '(?<!\d)55(?!\d)')
	if ($r.file -eq 'あり' -and $run -and $r.report_pass) {
		$trace = if ($r.log_ran) { '' } else { '（跡なし）' }
		return "<span class=`"badge b-ok`">合格</span>$sec 秒$trace"
	}
	$why = if ($r.file -ne 'あり') { 'sum.js を作らない' }
		elseif (-not $run) { '書いたが 55 が出ない' }
		else { '書いたが実行・報告なし' }
	return "<span class=`"badge b-ng`">不合格</span>$why"
}
foreach ($m in $order) {
	$tds = foreach ($a in $agents) { "<td>$(Format-Cell $cells["$a|$m"])</td>" }
	"<tr><td class=`"nowrap`">$m</td>$($tds -join '')</tr>"
}
