# tests/ のテストをすべて流す。1 本でも落ちたら終了コード 1
$ErrorActionPreference = 'Stop'
$tests = (Resolve-Path "$PSScriptRoot/../../tests").Path
if (-not $tests) { throw 'tests フォルダが見つかりません' }
$files = Get-ChildItem $tests -Filter '*.tests.ps1'
if (-not $files) { throw 'テストが 1 本もありません' }
$ng = 0
foreach ($f in $files) {
	Write-Host "=== $($f.Name)"
	& powershell -NoProfile -ExecutionPolicy Bypass -File $f.FullName
	if ($LASTEXITCODE) { $ng++ }
}
Write-Host ''
if ($ng) { Write-Host "❌ 落ちたテスト $ng 本 / $($files.Count) 本"; exit 1 }
Write-Host "✅ すべて通った（$($files.Count) 本）"
