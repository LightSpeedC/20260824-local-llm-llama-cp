# ローカルLLM 実行環境

RTX 3050 Ti Laptop（VRAM 4GB）／RAM 16GB のノートPCで llama.cpp を動かす

> 📅 作成: 2026-08-24 / 更新: 2026-09-27

[lightspeedc.com](../)

手元のノートPCでローカルLLMを動かすための検討と実測をまとめている。 実行基盤は **llama.cpp**、モデルは `C:\AI_Models` にある手持ちの GGUF を使う。 公開ページは [https://lightspeedc.com/20260824-local-llm-llama-cp/](https://lightspeedc.com/20260824-local-llm-llama-cp/) にある。

## 1. 計画

- [ローカルLLM 実行計画](notes/10_plan/p260824-01-ローカルLLM実行計画.md) — ソフトウェアの選定、配布バイナリと自前コンパイルの比較、手持ちモデルの棚卸し、 量子化と VRAM 配分、最新量子化と MoE の検討、導入手順、検証計画、実測結果
- [階層型エージェント構成案](notes/10_plan/p260825-01-階層型エージェント構成案.md) — 大きなモデルで計画し、小さなモデルで実装する構成。VRAM 4GB では複数モデルを同時常駐できないため、 並列スロットで代替する設計

## 2. 調査

- [Speculative Decoding 調査](notes/01_research/r260825-01-投機的デコーディング.md) — 小さなドラフトモデルで先読みして生成を速める手法が、VRAM 4GB で成立するかの事前検討
- [HP ZGX Nano G1n 調査](notes/01_research/r260825-02-HP-ZGX-Nano-G1n.md) — 128GB 統合メモリの AI ワークステーション。容量と帯域の違い、他の選択肢との比較、判断材料の整理

## 3. 課題

- [課題一覧](notes/40_issues/issues.md) — これから解決すること

## 環境

| 項目 | 内容 |
|---|---|
| GPU | NVIDIA GeForce RTX 3050 Ti Laptop（VRAM 4 GB） |
| CPU / RAM | Intel Core i7-11370H（4コア8スレッド）／15.8 GB |
| 実行基盤 | llama.cpp（CUDA 12.4 の配布バイナリ） |
| モデル置き場 | `C:\AI_Models`（LM Studio と共用） |

## フォルダ構成

```
20260824-local-llm-llama-cp/
├─ README.html              … このファイル
├─ index.html               … README.html への転送（GitHub Pages 用）
├─ cc1.cmd                  … Claude Code を llama-server に繋いで起動する
├─ notes/
│   ├─ 01_research/         … 調査
│   ├─ 10_plan/             … 計画
│   └─ 40_issues/           … 課題
├─ tools/50_run/            … llama-server の起動（Claude Code 向けを含む）・速度計測
└─ bin/llama.cpp/           … 配布バイナリ（git 管理外）

C:\AI_Models\                … GGUF の実体（LM Studio と共用・移動しない）
```

[lightspeedc.com](../)
