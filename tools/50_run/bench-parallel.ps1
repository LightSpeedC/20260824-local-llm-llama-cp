# 並列スロットのスループットを測る（p260825-01 の Phase 1）
# --parallel N で llama-server を立て、N 本のリクエストを同時に投げて合計 tok/s と VRAM を記録する
param(
	[string]$Model = "C:/AI-models/qwen/Qwen3-4B-Instruct-2507-GGUF/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
	# -File 経由では配列を渡せないため、カンマ区切りの文字列で受ける（"1,2,4"）
	[string]$Parallel = "1,2,4",
	[int]$Context = 8192,
	[int]$MaxTokens = 256,
	[int]$Port = 8080,
	# 長いプロンプトで測るときの文の数。1 文が約 13 トークン（0 なら短い 1 行だけ）
	[int]$PromptSentences = 0,
	[string]$ExtraArgs = ""
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$root = Resolve-Path "$PSScriptRoot/../.."
$server = Join-Path $root "bin/llama.cpp/llama-server.exe"
$logDir = Join-Path $root "logs/bench-parallel"
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = Join-Path $logDir "$stamp-results.jsonl"
$base = "http://127.0.0.1:$Port"

function Get-VramUsed {
	[int](nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
}

$longText = ""
if ($PromptSentences -gt 0) {
	$longText = (1..$PromptSentences | ForEach-Object { "Log entry ${_}: the lighthouse keeper recorded wind, tide and ship traffic at dawn." }) -join "`n"
	$longText = "`n$longText`n"
}

function Send-Requests([int]$n, [string]$tag) {
	$client = New-Object System.Net.Http.HttpClient
	$client.Timeout = [TimeSpan]::FromMinutes(10)
	$tasks = @()
	$sw = [Diagnostics.Stopwatch]::StartNew()
	for ($i = 0; $i -lt $n; $i++) {
		# 同じ文をキャッシュで使い回さないよう、先頭の印をリクエストごと・温めと本番で変える
		$body = @{
			messages = @(@{ role = "user"; content = "($tag-$i)$longText Write a long story about a lighthouse keeper." })
			max_tokens = $MaxTokens
			temperature = 0.7
			ignore_eos = $true
		} | ConvertTo-Json -Depth 5
		$content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, "application/json")
		$tasks += $client.PostAsync("$base/v1/chat/completions", $content)
	}
	[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks)
	$wall = $sw.Elapsed.TotalSeconds
	$per = @()
	foreach ($t in $tasks) {
		$json = $t.Result.Content.ReadAsStringAsync().Result | ConvertFrom-Json
		$per += [pscustomobject]@{
			prompt = [int]$json.usage.prompt_tokens
			tokens = [int]$json.usage.completion_tokens
			tps = [math]::Round([double]$json.timings.predicted_per_second, 2)
		}
	}
	$client.Dispose()
	$total = ($per | Measure-Object tokens -Sum).Sum
	$prompt = ($per | Measure-Object prompt -Maximum).Maximum
	return [pscustomobject]@{ wall = [math]::Round($wall, 2); tokens = $total; prompt = $prompt; total_tps = [math]::Round($total / $wall, 2); per = $per }
}

$counts = @($Parallel -split ',' | ForEach-Object { [int]$_.Trim() })
if ($counts.Count -eq 0 -or ($counts | Where-Object { $_ -lt 1 -or $_ -gt 16 })) { throw "並列数は 1〜16 をカンマ区切りで渡す: $Parallel" }
$baseline = $null
foreach ($n in $counts) {
	Write-Host "=== --parallel $n"
	$serverArgs = "-m `"$Model`" -c $Context -np $n -ngl 99 $ExtraArgs --host 127.0.0.1 --port $Port"
	$log = Join-Path $logDir "$stamp-np$n-server.log"
	$proc = Start-Process -FilePath $server -ArgumentList $serverArgs -PassThru -WindowStyle Hidden -RedirectStandardError $log -RedirectStandardOutput "$log.out"
	try {
		$ready = $false
		for ($i = 0; $i -lt 180; $i++) {
			Start-Sleep -Seconds 1
			try { if ((Invoke-WebRequest "$base/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $ready = $true; break } } catch {}
		}
		if (-not $ready) { throw "llama-server が起動しない（np=$n）" }
		# 1 本流して温める
		Send-Requests 1 "warm" | Out-Null
		$r = Send-Requests $n "run"
		$vram = Get-VramUsed
		if ($n -eq $counts[0]) { $baseline = $r.total_tps }
		$ratio = if ($baseline) { [math]::Round($r.total_tps / $baseline, 2) } else { $null }
		$perText = ($r.per | ForEach-Object { $_.tps }) -join " / "
		Write-Host ("  合計 {0} tok/s（{1} トークン / {2} 秒）  1 本ごと {3} tok/s  倍率 {4}  VRAM {5} MiB  プロンプト {6} トークン/本" -f $r.total_tps, $r.tokens, $r.wall, $perText, $ratio, $vram, $r.prompt)
		[pscustomobject]@{ parallel = $n; context = $Context; max_tokens = $MaxTokens; prompt_tokens = $r.prompt; total_tps = $r.total_tps; tokens = $r.tokens; wall = $r.wall; per_tps = @($r.per | ForEach-Object { $_.tps }); ratio = $ratio; vram_mib = $vram; extra = $ExtraArgs } |
			ConvertTo-Json -Compress | Add-Content -Path $resultFile -Encoding UTF8
	}
	finally {
		Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
		Start-Sleep -Seconds 3
	}
}
Write-Host ("結果: " + $resultFile.Replace($root.Path + [IO.Path]::DirectorySeparatorChar, "").Replace("\", "/"))
