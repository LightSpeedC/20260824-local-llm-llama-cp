---
schema: 1
id: i260927-02
title: Speculative Decoding の検証
group: 検証
created: 2026-09-27
---

小さなドラフトモデルで先読みして生成を速める手法。本命とドラフトを同居させると VRAM の余裕は約 200 MiB と見積もっており、 帯域を使い切っている本PCでは効果が出ない可能性もある。

- [済] 使用中のビルドの `llama-server --help` で、ドラフトモデル指定のオプション名を確かめる（`-md` のほかに `--spec-type draft-simple` が要る。`--draft-max` は `--spec-draft-n-max` に替わった）
- [済] 本命と同系列のドラフトモデル（Qwen3-0.6B の GGUF）を取得する（unsloth の Q4_K_M・397 MB）
- [済] 調査の検証計画にある5構成を測り、結果を調査に反映する（どの構成も単体の 57 tok/s より遅く 29〜47 tok/s。見送る。`tools\50_run\bench-spec.cmd`）

関連: [Speculative Decoding 調査](../../../01_research/r260825-01-投機的デコーディング.md)
