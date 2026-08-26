# HTML → Markdown 変換スクリプト
#
# HTML を正とし、Markdown はここから生成する。
# Markdown を直接編集しない（次回実行で上書きされる）。
#
# 処理内容:
#   - インライン SVG を images/ に切り出し、![](images/xxx.svg) で参照する
#   - .callout を GitHub のアラート記法（> [!NOTE] 等）に変換する
#   - .badge の色分けを記号＋太字に落とす
#   - <table> を Markdown テーブルに変換する（rowspan / colspan も展開する）
#   - 目次の #chNN リンクを、Markdown の見出しアンカーに張り替える
#   - リンクの .html を .md に置き換える

$ErrorActionPreference = 'Stop'

# 変換対象（プロジェクトルートからの相対パス）
$targets = @(
	'README.html',
	'docs\plan\local-llm-plan.html',
	'docs\plan\agent-architecture.html',
	'docs\research\speculative-decoding.html',
	'docs\research\hp-zgx-nano.html'
)

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Write-Host "プロジェクトルート: $root"

# プレースホルダはタグに見えない形にする（タグ除去で消えるため）
$BR = '@@BR@@'

# ------------------------------------------------------------
# ユーティリティ
# ------------------------------------------------------------

function ConvertFrom-HtmlEntity {
	param([string]$s)
	$s = $s -replace '&lt;', '<'
	$s = $s -replace '&gt;', '>'
	$s = $s -replace '&quot;', '"'
	$s = $s -replace '&#39;', "'"
	$s = $s -replace '&nbsp;', ' '
	$s = $s -replace '&amp;', '&'   # 最後に処理する
	return $s
}

# 見出しテキストから GitHub の見出しアンカーを作る
function Get-Anchor {
	param([string]$heading)
	$a = $heading.ToLower()
	$a = $a -replace '`', ''
	$a = $a -replace '\*\*', ''
	# 文字・数字・空白・ハイフン・アンダースコア以外を落とす
	$a = $a -replace '[^\p{L}\p{Nd}\s_-]', ''
	$a = $a.Trim() -replace '\s', '-'
	return $a
}

# バッジ（色分け）を記号＋太字に落とす
function Convert-Badge {
	param([string]$s)
	$map = [ordered]@{
		'b-ok'   = '✅'
		'b-ng'   = '❌'
		'b-warn' = '⚠️'
		'b-non'  = '⬜'
	}
	foreach ($cls in $map.Keys) {
		$mark = $map[$cls]
		$s = [regex]::Replace($s, "<span class=`"badge $cls`">(.*?)</span>", {
			param($m) "**$mark $($m.Groups[1].Value)** "
		})
	}
	# 未知のバッジは太字だけにする
	$s = [regex]::Replace($s, '<span class="badge[^"]*">(.*?)</span>', '**$1** ')
	return $s
}

function Convert-Inline {
	param([string]$s)

	$s = Convert-Badge $s

	# 改行は後で復元する（タグ除去で消えないプレースホルダにする）
	$s = $s -replace '<br\s*/?>', $script:BR

	# リンク: 内部リンクは .html を .md にする
	$s = [regex]::Replace($s, '<a\s+href="([^"]+)"[^>]*>(.*?)</a>', {
		param($m)
		$href = $m.Groups[1].Value
		$text = $m.Groups[2].Value
		if ($href -notmatch '^(https?:|#)') { $href = $href -replace '\.html($|#)', '.md$1' }
		"[$text]($href)"
	})

	$s = $s -replace '<code>(.*?)</code>', '`$1`'
	$s = $s -replace '<strong>(.*?)</strong>', '**$1**'
	$s = $s -replace '<em>(.*?)</em>', '*$1*'
	$s = $s -replace '<tspan[^>]*>(.*?)</tspan>', '$1'

	# 残ったタグを除去する
	$s = $s -replace '<[^>]+>', ''

	$s = ConvertFrom-HtmlEntity $s
	$s = $s -replace '\s+', ' '
	return $s.Trim()
}

function Convert-Cell {
	param([string]$s)
	$t = Convert-Inline $s
	$t = $t -replace [regex]::Escape($script:BR), '<br>'
	$t = $t -replace '\|', '\|'      # テーブルを壊さないため
	return $t
}

# ------------------------------------------------------------
# テーブル変換（rowspan / colspan を展開する）
# ------------------------------------------------------------
function Convert-Table {
	param([string]$html)

	$rows = @()
	foreach ($rm in [regex]::Matches($html, '(?s)<tr[^>]*>(.*?)</tr>')) {
		$cells = @()
		foreach ($cm in [regex]::Matches($rm.Groups[1].Value, '(?s)<(t[hd])([^>]*)>(.*?)</\1>')) {
			$attr = $cm.Groups[2].Value
			$cells += [pscustomobject]@{
				Html    = $cm.Groups[3].Value
				ColSpan = if ($attr -match 'colspan="(\d+)"') { [int]$Matches[1] } else { 1 }
				RowSpan = if ($attr -match 'rowspan="(\d+)"') { [int]$Matches[1] } else { 1 }
				IsNum   = $attr -match 'class="[^"]*(^|\s)num(\s|")'
			}
		}
		if ($cells.Count -gt 0) { $rows += ,$cells }
	}
	if ($rows.Count -eq 0) { return '' }

	$grid = @{}
	$numCol = @{}
	$maxCol = 0
	$rowCount = 0
	for ($r = 0; $r -lt $rows.Count; $r++) {
		$c = 0
		foreach ($cell in $rows[$r]) {
			while ($grid.ContainsKey("$r,$c")) { $c++ }
			$text = Convert-Cell $cell.Html
			for ($dr = 0; $dr -lt $cell.RowSpan; $dr++) {
				for ($dc = 0; $dc -lt $cell.ColSpan; $dc++) {
					$rr = $r + $dr; $cc = $c + $dc
					$grid["$rr,$cc"] = if ($dr -eq 0 -and $dc -eq 0) { $text } else { '' }
					if ($rr + 1 -gt $rowCount) { $rowCount = $rr + 1 }
				}
			}
			if ($cell.IsNum) { $numCol[$c] = $true }
			$c += $cell.ColSpan
			if ($c -gt $maxCol) { $maxCol = $c }
		}
	}

	$sb = New-Object Text.StringBuilder
	for ($r = 0; $r -lt $rowCount; $r++) {
		$line = @()
		for ($c = 0; $c -lt $maxCol; $c++) {
			$line += if ($grid.ContainsKey("$r,$c")) { $grid["$r,$c"] } else { '' }
		}
		[void]$sb.AppendLine('| ' + ($line -join ' | ') + ' |')
		if ($r -eq 0) {
			$sep = @()
			for ($c = 0; $c -lt $maxCol; $c++) {
				$sep += if ($numCol.ContainsKey($c)) { '---:' } else { '---' }
			}
			[void]$sb.AppendLine('| ' + ($sep -join ' | ') + ' |')
		}
	}
	return $sb.ToString()
}

# ------------------------------------------------------------
# callout 変換（内容から種類を判定する）
# ------------------------------------------------------------
function Convert-Callout {
	param([string]$inner)

	$text = Convert-Inline $inner
	$text = $text -replace [regex]::Escape($script:BR), ' '

	$kind = 'NOTE'
	if ($text -match '危険|してはいけない|崩壊|失わ|壊れ|注意|危ない') { $kind = 'WARNING' }
	elseif ($text -match '必ず|重要|忘れず|絶対') { $kind = 'IMPORTANT' }

	$sb = New-Object Text.StringBuilder
	[void]$sb.AppendLine("> [!$kind]")
	[void]$sb.AppendLine("> $text")
	return $sb.ToString()
}

# ------------------------------------------------------------
# SVG 切り出し
# ------------------------------------------------------------
function Export-Svg {
	param([string]$svg, [string]$outPath)

	$w = 900; $h = 300
	if ($svg -match 'viewBox="\s*[\d.-]+\s+[\d.-]+\s+([\d.]+)\s+([\d.]+)') {
		$w = [math]::Round([double]$Matches[1]); $h = [math]::Round([double]$Matches[2])
	}

	# 単体ファイルとして開けるよう xmlns と寸法を付ける
	$svg = [regex]::Replace($svg, '^<svg', "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$w`" height=`"$h`"", 'IgnoreCase')
	$svg = $svg -replace '\s+role="[^"]*"', ''

	# ダークモードで文字が読めなくなるのを防ぐため白背景を敷く
	$svg = [regex]::Replace($svg, '(?s)(<svg[^>]*>)', "`$1`n`t<rect width=`"100%`" height=`"100%`" fill=`"#ffffff`"/>", 'IgnoreCase')

	$dir = Split-Path $outPath -Parent
	if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
	[IO.File]::WriteAllText($outPath, $svg, (New-Object Text.UTF8Encoding($false)))
}

# ------------------------------------------------------------
# 本体
# ------------------------------------------------------------
function Convert-HtmlFile {
	param([string]$htmlPath)

	$mdPath  = [IO.Path]::ChangeExtension($htmlPath, '.md')
	$baseDir = Split-Path $mdPath -Parent
	$imgDir  = Join-Path $baseDir 'images'
	$stem    = [IO.Path]::GetFileNameWithoutExtension($htmlPath)

	$t = [IO.File]::ReadAllText($htmlPath, [Text.Encoding]::UTF8)

	# --- 章 id と見出しの対応表を作る（目次のアンカー張り替え用）---
	$anchorMap = @{}
	$chNo = 0
	foreach ($sm in [regex]::Matches($t, '(?s)<section[^>]*id="([^"]+)"[^>]*>\s*<h1>(.*?)</h1>')) {
		$chNo++
		$id = $sm.Groups[1].Value
		$heading = "$chNo. " + (Convert-Inline $sm.Groups[2].Value)
		$anchorMap["#$id"] = '#' + (Get-Anchor $heading)
	}

	# --- SVG を切り出してプレースホルダに置き換える ---
	$script:svgCount = 0
	$t = [regex]::Replace($t, '(?s)<svg\b.*?</svg>', {
		param($m)
		$script:svgCount++
		$name = "$($script:stem)-fig$($script:svgCount).svg"
		Export-Svg -svg $m.Value -outPath (Join-Path $script:imgDir $name)
		$alt = if ($m.Value -match 'aria-label="([^"]*)"') { $Matches[1] } else { "図$($script:svgCount)" }
		"`n@@FIG:$alt|images/$name@@`n"
	})
	Write-Host ("  SVG を {0} 個切り出しました" -f $script:svgCount)

	# --- pre/code を退避する ---
	$script:pres = New-Object Collections.ArrayList
	$t = [regex]::Replace($t, '(?s)<pre[^>]*>\s*<code[^>]*>(.*?)</code>\s*</pre>', {
		param($m)
		$code = ConvertFrom-HtmlEntity $m.Groups[1].Value
		$code = ($code -replace "`r`n", "`n").Trim()
		$i = $script:pres.Add($code)
		"`n@@PRE:$i@@`n"
	})

	$t = [regex]::Replace($t, '(?s)<head\b.*?</head>', '')
	$t = [regex]::Replace($t, '(?s)<style\b.*?</style>', '')

	$sb = New-Object Text.StringBuilder

	# --- タイトルバー ---
	if ($t -match '(?s)<div class="titlebar">.*?<h1>(.*?)</h1>\s*<div class="meta">(.*?)</div>') {
		$rawTitle = $Matches[1]
		$rawMeta  = $Matches[2]
		[void]$sb.AppendLine('# ' + (Convert-Inline $rawTitle))
		[void]$sb.AppendLine()
		$meta = Convert-Inline $rawMeta
		foreach ($ln in ($meta -split [regex]::Escape($BR))) {
			$ln = $ln.Trim()
			if ($ln) { [void]$sb.AppendLine("> $ln") }
		}
		[void]$sb.AppendLine()
	}

	# --- 本文 ---
	$bodyHtml = if ($t -match '(?s)<div class="wrap">(.*?)</body>') { $Matches[1] } else { $t }

	# 名前付きグループにして番号のずれを避ける
	$pattern = '(?s)' + (@(
		'<section[^>]*>',
		'</section>',
		'<div class="callout"[^>]*>(?<callout>.*?)</div>\s*(?=<|@@|$)',
		'<div class="tablewrap">\s*(?<table><table.*?</table>)\s*</div>',
		'(?<table2><table.*?</table>)',
		'<div class="toc">(?<toc>.*?)</div>\s*(?=<h2|<!--)',
		'<div class="minibar">(?<minibar>.*?)</div>',
		'<h1>(?<h1>.*?)</h1>',
		'<h2[^>]*>(?<h2>.*?)</h2>',
		'<h3[^>]*>(?<h3>.*?)</h3>',
		'<ul>(?<ul>.*?)</ul>',
		'<ol>(?<ol>.*?)</ol>',
		'<p[^>]*>(?<p>.*?)</p>',
		'@@FIG:(?<figalt>.*?)\|(?<figsrc>.*?)@@',
		'@@PRE:(?<pre>\d+)@@',
		'<footer>(?<footer>.*?)</footer>'
	) -join '|')

	$chapter = 0
	foreach ($m in [regex]::Matches($bodyHtml, $pattern)) {

		if ($m.Groups['figalt'].Success) {
			[void]$sb.AppendLine("![$($m.Groups['figalt'].Value)]($($m.Groups['figsrc'].Value))")
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['pre'].Success) {
			$code = $script:pres[[int]$m.Groups['pre'].Value]
			$lang = if ($code -match '^\s*(@echo off|REM )') { 'bat' }
					elseif ($code -match '^\s*(git |cmake |winget |llama-|\.\\|-ngl)') { 'sh' }
					else { 'text' }
			[void]$sb.AppendLine('```' + $lang)
			[void]$sb.AppendLine($code)
			[void]$sb.AppendLine('```')
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['callout'].Success) {
			[void]$sb.AppendLine((Convert-Callout $m.Groups['callout'].Value))
			continue
		}
		if ($m.Groups['table'].Success) {
			[void]$sb.AppendLine((Convert-Table $m.Groups['table'].Value))
			continue
		}
		if ($m.Groups['table2'].Success) {
			[void]$sb.AppendLine((Convert-Table $m.Groups['table2'].Value))
			continue
		}
		if ($m.Groups['toc'].Success) {
			[void]$sb.AppendLine('## 目次')
			[void]$sb.AppendLine()
			$n = 0
			foreach ($li in [regex]::Matches($m.Groups['toc'].Value, '(?s)<li[^>]*>(.*?)</li>')) {
				$n++
				$line = Convert-Inline $li.Groups[1].Value
				# #chNN を Markdown の見出しアンカーに張り替える
				foreach ($k in $anchorMap.Keys) {
					$line = $line -replace ('\(' + [regex]::Escape($k) + '\)'), ('(' + $anchorMap[$k] + ')')
				}
				[void]$sb.AppendLine("$n. $line")
			}
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['minibar'].Success) {
			[void]$sb.AppendLine('## ' + (Convert-Inline $m.Groups['minibar'].Value))
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['h1'].Success) {
			$chapter++
			[void]$sb.AppendLine("## $chapter. " + (Convert-Inline $m.Groups['h1'].Value))
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['h2'].Success) {
			[void]$sb.AppendLine('### ' + (Convert-Inline $m.Groups['h2'].Value))
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['h3'].Success) {
			[void]$sb.AppendLine('#### ' + (Convert-Inline $m.Groups['h3'].Value))
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['ul'].Success) {
			foreach ($li in [regex]::Matches($m.Groups['ul'].Value, '(?s)<li[^>]*>(.*?)</li>')) {
				$x = (Convert-Inline $li.Groups[1].Value) -replace [regex]::Escape($BR), ' '
				[void]$sb.AppendLine('- ' + $x)
			}
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['ol'].Success) {
			$n = 0
			foreach ($li in [regex]::Matches($m.Groups['ol'].Value, '(?s)<li[^>]*>(.*?)</li>')) {
				$n++
				$x = (Convert-Inline $li.Groups[1].Value) -replace [regex]::Escape($BR), ' '
				[void]$sb.AppendLine("$n. $x")
			}
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['footer'].Success) {
			# HTML に無い記号（水平線等）は足さない
			$f = (Convert-Inline $m.Groups['footer'].Value) -replace [regex]::Escape($BR), ' '
			[void]$sb.AppendLine($f)
			[void]$sb.AppendLine()
			continue
		}
		if ($m.Groups['p'].Success) {
			$para = Convert-Inline $m.Groups['p'].Value
			$para = $para -replace [regex]::Escape($BR), "  `r`n"
			if ($para) {
				[void]$sb.AppendLine($para)
				[void]$sb.AppendLine()
			}
			continue
		}
	}

	$md = $sb.ToString()
	$md = $md -replace [regex]::Escape($BR), '  '
	$md = [regex]::Replace($md, '(\r?\n){3,}', "`r`n`r`n")

	[IO.File]::WriteAllText($mdPath, $md, (New-Object Text.UTF8Encoding($false)))
	Write-Host ("  出力: {0} ({1:N1} KB)" -f $mdPath.Replace("$root\", ''), ((Get-Item $mdPath).Length / 1KB))
	return $mdPath
}

# ------------------------------------------------------------
# 文言の同一性の確認
#
# Markdown 側にしか存在しない文言が無いかを機械的に調べる。
# 記法由来の記号と空白をすべて落として突き合わせるため、
# 「HTML に無い文章・記号を足していないか」だけを見ることになる。
# ------------------------------------------------------------
function Get-PlainForCompare {
	param([string]$s, [switch]$FromMarkdown)

	if ($FromMarkdown) {
		$s = $s -replace '(?m)^\s*\|[\s\-:|]+\|\s*$', ''    # テーブルの区切り行
		$s = $s -replace '!\[[^\]]*\]\([^)]*\)', ''         # 画像（元は SVG なので対応する本文が無い）
		$s = $s -replace '\[([^\]]*)\]\([^)]*\)', '$1'      # リンクは表示文字だけ残す
		$s = $s -replace '(?m)^\s*>\s*\[!\w+\]\s*$', ''     # アラートの種別行
		$s = $s -replace '(?m)^\s*>\s?', ''                 # 引用
		$s = $s -replace '(?m)^\s*#{1,6}\s*', ''            # 見出し
		$s = $s -replace '(?m)^\s*```.*$', ''               # コードフェンス
		$s = $s -replace '(?m)^\s*[-*]\s+', ''              # 箇条書き
		$s = $s -replace '(?m)^\s*\d+\.\s+', ''             # 番号付きリスト
		$s = $s -replace '\\\|', '|'                        # セル内のエスケープを戻す
		$s = $s -replace '\*\*', ''                         # 太字
		$s = $s -replace '`', ''                            # コード
		$s = $s -replace '<br>', ' '
	} else {
		$s = [regex]::Replace($s, '(?s)<head\b.*?</head>', '')
		$s = [regex]::Replace($s, '(?s)<style\b.*?</style>', '')
		$s = [regex]::Replace($s, '(?s)<svg\b.*?</svg>', '')   # 図は画像として切り出される
		$s = $s -replace '<[^>]+>', ' '
		$s = ConvertFrom-HtmlEntity $s
	}

	# 色分けの代替として認められた記号は、両側から落として比較する
	$s = $s -replace '✅', ''
	$s = $s -replace '❌', ''
	$s = $s -replace '⚠️', ''
	$s = $s -replace '⚠', ''
	$s = $s -replace '⬜', ''
	$s = $s -replace '️', ''

	# テーブルの区切りと本文中の縦棒が混ざるため、両側から落として比較する
	$s = $s -replace '\|', ''

	# 空白の入り方は記法で変わるため、比較前にすべて落とす
	$s = $s -replace '\s', ''
	return $s
}

function Test-MarkdownText {
	param([string]$htmlPath, [string]$mdPath)

	$htmlPlain = Get-PlainForCompare ([IO.File]::ReadAllText($htmlPath, [Text.Encoding]::UTF8))
	$mdRaw     = [IO.File]::ReadAllText($mdPath, [Text.Encoding]::UTF8)

	$ng = 0
	foreach ($line in ($mdRaw -split "`r?`n")) {
		if (-not $line.Trim()) { continue }
		$plain = Get-PlainForCompare $line -FromMarkdown
		if ($plain.Length -lt 2) { continue }
		if (-not $htmlPlain.Contains($plain)) {
			$show = if ($line.Length -gt 70) { $line.Substring(0, 70) + '…' } else { $line }
			Write-Host ("  HTML に無い文言: {0}" -f $show.Trim()) -ForegroundColor Red
			$ng++
		}
	}
	if ($ng -eq 0) { Write-Host "  Markdown 側だけの文言なし" }
	return $ng
}

# ------------------------------------------------------------
# リンク切れの確認
# ------------------------------------------------------------
function Test-MarkdownLink {
	param([string]$mdPath)

	$t = [IO.File]::ReadAllText($mdPath, [Text.Encoding]::UTF8)
	$dir = Split-Path $mdPath -Parent
	$ng = 0
	foreach ($m in [regex]::Matches($t, '!?\[[^\]]*\]\(([^)]+)\)')) {
		$link = $m.Groups[1].Value
		if ($link -match '^(https?:|mailto:|#)') { continue }
		$target = ($link -split '#')[0]
		if (-not $target) { continue }
		if (-not (Test-Path (Join-Path $dir $target))) {
			Write-Host ("  リンク切れ: {0}" -f $link) -ForegroundColor Red
			$ng++
		}
	}
	if ($ng -eq 0) { Write-Host "  リンク切れなし" }
	return $ng
}

# ------------------------------------------------------------
# 実行
# ------------------------------------------------------------
Write-Host ''
Write-Host '=== HTML → Markdown 変換 ==='
$results = @()
foreach ($rel in $targets) {
	$path = Join-Path $root $rel
	if (-not (Test-Path $path)) {
		Write-Host "  対象なし: $rel" -ForegroundColor Yellow
		continue
	}
	Write-Host ''
	Write-Host "[$rel]"
	$script:stem   = [IO.Path]::GetFileNameWithoutExtension($path)
	$script:imgDir = Join-Path (Split-Path $path -Parent) 'images'
	$md = Convert-HtmlFile $path
	$results += [pscustomobject]@{ Html = $path; Md = $md }
}

Write-Host ''
Write-Host '=== リンク切れの確認 ==='
$ngLink = 0
foreach ($r in $results) {
	Write-Host ("[{0}]" -f $r.Md.Replace("$root\", ''))
	$ngLink += (Test-MarkdownLink $r.Md)
}

Write-Host ''
Write-Host '=== 文言の同一性の確認 ==='
$ngText = 0
foreach ($r in $results) {
	Write-Host ("[{0}]" -f $r.Md.Replace("$root\", ''))
	$ngText += (Test-MarkdownText $r.Html $r.Md)
}

Write-Host ''
if ($ngLink -eq 0 -and $ngText -eq 0) {
	Write-Host '変換が完了しました。'
} else {
	if ($ngLink -gt 0) { Write-Host ("リンク切れ {0} 件" -f $ngLink) -ForegroundColor Yellow }
	if ($ngText -gt 0) { Write-Host ("Markdown 側だけの文言 {0} 件" -f $ngText) -ForegroundColor Yellow }
	Write-Host '変換は完了しましたが、上記を確認してください。'
}
