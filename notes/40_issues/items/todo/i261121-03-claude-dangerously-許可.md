---
schema: 1
id: i261121-03
title: Claude Code の権限を dangerously で許可し、project を信頼済みにする
group: 運用
created: 2026-11-21
---

利用者の依頼 (2026-11-21): Claude Code を dangerously で許可して動かす。Claude 用のホームに `.claude.json` を置いて、project を信頼済みにする。

決まったこと: 決定 13 (13-C)・14 (14-B)・15 (15-C)・19 (19-A)。`issue decide list --parent i261121-03` で見る。

- 対象は、試験 (test-cc-tools.ps1) と、利用者向けの起動 (start-agent.ps1 と配布物の `claude-*.cmd`) の両方。単体の claude.exe も npm 版と同じに扱う
- 利用者向けの起動は、常に `--dangerously-skip-permissions` を付ける (設定で切れない)
- 試験は、従来の `--permission-mode acceptEdits` と `--allowedTools "Bash(node:*)"` をやめ、`--dangerously-skip-permissions` に置き換える (従来の形は残さない)
- 起動のたびに、空のホームの `.claude.json` へ、実際の作業フォルダを `projects[<パス>].hasTrustDialogAccepted = true` で足し、ホームの `.claude\settings.json` に `skipDangerousModePermissionPrompt: true` を足す。すでにある鍵は残す

今ある動き:

- 試験: test-cc-tools.ps1 は `claude -p --permission-mode acceptEdits` で起動し、sum の問だけ `--allowedTools "Bash(node:*)"` を足す。`-NoRules` の既定で、`USERPROFILE` と `HOME` を空のホームに向ける
- 利用者向け: start-agent.ps1 の claude・claude-exe は、`USERPROFILE` と `HOME` を空のホームに向け、`ANTHROPIC_*` 等の環境変数を決め、引数なしで `claude.cmd` または `bin/claude/claude.exe` を起動する。権限の指定は無く、通常の確認が出る
- どの試験で守るか: まだ確かめていない。実装の前に、試験の有無を確かめる
- ホームは 3 つある (2026-11-21 のレビューで確かめた)。start-agent.ps1 の claude と claude-exe は、別々のホーム (`$LlmAgentHome\<Agent>`、98 行)。試験 (`-NoRules`) は `$LlmCcHome` (87 行)。試験の `-WithRules` は、ホームを向けず、利用者の本物のホームで動く。`.claude.json` は、使うホームごとに要る
- 作業フォルダは、start-agent.ps1 が `-WorkDir` か、既定の `<sandbox の親>\project` (100 行)。試験は `$LlmSandbox` (1 問ごとに中身を消す)

実装前のレビュー (2026-11-21) の結果、仮に決めたこと (利用者には聞かず記録。実装の前に覆してよい):

- `.claude.json` へ足す処理は、別の関数 1 つにする。書く直前に読み直して足し、書いた後に読み戻して確かめ、差があれば警告する。鍵が既にあれば書かない (読むだけ。書き込みの回数と、競合の窓を減らす)
- 一時ファイルに書いてから置き換える (部分書きを避ける)
- 書き込みは、start-agent.ps1 の、ポートの使用中の確認 (65 行) の後で、エージェントを起動する直前に置く。同じエージェントを 2 つ起動したとき、先に書いてしまう順序を避ける
- 結果ファイルに、権限の形 (`permission` の鍵) を入れる。過去の結果 (acceptEdits ＋ allowedTools) と、条件の違いが分かるようにする
- 作業フォルダのパスの書き方を確かめるとき、subst の `W:` と実体 (`C:`) の違いも見る。start-agent.ps1 は `Set-Location $WorkDir` (102 行) で入るので、Claude Code が見る cwd がどちらの形になるかを、実測で確かめる
- 配布物の `run\claude-*.cmd` は、start-agent.ps1 を引数付きで呼ぶだけ (make-offline-bundle.ps1:113〜127 が生成)。cmd 側の変更は不要で、start-agent.ps1 だけで足りる

先に書く試験 (先に ❌Red を見る): ホームの `.claude.json` へ足す関数を、別の関数にして、一時のホームで試験する。既存の鍵が残る・無いとき新規に作る・不正な JSON のとき書かずに止まる・読めない、または書けないとき止まる・足した後に解析し直せる。

後でよいこと (記録):

- 試験の `-WithRules` は、20-B により、利用者の本物の CLAUDE.md・フックが、確認なしの状態で動く。フックが破壊的だと、確認なしで及ぶ
- 試験の作業フォルダ (`$LlmSandbox`、`W:/temp/…`) の信頼が、本物の `~/.claude.json` に永続して残る。消す手順は決めていない
- 配布物の現地で、確認なしの起動を止める方法は、`claude-*.cmd` を使わないことだけ。使い方.html に書く
- 試験の作業フォルダに写す `.claude/settings.json` (test-cc-tools.ps1:50) に、許可・フックがあれば、dangerously でも読まれる。フックは動く見込み (確かめていない)

未決 (利用者に聞く): `.claude.json` の読み書きの方式、`-p` (非対話) で信頼と同意の確認が出るかの実測と、出ないときの扱い、書けなかったときの止まり方。

気づいた点 (記録):

- 利用者向けに常に付けると、確認なしでファイルの削除・上書き・コマンドの実行が通る。作業フォルダの外へも及ぶ (利用者が選んだ)
- 試験の権限の形が変わるので、過去の結果 (acceptEdits) と条件が違う。試験結果の資料と、結果ファイルへの記録の仕方を、実装のときに決める

確かめること (実装の前):

- Windows でのパスの書き方 (区切りが `\` か `/` か、ドライブ文字の大文字小文字)。`claude purge <フォルダ> --dry-run` の出力で見る。公式の例は Linux 形式だけ
- `USERPROFILE` を向けたとき、`.claude.json` と `settings.json` がどこから読まれるか (公式の資料に書かれていない)
- 手で書いた `.claude.json` を、Claude Code が起動時に書き戻すか
- `bypassPermissionsModeAccepted` が効くか (公式の設定リファレンスに無い。使わない案)
- 鍵の名前そのもの (`hasTrustDialogAccepted`・`skipDangerousModePermissionPrompt`) を、公式の設定リファレンスと、実際に Claude Code が書いた `.claude.json`・`settings.json` で確かめる。サブエージェントが公式資料から読んだ名前で、実機では確かめていない
- `claude purge` に `--dry-run` があるか
- start-agent.ps1 の `-WorkDir` には、利用者が実在の重要なフォルダを渡せる。dangerously を常に付けるので、渡したフォルダの中身にも確認なしで及ぶ (記録)
- 試験の `-WithRules` のときの権限と書き込み先: 決定 20 (20-B)。`-WithRules` でも `--dangerously-skip-permissions` を付け、利用者の本物のホームの `.claude.json` と `.claude\settings.json` に、信頼と同意の省略を書く
- 20-B の結果として、実装の前に確かめること: (1) `skipDangerousModePermissionPrompt: true` を本物の `~/.claude/settings.json` に書くと、利用者の全セッションで、dangerously の初回の確認が出なくなる (利用者が選んだ。記録)。(2) 本物の `~/.claude.json` は、実行中の Claude Code (この開発セッションを含む) も書き戻すので、書き込みが競合して、どちらかが消える恐れがある (確かめていない)。書く前に、読み直して足す形にするか、書いた後に読み戻して確かめる形にするか、実装のときに決める
- 決定の一覧は `issue decide list --parent i261121-03` で見る (決定 13・14・15・19・20)
- 調べの結果は、この課題の番号で、`notes/01_research/` に資料として書く

## やること
- [未] 実装の前に確かめる (Windows のパス表記・USERPROFILE での置き場・書き戻し) と、調査の資料を notes/01_research/ に書く
- [未] 今ある動き (test-cc-tools.ps1 の起動・start-agent.ps1 の claude と claude-exe) を守る試験の有無を確かめ、無ければ足す (先に ❌Red を見る)
- [未] start-agent.ps1: 起動のたびに、空のホームの .claude.json と .claude\settings.json へ信頼と同意の省略を足し、claude・claude-exe に --dangerously-skip-permissions を付ける
- [未] test-cc-tools.ps1: acceptEdits と --allowedTools をやめ --dangerously-skip-permissions に置き換え、試験のホームに信頼を書く
- [未] 試験結果の資料と結果ファイルに、権限の形が変わったことを記録する
- [未] 配布物の使い方.html に反映し、組み立て直す
