# Speculative Decoding の効果を測る（r260825-01 の検証計画）
# 構成ごとに llama-server を立て、同じ問を温度 0 で投げて、生成速度・受理率・VRAM・出力の同一性を記録する
param(
	[string]$Model = "C:/AI_Models/qwen/Qwen3-4B-Instruct-2507-GGUF/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
	[string]$Draft = "C:/AI_Models/qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf",
	[int]$Context = 4096,
	[int]$MaxTokens = 256,
	[int]$Port = 8080,
	# 測る構成の番号をカンマ区切りで（"2,6"）。空なら全部。対照の No1 は常に測る
	[string]$Only = ""
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$root = Resolve-Path "$PSScriptRoot/../.."
$server = Join-Path $root "bin/llama.cpp/llama-server.exe"
$logDir = Join-Path $root "logs/bench-spec"
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = Join-Path $logDir "$stamp-results.jsonl"
$base = "http://127.0.0.1:$Port"

# --spec-type の既定は none。-md だけではドラフトを読み込んでも使わない
$draftArgs = "-md `"$Draft`" -ngld 99 --spec-type draft-simple"
$configs = @(
	@{ no = 1; name = "単体（対照）"; args = "" }
	@{ no = 2; name = "ドラフト n-max 2"; args = "$draftArgs --spec-draft-n-max 2" }
	@{ no = 3; name = "ドラフト n-max 4"; args = "$draftArgs --spec-draft-n-max 4" }
	@{ no = 4; name = "ドラフト n-max 8"; args = "$draftArgs --spec-draft-n-max 8" }
	@{ no = 5; name = "ドラフト n-max 8 ＋KV q8_0"; args = "$draftArgs --spec-draft-n-max 8 -ctk q8_0 -ctv q8_0 -ctkd q8_0 -ctvd q8_0 -fa on" }
	# 以下は出力がずれる理由を調べるための構成（i260930-04）
	# 単体を立て直してもう一度。毎回同じ出力になるかを見る
	@{ no = 6; name = "単体（立て直して 2 回目）"; args = "" }
	# 同じ問を 2 本同時に処理させ、一度に計算するトークン数を 2 にする。ドラフトの検証も複数トークンをまとめて計算する
	@{ no = 7; name = "単体 2 本同時（np 2）"; args = ""; np = 2; concurrent = 2 }
	# n-max 2 と 4 の検証で一度に計算するトークン数（3・5）に合わせる
	@{ no = 8; name = "単体 3 本同時（np 3）"; args = ""; np = 3; concurrent = 3 }
	@{ no = 9; name = "単体 5 本同時（np 5）"; args = ""; np = 5; concurrent = 5 }
)
if ($Only) {
	$want = @(1) + @($Only -split ',' | ForEach-Object { [int]$_.Trim() })
	$configs = @($configs | Where-Object { $want -contains $_.no })
}

function Invoke-Chat([string]$body, [int]$count) {
	$client = New-Object System.Net.Http.HttpClient
	$client.Timeout = [TimeSpan]::FromMinutes(10)
	$tasks = @()
	for ($i = 0; $i -lt $count; $i++) {
		$content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, "application/json")
		$tasks += $client.PostAsync("$base/v1/chat/completions", $content)
	}
	[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks)
	$out = @()
	foreach ($t in $tasks) {
		$bytes = $t.Result.Content.ReadAsByteArrayAsync().Result
		$out += ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
	}
	$client.Dispose()
	return ,$out
}

# 先頭から何文字目まで同じか
function Get-CommonPrefix([string]$a, [string]$b) {
	$n = [math]::Min($a.Length, $b.Length)
	for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -cne $b[$i]) { return $i } }
	return $n
}
$prompts = @(
	@{ key = "text"; content = "Explain how a refrigerator works, step by step." }
	@{ key = "code"; content = "Write a PowerShell function that lists the 10 largest files under a folder, with sizes in MB." }
)

$reference = @{}
foreach ($c in $configs) {
	Write-Host "=== No$($c.no) $($c.name)"
	$np = if ($c.np) { $c.np } else { 1 }
	$concurrent = if ($c.concurrent) { $c.concurrent } else { 1 }
	$serverArgs = "-m `"$Model`" -c $($Context * $np) -np $np -ngl 99 $($c.args) --host 127.0.0.1 --port $Port"
	$log = Join-Path $logDir "$stamp-no$($c.no)-server.log"
	$proc = Start-Process -FilePath $server -ArgumentList $serverArgs -PassThru -WindowStyle Hidden -RedirectStandardError $log -RedirectStandardOutput "$log.out"
	try {
		$ready = $false
		for ($i = 0; $i -lt 180; $i++) {
			Start-Sleep -Seconds 1
			if ($proc.HasExited) { break }
			try { if ((Invoke-WebRequest "$base/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $ready = $true; break } } catch {}
		}
		if (-not $ready) { Write-Host "  llama-server が起動しない（ログ: $([IO.Path]::GetFileName($log))）"; continue }
		foreach ($p in $prompts) {
			$body = @{
				messages = @(@{ role = "user"; content = $p.content })
				max_tokens = $MaxTokens
				temperature = 0
				seed = 1
				ignore_eos = $true
			} | ConvertTo-Json -Depth 5
			# 1 回目で温め、2 回目を測る
			$null = Invoke-Chat $body $concurrent
			$rs = Invoke-Chat $body $concurrent
			$r = $rs[0]
			$vram = [int](nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
			$text = $r.choices[0].message.content
			[IO.File]::WriteAllText((Join-Path $logDir "$stamp-no$($c.no)-$($p.key).txt"), $text, (New-Object Text.UTF8Encoding($false)))
			if ($c.no -eq 1) { $reference[$p.key] = $text }
			$same = ($text -ceq $reference[$p.key])
			$prefix = Get-CommonPrefix $text $reference[$p.key]
			$t = $r.timings
			$accept = if ($t.draft_n -gt 0) { [math]::Round($t.draft_n_accepted / $t.draft_n, 3) } else { $null }
			Write-Host ("  {0}: {1:N2} tok/s  受理 {2}/{3}（{4}）  VRAM {5} MiB  対照と同じ出力 {6}（先頭 {7} / {8} 文字が一致）" -f $p.key, $t.predicted_per_second, $t.draft_n_accepted, $t.draft_n, $accept, $vram, $same, $prefix, $text.Length)
			[pscustomobject]@{ no = $c.no; name = $c.name; prompt = $p.key; tps = [math]::Round([double]$t.predicted_per_second, 2); tokens = $t.predicted_n; draft_n = $t.draft_n; draft_accepted = $t.draft_n_accepted; accept_rate = $accept; vram_mib = $vram; same_as_ref = $same; common_prefix = $prefix; length = $text.Length; args = $c.args } |
				ConvertTo-Json -Compress | Add-Content -Path $resultFile -Encoding UTF8
		}
	}
	finally {
		Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
		Start-Sleep -Seconds 3
	}
}
Write-Host ("結果: " + $resultFile.Replace($root.Path + [IO.Path]::DirectorySeparatorChar, "").Replace("\", "/"))
