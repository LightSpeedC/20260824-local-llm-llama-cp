# ローカルLLM 実行環境

RTX 3050 Ti Laptop（VRAM 4GB）／RAM 32GB のノートPCで llama.cpp を動かす

> 📅 作成: 2026-08-24 / 更新: 2026-09-30

[lightspeedc.com](../)

手元のノートPCでローカルLLMを動かすための検討と実測をまとめている。 実行基盤は **llama.cpp**、モデルは `C:\AI-models` にある手持ちの GGUF を使う。 公開ページは [https://lightspeedc.com/20260824-local-llm-llama-cp/](https://lightspeedc.com/20260824-local-llm-llama-cp/) にある。

## 1. 計画

- [ローカルLLM 実行計画](notes/10_plan/p260824-01-ローカルLLM実行計画.md) — ソフトウェアの選定、配布バイナリと自前コンパイルの比較、手持ちモデルの棚卸し、 量子化と VRAM 配分、最新量子化と MoE の検討、導入手順、検証計画、実測結果
- [ローカルLLM で Claude Code を使う・試す手順](notes/10_plan/p260930-01-ClaudeCodeを使う試す手順.md) — llama-server の引数と Claude Code の環境変数、cc1.cmd で対話に使う手順、試験スクリプトでモデルやエージェントを試す手順
- [AI エージェント比較の検証計画](notes/10_plan/p260929-01-AIエージェント比較の検証計画.md) — Claude Code（ルールなし）・Pi・OpenCode・Codex CLI・Aider を同じ試験で比べる
- [初期プログラミングの検証計画](notes/10_plan/p260930-02-初期プログラミングの検証計画.md) — 日本語で「プログラムを書いて実行する」を頼み、書きの試験に合格した 19 本を 4 つのエージェントで総当たりに試す
- [閉域網へ持っていく配布物](notes/10_plan/p261002-01-閉域網へ持っていく配布物.md) — ネットに出られない別の PC（Intel の内蔵 GPU）へ、llama.cpp・Node.js・エージェント・モデル・試験スクリプトをまとめて運ぶ
- [GPU 併用の検証計画](notes/10_plan/p261007-01-GPU併用の検証計画.md) — NVIDIA GPU・Intel GPU・CPU を組み合わせて載せたときに速くなるかを測る
- [画像解析の検証計画](notes/10_plan/p261010-01-画像解析の検証計画.md) — mmproj を持つモデルに文字・表・グラフ・画面の画像を読ませ、正しさと速さを測る
- [HTTP プロキシ作成の検証計画](notes/10_plan/p261010-02-HTTPプロキシ作成の検証計画.md) — Node.js の HTTP プロキシサーバを書かせ、試験側で実際に通信を通して合否を決める
- [新しいモデルの検証計画](notes/10_plan/p261010-03-新しいモデルの検証計画.md) — 新しく取得したモデルで、これまでと同じ試験（読み書き・sum）を流して比べる
- [ツールの更新とモデル選択ツールへの統合](notes/10_plan/p261113-01-ツールの更新とモデル選択ツールへの統合.md) — llama.cpp・node・bun・AI エージェントを最新にし、start-agent をモデルを選べる 1 本のツールにまとめる
- [階層型エージェント構成案](notes/10_plan/p260825-01-階層型エージェント構成案.md) — 大きなモデルで計画し、小さなモデルで実装する構成。VRAM 4GB では複数モデルを同時常駐できないため、 並列スロットで代替する設計

## 2. 調査

- [Speculative Decoding 調査](notes/01_research/r260825-01-投機的デコーディング.md) — 小さなドラフトモデルで先読みして生成を速める手法が、VRAM 4GB で成立するかの検討と実測
- [ハードウェア選定の判断材料](notes/01_research/r260825-02-ハードウェア選定の判断材料.md) — VRAM 4GB の制約をどのハードウェアで解決できるか。HP ZGX・DGX Spark・Mac Studio・RTX 30 / 50 系の容量・帯域・価格の比較
- [ローカルLLM で AI エージェントを使う — 試験結果](notes/01_research/r260929-01-AIエージェントの試験結果.md) — llama-server に繋いだ Claude Code・Pi・OpenCode・Aider・Codex CLI で、20GB 以下のモデルがファイルを読み書きできるかを試した結果と、どのモデル・エージェントを使うか
- [AI エージェント試験の経緯と全実行の記録](notes/01_research/r260930-01-エージェント試験の経緯と全実行の記録.md) — 上の試験の試し方、途中で起きたことと対処、最初の試験（共通ルールあり）の結果、流したすべての試験
- [Claude Code 以外の AI エージェント調査](notes/01_research/p260929-01-ClaudeCode以外のエージェント調査.md) — Pi・OpenCode・Qwen Code・Codex CLI・Aider を llama-server に繋ぐ方法と、最初に送る量の比較
- [AIエージェントの特徴](notes/01_research/i261014-01-AIエージェントの特徴.md) — 試験で見つけた、起動のしかたで結果が変わるエージェントの癖（OpenCode 1.19.0 は環境変数 PWD を見て、書くファイルの置き場を決める）と、その対処

## 3. 課題

- [課題一覧](notes/40_issues/issues.md) — これから解決すること

## 4. ルール

- [ローカルルール](notes/90_rules/local-rules.md) — このプロジェクトでだけ通る決めごと

## 使い方

- [start-agent の使い方](tools/50_run/使い方.md) — cmd から、モデルを選んで llama-server と Claude Code・Pi・OpenCode を起動する

## 環境

| 項目 | 内容 |
|---|---|
| GPU | NVIDIA GeForce RTX 3050 Ti Laptop（VRAM 4 GB） |
| CPU / RAM | Intel Core i7-11370H（4コア8スレッド）／31.8 GB |
| 実行基盤 | llama.cpp（CUDA 12.4 の配布バイナリ） |
| モデル置き場 | `C:\AI-models`（LM Studio と共用） |

## フォルダ構成

```
20260824-local-llm-llama-cp/
├─ README.html              … このファイル
├─ index.html               … README.html への転送（GitHub Pages 用）
├─ AGENTS.md                … ローカルルールの読み込み（AIエージェント用）
├─ cc1.cmd                  … Claude Code を llama-server に繋いで起動する
├─ notes/
│   ├─ 01_research/         … 調査
│   ├─ 10_plan/             … 計画
│   ├─ 40_issues/           … 課題
│   └─ 90_rules/            … ローカルルール
├─ tools/
│   ├─ 10_setup/            … モデルの取得
│   ├─ 50_run/              … llama-server の起動・速度計測・Claude Code の試験
│   └─ 80_ops/              … 温度・クロックの記録
└─ bin/llama.cpp/           … 配布バイナリ（git 管理外）

C:\AI-models\                … GGUF の実体（LM Studio と共用・移動しない）
```

[lightspeedc.com](../)
