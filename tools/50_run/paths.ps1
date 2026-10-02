# 試験スクリプトが使う場所を 1 か所で決める（p261002-01）
# root に config.cmd があれば、その set 行を読む（配布物ではこれを書き換えるだけで場所が変わる）
# 無ければ環境変数、それも無ければ開発用の PC の場所にする
$LlmRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$llmConfig = @{}
$configCmd = Join-Path $LlmRoot 'config.cmd'
if (Test-Path $configCmd) {
	foreach ($line in [IO.File]::ReadAllLines($configCmd, [Text.Encoding]::Default)) {
		if ($line -match '^\s*set\s+"?(LLM_[A-Z_]+)=([^"]*)"?\s*$') {
			# %~dp0 は config.cmd の置き場所（末尾に \ が付く）
			$llmConfig[$Matches[1]] = $Matches[2].Replace('%~dp0', $LlmRoot.TrimEnd('\') + '\')
		}
	}
}
function Get-LlmSetting([string]$name, [string]$default) {
	if ($llmConfig[$name]) { return $llmConfig[$name] }
	$v = [Environment]::GetEnvironmentVariable($name)
	if ($v) { return $v }
	return $default
}
# モデルの置き場
$LlmModelDir = Get-LlmSetting 'LLM_MODEL_DIR' 'C:\AI_Models'
# エージェントの作業フォルダと空のホーム。git のリポジトリの外に置く（中に置くと、モデルが root を推測して本物を読みにいく）
$llmWork = Get-LlmSetting 'LLM_WORK_DIR' ''
if ($llmWork) {
	$LlmSandbox = Join-Path $llmWork 'sandbox'
	$LlmAgentHome = Join-Path $llmWork 'agent-home'
	$LlmCcHome = Join-Path $llmWork 'cc-home'
} else {
	$LlmSandbox = 'W:/temp/llama-cp-sandbox'
	$LlmAgentHome = 'W:/temp/llama-cp-agent-home'
	$LlmCcHome = 'W:/temp/llama-cp-home'
}
# 使う llama.cpp（bin の下のフォルダ名）。auto は Vulkan 版に GPU が見えれば Vulkan、見えなければ CPU
$LlmBackend = Get-LlmSetting 'LLM_BACKEND' 'llama.cpp'
function Resolve-LlmBackend([string]$name) {
	if ($name -ne 'auto') { return $name }
	$vk = Join-Path $LlmRoot 'bin/llama.cpp-b11320-vulkan/llama-server.exe'
	if (Test-Path $vk) {
		$ErrorActionPreference = 'Continue'
		$dev = & $vk --list-devices 2>&1 | Out-String
		if ($dev -match 'Vulkan\d+:') { return 'llama.cpp-b11320-vulkan' }
	}
	return 'llama.cpp-b11320-cpu'
}
