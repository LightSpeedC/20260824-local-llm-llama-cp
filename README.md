# ローカルLLM 実行環境

> RTX 3050 Ti Laptop（VRAM 4GB）／RAM 16GB のノートPCで llama.cpp を動かす
> 📅 作成: 2026-08-24 / 更新: 2026-08-25

## プロジェクトの状況

## 1. このプロジェクトについて

手元のノートPCでローカルLLMを常用できる状態にする。 実行基盤は **llama.cpp**、モデルは `C:\AI_Models` にある手持ちのGGUFを流用する方針。

### 現在の段階

| 段階 | 状態 |
| --- | --- |
| 計画 | **✅ 作成済み** 下記の計画書にまとめてある |
| モデルの棚卸し | **✅ 完了** 重複していた 12.6 GB を整理（98.5 → 86.0 GB） |
| llama.cpp の配置 | **✅ 完了** b10612（CUDA 12.4）を `bin\llama.cpp\` に展開 |
| 起動スクリプト | **✅ 完了** `scripts\` に4種類（常用・品質重視・9B・MoE） |
| 速度の実測 | **✅ 完了** 下記のとおり。計画書の第10章に詳細 |
| 品質の評価 | **✅ 完了** 質問セットで Qwen3-4B と E4B を比較。用途による使い分けを確定 |
| Claude Code 接続 | **⬜ 未着手** API 動作は確認済み。接続先を `127.0.0.1:8080` に向け替えるだけ |

### 環境

| 項目 | 内容 |
| --- | --- |
| GPU | NVIDIA GeForce RTX 3050 Ti Laptop（VRAM 4 GB）／ドライバ 592.82 |
| CPU / RAM | Intel Core i7-11370H（4コア8スレッド）／15.8 GB |
| モデル置き場 | `C:\AI_Models`（LM Studio と共用・約 86.0 GB / 26ファイル） |
| 既存ツール | LM Studio 導入済み。Ollama はアンインストール済み |

### 実測した生成速度

| 用途 | モデルと設定 | 速度 |
| --- | --- | --- |
| **✅ 対話・下書き** | **Qwen3-4B-Instruct-2507** `-ngl 99 -c 8192` | 56.5 tok/s |
| **✅ 事実・コード** | **gemma-4-E4B-it** `-ngl 99`（reasoning） | 45.2 tok/s |
| **⚠️ 用途限定** | Qwen3.5-9B `-ngl 24` ＋KV量子化 | 8.1 tok/s |
| **⚠️ 用途限定** | gpt-oss-20b `--n-cpu-moe 18` | 5.9 tok/s |

> [!NOTE]
> **速度で一本化しないこと。** Qwen3-4B は 1〜2秒で返るが、「量子化とは」の説明で**量子力学と混同した誤答**を出した。 日本語が自然なぶん気づきにくい。gemma-4-E4B は思考を経るため10秒前後かかるが、同じ問いに正確に答える。 **対話は 4B、事実確認とコードは E4B** と用途で切り替える。

> [!NOTE]
> **予想外だったのは gemma-4-E4B。** ファイルは 4.95 GiB で 9B クラス扱いだったが、Per-Layer Embeddings の 2730 MiB が CPU 側に分離されるため、 GPU には 2868 MiB しか載らず **4B クラスに近い速度で動く**。 サイズだけで仕分けると取りこぼすモデルがある。詳細は計画書の第10章。

> [!NOTE]
> **VRAM を超えても、エラーではなく「5〜40倍遅くなる」形で現れる。** NVIDIAドライバが共有GPUメモリに逃がすため止まらない。 `-ngl` の付けすぎと、コンテキスト 16384 の指定がこれを起こす。8192 を上限として運用する。

## 2. ドキュメント

### 計画

- [**ローカルLLM 実行計画**](docs/plan/local-llm-plan.md) — ソフトウェア選定（llama.cpp / Ollama / LM Studio）、配布バイナリと自前コンパイルの比較、 手持ちモデルの棚卸し、量子化とVRAM配分、最新量子化とMoEの検討、導入手順、検証計画、**実測結果**

### 調査

- [**Speculative Decoding 調査**](docs/research/speculative-decoding.md) — 小さなドラフトモデルで先読みして生成を速める手法。VRAM 4GB で成立するかの事前検討。 **⬜ 検証は未実施**
- [**HP ZGX Nano G1n 調査**](docs/research/hp-zgx-nano.md) — 128GB 統合メモリの AI ワークステーション。容量と帯域の違い、他の選択肢との比較、判断材料の整理

### フォルダ構成

```text
20260824-local-llm-llama-cp/
├─ README.html              … このファイル
├─ bin/llama.cpp/           … b10612 (CUDA 12.4) 一式
├─ scripts/
│   ├─ run-server.cmd       … 常用 (Qwen3-4B)
│   ├─ run-server-e4b.cmd   … 品質重視 (gemma-4-E4B)
│   ├─ run-server-9b.cmd    … Qwen3.5-9B
│   ├─ run-server-moe.cmd   … gpt-oss-20b (MoE)
│   └─ bench.cmd            … 速度計測
├─ docs/
│   ├─ plan/                … 計画書
│   └─ research/            … 個別テーマの調査
├─ src/scripts/70_html2md/  … HTML→Markdown 変換
├─ etc/                     … 補助スクリプト（git管理外）
└─ tmp/                     … ダウンロードしたzip等（git管理外）

C:\AI_Models\                … GGUF の実体（LM Studio と共用・移動しない）
```

