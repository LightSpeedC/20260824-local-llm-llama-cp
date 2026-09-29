param(
	[int]$IntervalSec = 30,
	[int]$Hours = 24
)
# GPU の温度・クロック・電力・使用率・制限理由と、CPU のクロック・使用率を一定間隔で CSV に追記する
# CPU の温度は管理者権限がないと読めないため取らない
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$logDir = Join-Path $root 'logs/thermal'
New-Item -ItemType Directory -Force $logDir | Out-Null
$file = Join-Path $logDir ((Get-Date -Format 'yyyyMM') + '-thermal.csv')
$utf8 = New-Object Text.UTF8Encoding($false)
if (-not (Test-Path $file)) {
	[IO.File]::AppendAllText($file, "time,gpu_temp_c,gpu_clock_mhz,gpu_power_w,gpu_util_pct,gpu_mem_mib,gpu_throttle,cpu_freq_mhz,cpu_perf_pct,cpu_util_pct,llama_server`n", $utf8)
}
$counters = '\Processor Information(_Total)\Processor Frequency', '\Processor Information(_Total)\% Processor Performance', '\Processor(_Total)\% Processor Time'
$end = (Get-Date).AddHours($Hours)
Write-Host "記録先: logs/thermal/$(Split-Path $file -Leaf)（$IntervalSec 秒ごと）"
while ((Get-Date) -lt $end) {
	$g = (& nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw,utilization.gpu,memory.used,clocks_throttle_reasons.active --format=csv,noheader,nounits) -split ',\s*'
	$c = (Get-Counter $counters).CounterSamples | ForEach-Object { [Math]::Round($_.CookedValue) }
	$srv = if (Get-Process llama-server -ErrorAction SilentlyContinue) { 1 } else { 0 }
	$line = @((Get-Date -Format 'yyyy/MM/dd HH:mm:ss'), $g[0], $g[1], $g[2], $g[3], $g[4], $g[5], $c[0], $c[1], $c[2], $srv) -join ','
	[IO.File]::AppendAllText($file, "$line`n", $utf8)
	Start-Sleep -Seconds $IntervalSec
}
