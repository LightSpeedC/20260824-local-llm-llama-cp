param([string]$ModelDir = 'C:\AI-models')
# Hugging Face から試験用のモデルを取得する。取得済みで大きさが一致するものは飛ばす
# 書いた順に取る。小さいものから並べると、早く使い始められる
# mmproj（画像を読む部品）は、配布元の名前（mmproj-BF16.gguf 等）だと区別できないので、mmproj-<モデル名>-<型>.gguf の形で保存する
$ErrorActionPreference = 'Stop'
$list = @(
	@{ repo = 'unsloth/gemma-4-E4B-it-qat-GGUF'; file = 'gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf'; dir = 'Gemma'; mmproj = 'mmproj-BF16.gguf' }
	@{ repo = 'unsloth/LFM2.5-8B-A1B-GGUF'; file = 'LFM2.5-8B-A1B-UD-Q4_K_M.gguf'; dir = 'LFM' }
	@{ repo = 'unsloth/granite-4.1-8b-GGUF'; file = 'granite-4.1-8b-Q4_K_M.gguf'; dir = 'Granite' }
	@{ repo = 'unsloth/Ornith-1.0-9B-GGUF'; file = 'Ornith-1.0-9B-Q4_K_M.gguf'; dir = 'Ornith'; mmproj = 'mmproj-BF16.gguf' }
	@{ repo = 'unsloth/Muse-Glimmer-30B-GGUF'; file = 'Muse-Glimmer-30B-UD-Q4_K_XL.gguf'; dir = 'Meta'; mmproj = 'mmproj-Muse-Glimmer-30B-Q8_0.gguf' }
	@{ repo = 'unsloth/Qwen3.8-27B-GGUF'; file = 'Qwen3.8-27B-UD-Q4_K_M.gguf'; dir = 'Qwen'; mmproj = 'mmproj-BF16.gguf' }
	@{ repo = 'unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF'; file = 'Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf'; dir = 'Qwen' }
	@{ repo = 'unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF'; file = 'Qwen3-30B-A3B-Instruct-2507-UD-Q4_K_XL.gguf'; dir = 'Qwen' }
	@{ repo = 'unsloth/GLM-4.7-Flash-GGUF'; file = 'GLM-4.7-Flash-UD-Q4_K_XL.gguf'; dir = 'GLM' }
	@{ repo = 'unsloth/gemma-4-26B-A4B-it-GGUF'; file = 'gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf'; dir = 'Gemma' }
	@{ repo = 'unsloth/Qwen3.6-35B-A3B-GGUF'; file = 'Qwen3.6-35B-A3B-UD-Q3_K_XL.gguf'; dir = 'Qwen' }
	@{ repo = 'unsloth/Devstral-Small-2507-GGUF'; file = 'Devstral-Small-2507-UD-Q4_K_XL.gguf'; dir = 'Mistral' }
)
function Get-One([string]$repo, [string]$file, [string]$dest, [object[]]$tree) {
	$size = ($tree | Where-Object { $_.path -eq $file }).size
	if (-not $size) { Write-Host "配布元に無い: $repo/$file"; return }
	if ((Test-Path $dest) -and (Get-Item $dest).Length -eq $size) { Write-Host "取得済み: $(Split-Path $dest -Leaf)"; return }
	Write-Host ("取得開始: {0}（{1:N2} GB）" -f (Split-Path $dest -Leaf), ($size / 1GB))
	$sw = [Diagnostics.Stopwatch]::StartNew()
	# -C - で途中からの再開ができる
	& curl.exe -L --fail --retry 5 -C - -o $dest "https://huggingface.co/$repo/resolve/main/$file" --silent --show-error
	if ($LASTEXITCODE -ne 0) { Write-Host "失敗: $file（curl $LASTEXITCODE）"; return }
	$got = (Get-Item $dest).Length
	if ($got -ne $size) { Write-Host "大きさが違う: $file $got / $size" } else { Write-Host ("取得完了: {0}（{1:N0} 秒）" -f (Split-Path $dest -Leaf), $sw.Elapsed.TotalSeconds) }
}
foreach ($m in $list) {
	$name = $m.repo.Split('/')[1]
	$destDir = Join-Path $ModelDir "$($m.dir)\$name"
	New-Item -ItemType Directory -Force $destDir | Out-Null
	$tree = Invoke-RestMethod "https://huggingface.co/api/models/$($m.repo)/tree/main" -TimeoutSec 60
	Get-One $m.repo $m.file (Join-Path $destDir $m.file) $tree
	if ($m.mmproj) {
		$base = [IO.Path]::GetFileNameWithoutExtension($m.file) -replace '-(UD-)?(Q\d.*|MXFP4)$', ''
		$kind = ([IO.Path]::GetFileNameWithoutExtension($m.mmproj) -split '-')[-1]
		Get-One $m.repo $m.mmproj (Join-Path $destDir "mmproj-$base-$kind.gguf") $tree
	}
}
Write-Host '全件終了'
