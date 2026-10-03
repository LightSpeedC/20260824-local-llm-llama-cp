param([string]$ModelDir = 'C:\AI-models')
# Hugging Face から Claude Code 試験用のモデルを取得する。取得済みで大きさが一致するものは飛ばす
$ErrorActionPreference = 'Stop'
$list = @(
	@{ repo = 'unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF'; file = 'Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf'; dir = 'Qwen' }
	@{ repo = 'unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF'; file = 'Qwen3-30B-A3B-Instruct-2507-UD-Q4_K_XL.gguf'; dir = 'Qwen' }
	@{ repo = 'unsloth/GLM-4.7-Flash-GGUF'; file = 'GLM-4.7-Flash-UD-Q4_K_XL.gguf'; dir = 'GLM' }
	@{ repo = 'unsloth/Gemma-4-26B-A4B-it-GGUF'; file = 'gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf'; dir = 'Gemma' }
	@{ repo = 'unsloth/Qwen3.6-35B-A3B-GGUF'; file = 'Qwen3.6-35B-A3B-UD-Q3_K_XL.gguf'; dir = 'Qwen' }
	@{ repo = 'unsloth/Devstral-Small-2507-GGUF'; file = 'Devstral-Small-2507-UD-Q4_K_XL.gguf'; dir = 'Mistral' }
)
foreach ($m in $list) {
	$name = $m.repo.Split('/')[1]
	$dest = Join-Path $ModelDir "$($m.dir)\$name"
	New-Item -ItemType Directory -Force $dest | Out-Null
	$path = Join-Path $dest $m.file
	$url = "https://huggingface.co/$($m.repo)/resolve/main/$($m.file)"
	$tree = Invoke-RestMethod "https://huggingface.co/api/models/$($m.repo)/tree/main" -TimeoutSec 60
	$size = ($tree | Where-Object { $_.path -eq $m.file }).size
	if ((Test-Path $path) -and (Get-Item $path).Length -eq $size) { Write-Host "取得済み: $($m.file)"; continue }
	Write-Host ("取得開始: {0}（{1:N2} GB）" -f $m.file, ($size / 1GB))
	# -C - で途中からの再開ができる
	& curl.exe -L --fail --retry 5 -C - -o $path $url --silent --show-error
	if ($LASTEXITCODE -ne 0) { Write-Host "失敗: $($m.file)（curl $LASTEXITCODE）"; continue }
	$got = (Get-Item $path).Length
	if ($got -ne $size) { Write-Host "大きさが違う: $($m.file) $got / $size" } else { Write-Host "取得完了: $($m.file)" }
}
Write-Host '全件終了'
