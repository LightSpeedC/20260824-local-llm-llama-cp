# Claude Code 以外の AI エージェント調査

llama-server に繋いで使えそうなコーディングエージェントを洗い出す。計画 p260929-01 の事前調査

> 📅 作成: 2026-09-29 / 更新: 2026-09-29

[README](../../README.md)

## 目次

1. [なぜ別のエージェントを見るか](#1-なぜ別のエージェントを見るか)
2. [候補](#2-候補)
3. [計画への提案](#3-計画への提案)

## この文書の位置づけ

[Claude Code のツール利用テスト](r260929-01-ClaudeCodeのツール利用テスト.md)では、どのモデルも最初の要求を読み込むだけで 140〜180 秒かかり、実用にならなかった。 本書は、これから立てる計画 **p260929-01**（Claude Code 以外のエージェントの検証）のための事前調査である。 ここに書く各ツールの性質は記事・公式資料によるもので、**このPCではまだ1つも試していない**。

## 1. なぜ別のエージェントを見るか

このPCでは、プロンプトの読み込みが 300〜1,250 tok/s しか出ない（深くなるほど落ちる）。 **最初に送る量がそのまま待ち時間になる**ため、エージェントの選び方で結果が大きく変わる。

| エージェント | 最初に送る量 | 出典 |
|---|---:|---|
| Claude Code（このPC・実測） | 約 60,000 | 試験の記録。共通ルール（CLAUDE.md）・メモリの注入を含む |
| Claude Code（記事） | 約 33,000 | 指示ファイルなしの素の状態。道具の定義だけで 14,000〜17,000 |
| OpenCode（記事） | 約 7,000 | 同じ測り方で Claude Code の約 1/5 |
| Pi（記事） | 1,000 未満 | 道具 4 つ（read・write・edit・bash）と 150 語ほどの指示 |

このPCの 60,000 のうち、記事の素の状態との差（約 27,000）は、利用者の共通ルールとメモリの分と考えられる。 **Claude Code のままでも、それらを読ませない起動方法があれば半分以下になる可能性がある**（未確認）。

## 2. 候補

いずれも OpenAI 互換の `/v1/chat/completions`（Codex は `/v1/responses`）で llama-server に繋ぐ。手元には node 26・bun 1.4・npm があり、どれも入れられる見込み。

| エージェント | 形 | 繋ぎ方 | このPCで見込める点 |
|---|---|---|---|
| **Pi** | CLI | `~/.pi/agent/models.json` に baseUrl とモデルを書く | ✅ **本命** 最初に送る量が最小。gemma-4 系と組み合わせた記事がある |
| **OpenCode** | CLI | `opencode.json` に provider（baseURL）を書く | ✅ **本命** 送る量が Claude Code の約 1/5。要求の先頭を毎回同じに保つためキャッシュが効きやすいとされる |
| Qwen Code | CLI | modelProviders に baseUrl・contextWindowSize・envKey を書く（envKey を省くと認証エラー） | ⚠ **候補** Qwen3-Coder 向け。Gemini CLI 由来で送る量は多めの見込み（未確認） |
| Codex CLI | CLI | `%USERPROFILE%\.codex\config.toml` の `[model_providers.*]`、または `--oss` | ⚠ **候補** gpt-oss-20b との組み合わせ例が多い。llama-server が Responses API に応じるかは要確認 |
| Aider | CLI | LiteLLM 経由で `openai/` 接頭辞のモデル名を使う | ⚠ **候補** 道具呼び出しでなく差分の書式で編集するため、道具呼び出しが弱いモデルでも動く可能性。Python が要る |
| Claude Code（軽量起動） | CLI | いまと同じ。共通ルール・メモリ・MCP を読ませない起動方法を探す | ⚠ **候補** 送る量を減らせれば、今回の試験結果が変わる可能性 |

> [!IMPORTANT]
> **Aider は Python が要る。** 共通ルールでは Python を使わないことにしているため、入れるかどうかは利用者の判断が要る。

## 3. 計画への提案

1. **同じ試験で比べる**。Claude Code の試験と同じ「README の h1 を読む」「決めた1行を書く」で、最初の応答までの時間・ターン数・合否を測る
2. **順番は送る量の少ない順**。Pi → OpenCode → Claude Code（軽量起動） → Qwen Code → Codex CLI
3. **モデルは Claude Code の試験で道具を呼べたものから選ぶ**。書きに合格した gemma-4-E2B・E4B・Qwen3-4B-Instruct など
4. **入れ方は利用者の範囲に閉じる**。npm のグローバル導入か、プロジェクト配下（`tools/` 以下の git 管理外）かを計画で決める

## 参考資料

- [Claude Code Sends 33k Tokens Before Your Prompt - OpenCode Sends 7k](https://www.developersdigest.tech/blog/claude-code-token-overhead-opencode-comparison) — 送る量の比較
- [Pi: a coding agent with efficient system prompting](https://www.tensorlake.ai/blog/pi-coding-agent-efficient-system-prompting) — Pi の指示の大きさ
- [How to run a local coding agent with Gemma 4 and Pi](https://patloeber.com/gemma-4-pi-agent/) — Pi をローカルサーバに繋ぐ手順
- [Using OpenCode with llama.cpp](https://www.mykolaaleksandrov.dev/posts/2026/07/blog-opencode-llamacpp/) — OpenCode の設定
- [Connect Qwen Code to a Local llama.cpp Server](https://carteakey.dev/snippets/qwen-code-local-llama-cpp.html) — Qwen Code の設定
- [How to Run Local LLMs with OpenAI Codex](https://unsloth.ai/docs/basics/codex) — Codex CLI の設定
- [Tutorial: Offline Agentic coding with llama-server](https://github.com/ggml-org/llama.cpp/discussions/14758) — llama-server で使うエージェントの例

[README](../../README.md)
