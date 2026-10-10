# 試験スクリプトが使う場所を 1 か所で決める（p261002-01）
# root に config.cmd があれば、その set 行を読む（配布物ではこれを書き換えるだけで場所が変わる）
# 無ければ環境変数、それも無ければ開発用の PC の場所にする
$LlmRoot = (Resolve-Path "$PSScriptRoot/../..").Path
# config.cmd の set 行を読む。cmd のファイルは SJIS なので CP932 と決めて読む（Encoding.Default は pwsh 7 では UTF-8 になる）
# %~dp0 は config.cmd の置き場所（末尾に \ が付く）。ほかの %変数% は cmd と同じく環境変数で展開する
function Read-LlmConfig([string]$path, [string]$root) {
	$conf = @{}
	if (-not (Test-Path $path)) { return $conf }
	foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::GetEncoding(932))) {
		if ($line -match '^\s*set\s+"?(LLM_[A-Z_]+)=([^"]*)"?\s*$') {
			$conf[$Matches[1]] = [Environment]::ExpandEnvironmentVariables($Matches[2].Replace('%~dp0', $root.TrimEnd('\') + '\'))
		}
	}
	return $conf
}
$llmConfig = Read-LlmConfig (Join-Path $LlmRoot 'config.cmd') $LlmRoot
function Get-LlmSetting([string]$name, [string]$default) {
	if ($llmConfig[$name]) { return $llmConfig[$name] }
	$v = [Environment]::GetEnvironmentVariable($name)
	if ($v) { return $v }
	return $default
}
# 配布物では bin\node（エージェント入りの Node.js）を先に探す。開発用の PC には無いので何も変わらない
$llmNode = Join-Path $LlmRoot 'bin\node'
if ((Test-Path $llmNode) -and -not ($env:PATH -like "$llmNode;*")) { $env:PATH = "$llmNode;$env:PATH" }
# モデルの置き場
$LlmModelDir = Get-LlmSetting 'LLM_MODEL_DIR' 'C:\AI-models'
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
# llama-server のポート。各スクリプトの -Port を省いたときに使う。既定は Ollama と同じ 11434
$LlmPort = [int](Get-LlmSetting 'LLM_PORT' '11434')
# エージェントの出力ファイルを読む。時間切れで止めた後も子プロセスが開いたままのことがあるので、
# ほかのプロセスが開いていても読める開き方にし、読めなければ何回かやり直す。それでも駄目なら空を返す
function Read-LlmText([string]$path) {
	if (-not (Test-Path $path)) { return '' }
	for ($i = 0; $i -lt 10; $i++) {
		try {
			$fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
			try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); return $sr.ReadToEnd() } finally { $fs.Dispose() }
		} catch { Start-Sleep -Milliseconds 500 }
	}
	return ''
}
# llama-server を立てる前に、ポートが空いているかを見る（i261003-01）
# 別のプログラムが待っていると、/health の確認がそちらに届いて通ってしまう
# 繋がれば使用中。0.0.0.0 で待つプログラムには 127.0.0.1 で bind できてしまうことがあるため、先に繋いで確かめる
function Test-LlmPortFree([int]$port) {
	$c = New-Object Net.Sockets.TcpClient
	try {
		if ($c.ConnectAsync('127.0.0.1', $port).Wait(500) -and $c.Connected) { return $false }
	} catch {} finally { $c.Close() }
	$l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port)
	try { $l.Start(); return $true } catch { return $false } finally { $l.Stop() }
}
# 起動したプロセスを、この PowerShell が終わったら OS が止めるようにする（i261003-01）
# 窓を × で閉じる・強制終了すると finally が走らず、llama-server が残っていた
# ジョブオブジェクトに「最後のハンドルが閉じたら中を止める」を付けて入れる。ハンドルはこの PowerShell が持ち、終われば OS が閉じる
function Add-LlmKillOnClose([Diagnostics.Process]$proc) {
	if (-not ('LlmJob' -as [type])) {
		Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LlmJob {
	[StructLayout(LayoutKind.Sequential)] struct BASIC { public long a, b; public uint LimitFlags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
	[StructLayout(LayoutKind.Sequential)] struct IO { public ulong a, b, c, d, e, f; }
	[StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC Basic; public IO Io; public UIntPtr g, h, i, j; }
	[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string name);
	[DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, ref EXT info, int len);
	[DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
	static IntPtr job = IntPtr.Zero;
	public static void Add(IntPtr proc) {
		if (job == IntPtr.Zero) {
			job = CreateJobObject(IntPtr.Zero, null);
			var info = new EXT();
			info.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
			if (!SetInformationJobObject(job, 9, ref info, Marshal.SizeOf(typeof(EXT)))) throw new System.ComponentModel.Win32Exception();
		}
		if (!AssignProcessToJobObject(job, proc)) throw new System.ComponentModel.Win32Exception();
	}
}
'@
	}
	[LlmJob]::Add($proc.Handle)
}
# 時間切れの既定（秒）。NVIDIA GPU（CUDA 版）は 10 分、Intel GPU（Vulkan 版）と CPU 版は 15 分（r260929-01）
# 名前に Thinking・Reasoning が入るモデルは、--reasoning off でも長く考えるので倍にする
function Get-LlmTimeout([string]$llamaDir, [string]$model) {
	$sec = if ($llamaDir -eq 'llama.cpp' -or $llamaDir -like '*-cuda') { 600 } else { 900 }
	if ($model -match 'Thinking|Reasoning') { $sec *= 2 }
	return $sec
}
# GPU に何層載せるかの引数（i261003-01）。$devices は llama-server --list-devices の出力
# Vulkan 版: 大きさに関わらず全部載せる。-ngl を渡さないと 12B は Intel に載らず CPU で動いた
#   Intel に全部載せるとプロンプトの処理が CPU の 4.6 倍。NVIDIA も見える PC では NVIDIA に分けて載せようとして足りなくなるので、Intel だけを使う
# CPU 版: 何も付けない
# CUDA 版（RTX 3050 Ti 4GB）: 3.2GB 以下だけ全部載せ、大きいものは自動配置に任せる（r260929-01 の試験条件）
function Get-LlmGpuArgs([string]$llamaDir, [long]$size, [string]$devices) {
	if ($llamaDir -like '*-vulkan') {
		$m = [regex]::Matches($devices, '(Vulkan\d+):\s*(.+)') | Where-Object { $_.Groups[2].Value -notmatch 'NVIDIA' } | Select-Object -First 1
		$dev = if ($m -and $devices -match 'NVIDIA') { "--device $($m.Groups[1].Value)" } else { '' }
		# 空きの 8 割に収まらないものは全部は載らない（15.7GB の Qwen3.6-35B は -ngl 99 で起動しなかった）。-ngl を付けず、入る分だけを自動で載せる
		$free = if ($m -and $m.Groups[2].Value -match ',\s*(\d+) MiB free') { [long]$Matches[1] * 1MB } else { 0 }
		$ngl = if ($free -and $size -gt $free * 0.8) { '' } else { '-ngl 99' }
		return (($ngl, $dev) | Where-Object { $_ }) -join ' '
	}
	if ($llamaDir -like '*-cpu') { return '' }
	if ($size -le 3.2GB) { return '-ngl 99' }
	return ''
}
# Vulkan 版のときだけ、見えるデバイスの一覧を取る
function Get-LlmDevices([string]$llamaDir) {
	if ($llamaDir -notlike '*-vulkan') { return '' }
	$exe = Join-Path $LlmRoot "bin/$llamaDir/llama-server.exe"
	if (-not (Test-Path $exe)) { return '' }
	$ErrorActionPreference = 'Continue'
	return (& $exe --list-devices 2>&1 | Out-String)
}
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
