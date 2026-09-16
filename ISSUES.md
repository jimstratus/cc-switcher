# Known Issues

Unless marked otherwise, entries apply to both the PowerShell module and the
bash port — the two implementations share the catalog and feature set.

## OpenAI Codex direct OAuth — intentionally disabled

`cc-codex` cannot be implemented as a direct Claude Code provider with a ChatGPT subscription. Codex device login issues a ChatGPT OAuth token that is not accepted by OpenAI's public API, and the public API does not implement the Anthropic Messages protocol Claude Code requires.

**Supported alternatives:** use `codex login --device-auth` with the native Codex CLI, or set `OPENROUTER_API_KEY` and run `cc-openrouter openai/gpt-5.4` from Claude Code. The latter is gateway-billed; it does not consume a ChatGPT subscription.

`cc-codex` and `cc-codex-login` are retained as explicit migration guards. `cc-codex-logout` removes the legacy token cache.

---

## Z.AI GLM-5.3 (`cc-zai-glm51`) — Slow

The Z.AI Anthropic-compatible endpoint (`https://api.z.ai/api/anthropic`) is
China-based; round-trip latency from US is prohibitive for interactive coding.

**Workaround:** Use `cc-glm` (OpenRouter route to `z-ai/glm-5.3`). Same model,
US/EU latency.

This command is kept and tagged `[SLOW]` so it sorts last in `cc-launch` and
`cc-help`.

---

## NVIDIA NIM tier defaults — best guess

The default tier IDs in `data\providers.json` for `cc-nvidia` are educated
guesses — NVIDIA NIM rotates models frequently. If a tier returns 404 / 400,
edit `providers.json` to a model id from
[build.nvidia.com/explore/discover](https://build.nvidia.com/explore/discover).

`cc-nvidia <model>` overrides all three tiers in one shot.

---

## DeepSeek V4.1 Flash — canonical identifier

Verified 2026-09-16 against `https://api.deepseek.com/v1/models`: the live
identifiers are `deepseek-flash` and `deepseek-v4-pro`. `deepseek-flash` is
DeepSeek V4.1 Flash; the retired `deepseek-v4-flash` identifier is temporarily
routed for compatibility. The catalog maps all tiers to `deepseek-flash`.

When DeepSeek releases V4.1 Pro, review the tier mapping rather than assuming
the previous V4 Pro identifier has become the new flagship.

---

## Context window display for 1M-context models

Claude Code defaults to a **200K context** display for any model ID it doesn't
recognize, and the fix requires two env vars set together: `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
plus `DISABLE_COMPACT=1` (`MAX_CONTEXT_TOKENS` only takes effect when
`DISABLE_COMPACT` is also set, per Claude Code's docs).

**`cc-switcher` auto-derives both env vars** when a provider's flagship-tier
context is `>= 500000`. No catalog edit required for these:

| Provider | Auto-applied? | Flagship context |
|---|:---:|---|
| `cc-grok` (Grok 4.20) | yes | 2M |
| `cc-mimo` (MiMo V2.5-Pro on OpenRouter) | yes | 1M (flagship/standard; fast tier 256K) |
| `cc-xiaomi` (MiMo V2.5-Pro direct SGP) | yes | 1M (flagship only) |
| `cc-nemotron` (Nemotron 3 Ultra, free) | yes | 1M (uniform across tiers) |
| `cc-owl` (LongCat 2.0, OpenRouter) | yes | ~1M (Owl Alpha's public successor; paid) |
| `cc-deepseek` (V4.1 Flash) | yes | 1M (uniform across tiers) |
| `cc-glm` (GLM-5.3) | yes | 1.31M |
| `cc-zai-glm51` (GLM-5.3, direct) | yes | 1M (conservative) |
| `cc-gemini` (Gemini 3.1 Pro) | yes | 1M |
| `cc-minimax`, `cc-minimax-or` (MiniMax M3) | yes | 1M |
| `cc-qwen` (Qwen3.8 Max / 27B / Flash on OpenRouter) | yes | 1M (all tiers) |
| `cc-ollama-glm` (GLM-5.3, Ollama Cloud) | yes | 1M |
| `cc-ollama-minimax` (MiniMax M3, Ollama Cloud) | yes | 512K |
| `cc-kimi` (Kimi K3) | yes | 1M |
| `cc-opencode-minimax` | no | ~205K (OpenCode Go cap unverified) |
| `cc-codex` | n/a | disabled (incompatible auth + wire protocol) |
| `cc-nvidia` | no | 128K |

See [`docs/architecture.md`](docs/architecture.md#auto-context-derivation) for
the threshold rationale. To opt in a sub-500K provider explicitly, add an
`envVars` block to its catalog entry:

```json
"envVars": {
  "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "256000",
  "DISABLE_COMPACT": "1"
}
```

**Tradeoff for any 1M-display provider:** `DISABLE_COMPACT=1` disables Claude
Code's auto-compaction safety net. Run `/compact` manually as you approach the
real ceiling. On a 1M window the ceiling is 5× further than the old 200K, so
this is a mild trade — but real.

**Per-tier caveat:** the env var is session-scoped, so once `cc-mimo` (flagship 1M /
fast 256K) launches with `MAX_CONTEXT_TOKENS=1048576`, switching to `/model haiku`
will display 1M but the v2-flash API endpoint will reject prompts beyond 256K.
Acceptable for opus-primary workflows.

---

## OpenCode Go GLM removed

`cc-opencode-glm51` and `cc-opencode-glm5t` were removed in 3.0.0 because
`cc-glm` (OpenRouter) covers GLM-5.3 with US/EU latency and no local proxy.

The local Python proxy at `<your-tools-path>\claude-code-proxy` is now
orphaned.

If format translation is ever needed again, prefer the upstream
`free-claude-code` project — broader provider support, actively maintained.

---

## Untested commands

These commands exist in the catalog but haven't been launched end-to-end. Run
`cc-doctor` for a quick reachability check before relying on any:

- `cc-kimi` (OpenRouter only — no direct Moonshot account)
- `cc-qwen` (OpenRouter only — no direct DashScope account)
- `cc-nvidia` (depends on NVIDIA_API_KEY being valid)

---

## `Out-ConsoleGridView` for `cc-pick` (PowerShell only)

`cc-pick` requires `Microsoft.PowerShell.ConsoleGuiTools`. Install with:

```powershell
Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
```

Without it, `cc-pick` falls back to `cc-launch` (numbered menu). The bash port
has no `cc-pick` — use `cc-launch`.

---

## Bash port: env restore is best-effort on interrupt

The PowerShell module restores the environment in a `try/finally`. The bash
port restores after `claude` returns on the normal path; a `Ctrl+C` that kills
the launching *function* itself (rare — `claude` normally receives the signal)
can skip restore. If `cc-status` shows a provider URL after a session ended,
run `cc-reset`.

---

## `cc-owl`: LongCat 2.0 successor and pricing

OpenRouter retired the Owl Alpha stealth listing. `cc-owl` now retains that
familiar command name while launching `meituan/longcat-2.0`, Meituan's public
LongCat 2.0 release, through OpenRouter.

This is a paid route, not a free stealth model. At the 2026-09-16 audit,
OpenRouter listed $0.30 per million input tokens and $1.20 per million output
tokens; gateway pricing can change. The registry reports a roughly 1.05M-token
window. A forced Anthropic Messages tool-use request succeeded on that date.

LongCat 2.0 is text-only. Use a separate provider when image or audio input
is required.
