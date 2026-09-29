# ローカルLLM で Claude Code を使う・試す手順

cc1.cmd で対話に使う手順と、試験スクリプトでモデルやエージェントを試す手順

> 📅 作成: 2026-09-30 / 更新: 2026-09-30

[README](../../README.md)

## 目次

1. [置き場所](#1-置き場所)
2. [cc1.cmd で対話に使う](#2-cc1cmd-で対話に使う)
3. [Claude Code の試験を流す](#3-claude-code-の試験を流す)
4. [ほかのエージェントの試験を流す](#4-ほかのエージェントの試験を流す)

## この文書の位置づけ

設定の根拠と試験結果は [Claude Code のツール利用テスト](../01_research/r260929-01-ClaudeCodeのツール利用テスト.md)にある。 本書はその設定を自分で動かすための手順だけを書く。コマンドはすべてプロジェクトのフォルダ（`W:\2026\20260824-local-llm-llama-cp`）で実行する。

## 1. 置き場所

| もの | 場所 | 備考 |
|---|---|---|
| llama-server | `bin\llama.cpp\llama-server.exe` | 一度置いたものを使い続ける。起動のたびにダウンロードはしない（git 管理外） |
| モデル | `C:\AI_Models\<作者>\<名前>-GGUF\` | 起動のたびにディスクから読むだけ。追加の取得は `tools\10_setup\download-models.cmd` |
| 差し替えたテンプレート | `tools\50_run\templates\` | Ministral 2 本・Bonsai・Qwen3.5-9B 用 |
| ルールなしのホーム | `W:\temp\cc1-home`（cc1）<br>`W:\temp\llama-cp-home`（試験） | 無ければ自動で作る |
| 試験の作業用コピー | `W:\temp\llama-cp-sandbox` | 1 問ごとに中身を消して作り直す |
| 試験の記録 | `logs\test-cc-tools\`・`logs\test-agents\` | git 管理外 |

## 2. cc1.cmd で対話に使う

### 手順

1. サーバを起動する。窓が開いたままになり、`listening on http://127.0.0.1:8080` と出れば準備完了 `tools\50_run\run-server-cc.cmd`
2. 別の窓で Claude Code を起動する。**`.\` を付ける**（このPCはカレントフォルダの cmd を名前だけでは探さない） `.\cc1.cmd .\cc1.cmd -p "README.html の h1 を答えて"`
3. 使い終わったら、サーバの窓で Ctrl+C

### モデルを替えるとき

2 か所を同じ名前にそろえる。

- `tools\50_run\run-server-cc.cmd` の `-m`（モデルのファイル）と `--alias`（名前）。3.2 GB 以下のモデルは `-ngl 99` を足す。テンプレートを差し替えるモデルは `--chat-template-file "tools\50_run\templates\<名前>.jinja"` を足す
- `cc1.cmd` の `ANTHROPIC_MODEL` と `ANTHROPIC_SMALL_FAST_MODEL`（`--alias` と同じ値）

> [!TIP]
> **速さで選ぶなら gemma-4-E2B、知識で選ぶなら gpt-oss-20b。** 試験では gemma-4-E2B が読み 13 秒・書き 10 秒、gpt-oss-20b が読み 84 秒・書き 40 秒だった。

## 3. Claude Code の試験を流す

モデルを 1 本ずつ起動し、Claude Code に「README の h1 を読む」「決めた 1 行を書く」の 2 問を投げる。サーバの起動と停止もスクリプトが行う。

### よく使う形

```batch
rem 決めたモデルだけ（名前の一部をカンマ区切り。書いた順に流れる）
tools\50_run\test-cc-tools.cmd -Only "gemma-4-E2B,gpt-oss-20b" -NoRules -UseTemplates -ExtraArgs "--reasoning off" -TimeoutSec 900

rem 20GB 以下の全モデル（小さい順）
tools\50_run\test-cc-tools.cmd -MaxSizeGB 20 -NoRules -UseTemplates -ExtraArgs "--reasoning off" -TimeoutSec 900
```

| 引数 | 意味 |
|---|---|
| `-Only` | 試すモデル。ファイル名の一部をカンマ区切りで書く |
| `-MaxSizeGB` | このサイズ未満を対象にする（既定 10） |
| `-NoRules` | ルールなし（ホームを `W:\temp\llama-cp-home` にする）。**付けないと 1 往復に数分かかる** |
| `-UseTemplates` | 差し替えたテンプレートがあるモデルはそれを使う |
| `-ExtraArgs` | llama-server に足す引数。`"--reasoning off"` で思考を切る |
| `-TimeoutSec` | 1 問を待つ秒数（既定 600） |
| `-Tests` | `read`・`write` のどちらかだけにする（既定は両方） |

### 結果の見方

- 画面に 1 問ごとに `読み: ok 13.4 秒 ターン 2 合格 True` の形で出る
- まとめは `logs\test-cc-tools\<日時>-norules-results.jsonl`（1 モデル 1 行）。1 問ごとの生の出力は `…-raw.json`
- **ターン 1 で合格 False** は、ツールを呼ばずに答えを作ったということ。**ファイルなし**は、作ったと答えても実際にはできていないということ

## 4. ほかのエージェントの試験を流す

Pi・OpenCode・Aider・Codex CLI を、同じ 2 問で試す。各エージェントの設定は `W:\temp\llama-cp-agent-home\` に書き、いつもの設定には触れない。

```batch
tools\50_run\test-agents.cmd -Agent pi -Only "Nemotron,Qwen3-4B-Thinking" -UseTemplates -ExtraArgs "--reasoning off"
tools\50_run\test-agents.cmd -Agent opencode -Only "Nemotron" -UseTemplates -ExtraArgs "--reasoning off"
tools\50_run\test-agents.cmd -Agent aider -Only "Nemotron" -UseTemplates -ExtraArgs "--reasoning off"
tools\50_run\test-agents.cmd -Agent codex -Only "gpt-oss-20b" -UseTemplates -ExtraArgs "--reasoning off"
```

結果は `logs\test-agents\<日時>-<エージェント>-results.jsonl`。質問はコマンド行に載せるため英語にしてある。

> [!WARNING]
> **Codex は安全装置を外して動かす。** Windows では `-s workspace-write` だとファイルの読み書きが止められるため、スクリプトは `--dangerously-bypass-approvals-and-sandbox` を付けている。 モデルは作業用コピーの外にも手を出せる。

## 共通の注意

- **試験は 1 つずつ流す**。どれもポート 8080 を使い、Windows では 2 つのサーバが同じポートを取れてしまうため、結果が混ざる
- **始める前に llama-server が残っていないか確かめる**。残っていれば止める `Get-Process llama-server Stop-Process -Name llama-server`
- RAM を多く使う（20GB 級のモデルでは 16 GB 前後）。ブラウザなどを閉じておくと安定する
- 温度とクロックは `tools\80_ops\watch-thermal.cmd` で 30 秒ごとに `logs\thermal\` へ記録できる

[README](../../README.md)
