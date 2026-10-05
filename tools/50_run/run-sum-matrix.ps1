param(
	# 流す組み合わせ。「モデル:エージェント,エージェント」をセミコロンで区切る（例: gemma-4-E4B:cc,pi;Qwen3.5-9B:opencode）。エージェントは cc・pi・opencode・aider
	[Parameter(Mandatory)][string]$Combos,
	# 使う llama.cpp の bin 下のフォルダ名
	[string]$LlamaDir = 'llama.cpp',
	# 0 ならモデルと llama.cpp から決める（paths.ps1 の Get-LlmTimeout）
	[int]$TimeoutSec = 0,
	# ログの名前に付ける目印
	[string]$Label = 'matrix'
)
# sum（初期プログラミング）を、決めたモデルとエージェントの組み合わせだけ 1 回ずつ流す（i261001-01）
# 書いた順に流すので、小さいモデルから並べると早く結果が出る
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$logDir = Join-Path $root 'logs/sum-sets'
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $logDir "$stamp-$Label-driver.log"
$out = Join-Path $logDir "$stamp-$Label-out.txt"
# 運転記録を見張る側がファイルを開いていると書けないことがある。何回かやり直し、駄目なら書くのを諦めて試験は続ける
function Write-Log([string]$s) {
	$line = "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') $s"
	Write-Host $line
	for ($i = 0; $i -lt 10; $i++) {
		try { [IO.File]::AppendAllText($log, "$line`r`n", (New-Object Text.UTF8Encoding($false))); return } catch { Start-Sleep -Milliseconds 500 }
	}
	Write-Host "（運転記録に書けなかった: $line）"
}

$list = foreach ($c in $Combos.Split(';')) {
	$m, $as = $c.Trim().Split(':')
	foreach ($a in $as.Split(',')) { [pscustomobject]@{ model = $m.Trim(); agent = $a.Trim() } }
}
$timeoutText = if ($TimeoutSec) { "$TimeoutSec 秒" } else { 'モデルと llama.cpp から決める' }
Write-Log "開始 $(@($list).Count) 組・llama.cpp: $LlamaDir・時間切れ: $timeoutText"
$t = $PSScriptRoot
$n = 0
foreach ($x in $list) {
	$n++
	Write-Log "=== $n/$(@($list).Count) $($x.model) / $($x.agent)"
	$common = @{ Only = $x.model; UseTemplates = $true; Tests = 'sum'; ExtraArgs = '--reasoning off'; TimeoutSec = $TimeoutSec; LlamaDir = $LlamaDir }
	# 1 組でエラーが起きても全体は止めない。エラーを運転記録に書いて次の組へ進む
	try {
		if ($x.agent -eq 'cc') {
			& "$t/test-cc-tools.ps1" @common -MaxSizeGB 20 -NoRules *>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $out -Append | Where-Object { $_ -match 'sum:' } | ForEach-Object { Write-Log "  $_" }
		} else {
			& "$t/test-agents.ps1" @common -Agent $x.agent *>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $out -Append | Where-Object { $_ -match 'sum:' } | ForEach-Object { Write-Log "  $_" }
		}
	} catch {
		Write-Log "  エラー: $($_.Exception.Message)"
	}
}
Write-Log '終了'
