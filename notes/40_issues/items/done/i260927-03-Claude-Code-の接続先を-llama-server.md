---
schema: 1
id: i260927-03
title: Claude Code の接続先を llama-server へ切り替える
group: 運用
created: 2026-09-27
---

これまで LM Studio に向けていた接続先を、llama-server（`127.0.0.1:8080`）へ切り替える。 llama-server は Anthropic 形式の `/v1/messages` に直接応答するため、変換の層を挟まずに繋がる。

Claude Code は最初の要求だけで約 63,000 トークンある。VRAM 4GB には KV キャッシュが載らないため、 コンテキスト 65536・KV キャッシュを RAM 側（`-nkvo`）・q8_0 で起動する。 初回は 157 秒かかるが、2回目以降は共通部分が再利用されて 14 秒になる。

- [済] llama-server が Anthropic 形式に直接応答することを確かめる
- [済] サーバの起動（`tools/50_run/run-server-cc.cmd`）と Claude Code の起動（root の `cc1.cmd`）をスクリプトにする
- [済] Claude Code から応答が返ることを確かめる

関連: [ローカルLLM 実行計画](../../../10_plan/p260824-01-ローカルLLM実行計画.md)（導入手順の Step 5）
