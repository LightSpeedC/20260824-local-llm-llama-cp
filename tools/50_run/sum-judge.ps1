# 初期プログラミングの問（sum）の判定。test-agents.ps1・test-cc-tools.ps1 から読み込む（p260930-02）
# ① sum.js ができたか ② node sum の出力が 55 だけか ③ 答えに 55 があるか ④ ソース ⑤ 作業ログに node sum の実行があるか

$SumPrompt = '1から10までの合計を表示するnode.jsプログラムをsum.jsに書く。node sumで実行する'
$EchoText = '日本語の確認です。合計は五十五。'
$EchoPrompt = "次の文を、そのまま一字も変えずに繰り返してください: $EchoText"

function Test-SumResult([string]$work, [string]$answer, [string]$toolLog, [string]$saveAs) {
	$src = Join-Path $work 'sum.js'
	$r = [ordered]@{ file = 'なし'; run_out = ''; run_pass = $false; report_pass = $false; log_ran = $false; pass = $false }
	if (Test-Path $src) {
		$r.file = 'あり'
		$code = [IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
		# ④ ソースは目で見るために残す
		[IO.File]::WriteAllText("$saveAs-sum.js", $code, (New-Object Text.UTF8Encoding($false)))
		# ② エージェントの答えとは別に、試験側で実行して確かめる
		$psi = New-Object Diagnostics.ProcessStartInfo
		$psi.FileName = 'node'
		$psi.Arguments = 'sum'
		$psi.WorkingDirectory = $work
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
		$p = [Diagnostics.Process]::Start($psi)
		$outTask = $p.StandardOutput.ReadToEndAsync()
		$errTask = $p.StandardError.ReadToEndAsync()
		if (-not $p.WaitForExit(20000)) { $p.Kill(); $r.run_out = '（20 秒で終わらない）' }
		else { $r.run_out = ($outTask.Result + $errTask.Result).Trim() }
		$r.run_pass = ($outTask.Result.Trim() -eq '55')
	}
	$r.report_pass = ($answer -match '(?<!\d)55(?!\d)')
	# ⑤ 道具の呼び出し（JSON の command）か、Aider の「Running」行に node sum があるか
	$r.log_ran = ($toolLog -match '"command"\s*:\s*"[^"]*node\s+sum' -or $toolLog -match '(?m)^\s*Running\s+node\s+sum')
	$r.pass = ($r.file -eq 'あり' -and $r.run_pass -and $r.report_pass)
	return $r
}
