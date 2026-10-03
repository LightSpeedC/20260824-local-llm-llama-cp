# 初期プログラミングの問（sum）の判定。test-agents.ps1・test-cc-tools.ps1 から読み込む（p260930-02）
# ① sum.js ができたか ② node sum の出力に 55 があるか ③ 答えに 55 があるか ④ ソース ⑤ 作業ログに node sum の実行があるか

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
		# 「1から10までの合計: 55」のような表示も正しい。55 という数が単独で出ていれば合格にする
		$r.run_pass = ($outTask.Result -match '(?<!\d)55(?!\d)')
	}
	$r.report_pass = ($answer -match '(?<!\d)55(?!\d)')
	$r.log_ran = Test-SumTrace $toolLog
	$r.pass = ($r.file -eq 'あり' -and $r.run_pass -and $r.report_pass)
	return $r
}

# 結果ファイルの 1 回分を記号にする。✅ 合格・☑️ 補欠合格（合っているが node で実行した跡が無い）・❌ 不合格・⏱️ 時間切れ
function Get-SumMark($r) {
	if (-not $r) { return '—' }
	if ($r.status -ne 'ok') { return '⏱️' }
	$run = ($r.run_out -match '(?<!\d)55(?!\d)')
	if ($r.file -eq 'あり' -and $run -and $r.report_pass) { if ($r.log_ran) { return '✅' } else { return '☑️' } }
	return '❌'
}

# 1 回だけの表のマス。合格には秒数、不合格には落ち方を添える
function Format-SumCell($r) {
	$mark = Get-SumMark $r
	switch ($mark) {
		'—' { return '—' }
		'⏱️' { return '⏱️ 時間切れ' }
		'✅' { return "✅ 合格 $([Math]::Round([double]$r.sec)) 秒" }
		'☑️' { return "☑️ 補欠合格 $([Math]::Round([double]$r.sec)) 秒" }
	}
	$why = if ($r.file -ne 'あり') { 'sum.js を作らない' }
		elseif ($r.run_out -notmatch '(?<!\d)55(?!\d)') { '書いたが 55 が出ない' }
		elseif ($r.log_ran) { '実行したが結果を答えない' }
		else { '書いたが実行・報告なし' }
	return "❌ 不合格 $why"
}

# ⑤ 道具の呼び出し（JSON の command）か、Aider の「Running」行に node で sum を実行した跡があるか
# パス付き（node /w/temp/llama-cp-sandbox/sum.js・node W:\\temp\\…\\sum.js）も拾う
function Test-SumTrace([string]$toolLog) {
	$cmd = 'node\s+[^"\s]*?sum(\.js)?(?![\w.])'
	return ($toolLog -match ('"command"\s*:\s*"[^"]*' + $cmd) -or $toolLog -match ('(?m)^\s*Running\s+' + $cmd))
}
