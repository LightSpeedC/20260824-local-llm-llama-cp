param(
	# 何セット目まで流すか
	[int]$Sets = 3,
	# この時刻までに終わらない見込みのエージェントは始めない（HH:mm。過ぎていれば翌日の時刻）
	[string]$Until = '07:00',
	# 1 セット目で済んでいるエージェント（カンマ区切り。cc・pi・opencode・aider）
	[string]$DoneInFirst = '',
	# 1 セット目で済んでいるモデル（カンマ区切り。1 セット目だけ除く）
	[string]$SkipInFirst = 'gemma-4-E4B'
)
# sum（初期プログラミング）を 4 エージェント × 19 本で何セットも流し、揺れを見る（i261001-01）
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$logDir = Join-Path $root 'logs/sum-sets'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')-driver.log"
function Write-Log([string]$s) { $line = "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') $s"; Add-Content $log $line -Encoding UTF8; Write-Host $line }

$all = 'gemma-4-E2B,gemma-4-E4B,Ministral-3-3B,Qwen3-4B-Instruct,Qwen3.5-9B,gpt-oss-20b,gemma-4-12B-it-QAT,gemma-4-12B-it-Q4_K_M,gemma-4-26B-A4B,Qwen3-30B-A3B,Qwen3-Coder-30B,GLM-4.7-Flash,Bonsai-27B,Qwen3.6-35B,Ministral-3-14B,Devstral,NVIDIA-Nemotron,Qwen3-4B-Thinking,GLM-4.6V'.Split(',')
# 1 セットにかかる時間の見込み（分。2026-10-01 の実績から）
$minutes = @{ cc = 80; pi = 25; opencode = 45; aider = 25 }
$deadline = [datetime]::ParseExact($Until, 'HH:mm', $null)
if ($deadline -lt (Get-Date)) { $deadline = $deadline.AddDays(1) }
$done = $DoneInFirst.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$skip = $SkipInFirst.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$t = $PSScriptRoot
Write-Log "開始 $Sets セット・期限 $($deadline.ToString('MM/dd HH:mm'))"

:sets for ($s = 1; $s -le $Sets; $s++) {
	foreach ($a in 'cc', 'pi', 'opencode', 'aider') {
		if ($s -eq 1 -and $done -contains $a) { continue }
		if ((Get-Date).AddMinutes($minutes[$a]) -gt $deadline) { Write-Log "期限に間に合わないため止める（$s セット目 $a）"; break sets }
		$keys = if ($s -eq 1) { $all | Where-Object { $skip -notcontains $_ } } else { $all }
		$only = $keys -join ','
		Write-Log "=== $s セット目 $a 開始"
		$out = Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')-set$s-$a.txt"
		if ($a -eq 'cc') {
			& "$t/test-cc-tools.ps1" -Only $only -MaxSizeGB 20 -UseTemplates -NoRules -Tests 'sum' -ExtraArgs '--reasoning off' *>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $out | Where-Object { $_ -match '^===|sum:|結果:' } | ForEach-Object { Write-Log "  $_" }
		} else {
			& "$t/test-agents.ps1" -Agent $a -Only $only -UseTemplates -Tests 'sum' -ExtraArgs '--reasoning off' *>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $out | Where-Object { $_ -match '^===|sum:|結果:' } | ForEach-Object { Write-Log "  $_" }
		}
		Write-Log "=== $s セット目 $a 終了"
	}
}
Write-Log '完了'
