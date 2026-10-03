# 初期プログラミングの試験結果（sum）から、試験結果の第 4 章の表の行を作る（p260930-02）
# エージェント × モデルごとに、いちばん新しい結果を使う。判定は sum-judge.ps1 と同じ基準で出し直す
# -All: 最新だけでなく、流したすべての回を 1 行ずつ出す（全実行の記録用）
# -Sets: 同じ組を何回も流したとき、1 マスに回の順で ✅☑️❌⏱️ を並べる（版を上げて 3 回ずつ流した表用）
# -Until: この時刻より前の結果だけを使う（例: 版を上げた 3 セットは -Since 20261001-2300 -Until 20261002-0700）
param([string]$Since = '20260930-2254', [string]$Until = '99999999', [switch]$All, [switch]$Sets)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sum-judge.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')
$root = (Resolve-Path "$PSScriptRoot/../..").Path

# ⑤ は保存してある作業ログから判定し直す（判定を直したとき、流し直さずに済むように）
function Get-ToolLog([string]$agent, [string]$stamp, [string]$model) {
	$p = switch ($agent) {
		'claude' { Join-Path $root "logs/test-cc-tools/$stamp-$model-sum-norules-raw.json" }
		'pi' { Join-Path $root "logs/test-agents/$stamp-pi-$model-sum-pi-session" }
		default { Join-Path $root "logs/test-agents/$stamp-$agent-$model-sum-out.txt" }
	}
	if (-not (Test-Path $p)) { return $null }
	if ((Get-Item $p).PSIsContainer) {
		return (Get-ChildItem $p -Recurse -Filter *.jsonl | ForEach-Object { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8) }) -join "`n"
	}
	return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
}
$order = @(
	'gemma-4-E2B-it-Q4_K_M', 'gemma-4-E4B-it-Q4_K_M', 'Ministral-3-3B-Instruct-2512-Q4_K_M', 'Qwen3-4B-Instruct-2507-Q4_K_M',
	'Qwen3.5-9B-Q4_K_M', 'gpt-oss-20b-MXFP4', 'gemma-4-12B-it-QAT-Q4_0', 'gemma-4-12B-it-Q4_K_M', 'gemma-4-26B-A4B-it-UD-Q4_K_XL',
	'Qwen3-30B-A3B-Instruct-2507-UD-Q4_K_XL', 'Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL', 'GLM-4.7-Flash-UD-Q4_K_XL', 'Bonsai-27B-Q1_0',
	'Qwen3.6-35B-A3B-UD-Q3_K_XL', 'Ministral-3-14B-Reasoning-2512-Q4_K_M', 'Devstral-Small-2507-UD-Q4_K_XL',
	'NVIDIA-Nemotron-3-Nano-4B-Q4_K_M', 'Qwen3-4B-Thinking-2507-Q4_K_M', 'GLM-4.6V-Flash-Q4_K_M'
)
$agents = @('claude', 'pi', 'opencode', 'aider')
$agentNames = @{ claude = 'Claude Code'; pi = 'Pi'; opencode = 'OpenCode'; aider = 'Aider' }
$cells = @{}
$runs = @()
$sources = @(
	Get-ChildItem (Join-Path $root 'logs/test-cc-tools') -Filter '*-norules-results.jsonl' | ForEach-Object { @{ file = $_; agent = 'claude' } }
	Get-ChildItem (Join-Path $root 'logs/test-agents') -Filter '*-results.jsonl' | ForEach-Object { @{ file = $_; agent = $null } }
) | Where-Object { $_.file.Name -ge $Since -and $_.file.Name -lt $Until -and $_.file.Name -notmatch '-llama\.cpp-' } | Sort-Object { $_.file.Name }
# 名前に -llama.cpp-… が付くのは、Vulkan 版・CPU 版など別の llama.cpp で流した結果なので混ぜない
foreach ($s in $sources) {
	foreach ($line in [IO.File]::ReadAllLines($s.file.FullName, [Text.Encoding]::UTF8)) {
		if (-not $line.Trim()) { continue }
		$o = $line | ConvertFrom-Json
		if (-not $o.sum) { continue }
		$agent = if ($s.agent) { $s.agent } else { $o.agent }
		$log = Get-ToolLog $agent $s.file.Name.Substring(0, 15) $o.model
		if ($null -ne $log) { $o.sum.log_ran = Test-SumTrace $log }
		$cells["$agent|$($o.model)"] = $o.sum
		$runs += [pscustomobject]@{ stamp = $s.file.Name.Substring(0, 15); agent = $agent; model = $o.model; sum = $o.sum }
	}
}
if ($Sets) {
	# 1 マスに回の順で記号を並べる。行はモデルの大きさ順にし、名前の横に GB を書く
	$size = @{}
	Get-ChildItem $LlmModelDir -Recurse -Filter *.gguf | ForEach-Object { $size[$_.BaseName] = $_.Length }
	$marks = @{}
	foreach ($r in $runs) { $marks["$($r.agent)|$($r.model)"] += (Get-SumMark $r.sum) }
	foreach ($m in ($order | Sort-Object { $size[$_] })) {
		$gb = if ($size[$m]) { '{0:N1} GB' -f ($size[$m] / 1GB) } else { '?' }
		$tds = foreach ($a in $agents) { $v = $marks["$a|$m"]; if (-not $v) { $v = '—' }; "<td class=`"nowrap`">$v</td>" }
		"<tr><td class=`"nowrap`">$m</td><td class=`"num nowrap`">$gb</td>$($tds -join '')</tr>"
	}
	return
}
if ($All) {
	foreach ($r in $runs) {
		$t = [datetime]::ParseExact($r.stamp, 'yyyyMMdd-HHmmss', $null).ToString('MM/dd HH:mm')
		# 表に載っているのと同じ組の、より新しい回があれば、この回は流し直しで置き換えられた
		$latest = ($cells["$($r.agent)|$($r.model)"] -eq $r.sum)
		$valid = if ($latest) { '有効' } else { '無効：流し直した' }
		"<tr><td class=`"nowrap`">$t</td><td class=`"nowrap`">$($agentNames[$r.agent])</td><td class=`"nowrap`">$($r.model)</td><td>$(Format-SumCell $r.sum)</td><td class=`"num`">$([Math]::Round([double]$r.sum.sec)) 秒</td><td>$valid</td></tr>"
	}
	return
}
foreach ($m in $order) {
	$tds = foreach ($a in $agents) { "<td>$(Format-SumCell $cells["$a|$m"])</td>" }
	"<tr><td class=`"nowrap`">$m</td>$($tds -join '')</tr>"
}
