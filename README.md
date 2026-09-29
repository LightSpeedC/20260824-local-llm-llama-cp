# ローカルLLM 実行環境

RTX 3050 Ti Laptop（VRAM 4GB）／RAM 32GB のノートPCで llama.cpp を動かす

> 📅 作成: 2026-08-24 / 更新: 2026-09-30

[lightspeedc.com](../)

手元のノートPCでローカルLLMを動かすための検討と実測をまとめている。 実行基盤は **llama.cpp**、モデルは `C:\AI_Models` にある手持ちの GGUF を使う。 公開ページは [https://lightspeedc.com/20260824-local-llm-llama-cp/](https://lightspeedc.com/20260824-local-llm-llama-cp/) にある。

## 1. 計画

- [ローカルLLM 実行計画](notes/10_plan/p260824-01-ローカルLLM実行計画.md) — ソフトウェアの選定、配布バイナリと自前コンパイルの比較、手持ちモデルの棚卸し、 量子化と VRAM 配分、最新量子化と MoE の検討、導入手順、検証計画、実測結果
- [ローカルLLM で Claude Code を使う・試す手順](notes/10_plan/p260930-01-ClaudeCodeを使う試す手順.md) — llama-server の引数と Claude Code の環境変数、cc1.cmd で対話に使う手順、試験スクリプトでモデルやエージェントを試す手順
- [AI エージェント比較の検証計画](notes/10_plan/p260929-01-AIエージェント比較の検証計画.md) — Claude Code（ルールなし）・Pi・OpenCode・Codex CLI・Aider を同じ試験で比べる
- [階層型エージェント構成案](notes/10_plan/p260825-01-階層型エージェント構成案.md) — 大きなモデルで計画し、小さなモデルで実装する構成。VRAM 4GB では複数モデルを同時常駐できないため、 並列スロットで代替する設計

## 2. 調査

- [Speculative Decoding 調査](notes/01_research/r260825-01-投機的デコーディング.md) — 小さなドラフトモデルで先読みして生成を速める手法が、VRAM 4GB で成立するかの検討と実測
- [ハードウェア選定の判断材料](notes/01_research/r260825-02-ハードウェア選定の判断材料.md) — VRAM 4GB の制約をどのハードウェアで解決できるか。HP ZGX・DGX Spark・Mac Studio・RTX 30 / 50 系の容量・帯域・価格の比較
- [ローカルLLM で AI エージェントを使う — 試験結果](notes/01_research/r260929-01-AIエージェントの試験結果.md) — llama-server に繋いだ Claude Code・Pi・OpenCode・Aider・Codex CLI で、20GB 以下のモデルがファイルを読み書きできるかを試した結果と、どのモデル・エージェントを使うか
- [AI エージェント試験の経緯と全実行の記録](notes/01_research/r260930-01-エージェント試験の経緯と全実行の記録.md) — 上の試験の試し方、途中で起きたことと対処、最初の試験（共通ルールあり）の結果、流したすべての試験
- [Claude Code 以外の AI エージェント調査](notes/01_research/p260929-01-ClaudeCode以外のエージェント調査.md) — Pi・OpenCode・Qwen Code・Codex CLI・Aider を llama-server に繋ぐ方法と、最初に送る量の比較

## 3. 課題

- [課題一覧](notes/40_issues/issues.md) — これから解決すること

## 4. ルール

- [ローカルルール](notes/90_rules/local-rules.md) — このプロジェクトでだけ通る決めごと

## 環境

| 項目 | 内容 |
|---|---|
| GPU | NVIDIA GeForce RTX 3050 Ti Laptop（VRAM 4 GB） |
| CPU / RAM | Intel Core i7-11370H（4コア8スレッド）／31.8 GB |
| 実行基盤 | llama.cpp（CUDA 12.4 の配布バイナリ） |
| モデル置き場 | `C:\AI_Models`（LM Studio と共用） |

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

C:\AI_Models\                … GGUF の実体（LM Studio と共用・移動しない）
```

[lightspeedc.com](../)
