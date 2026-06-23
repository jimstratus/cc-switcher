# Known Issues

Unless marked otherwise, entries apply to both the PowerShell module and the
bash port — the two implementations share the catalog and feature set.

## Z.AI GLM-5.2 (`cc-zai-glm51`) — Slow

The Z.AI Anthropic-compatible endpoint (`https://api.z.ai/api/anthropic`) is
China-based; round-trip latency from US is prohibitive for interactive coding.

**Workaround:** Use `cc-glm` (OpenRouter route to `z-ai/glm-5.2`). Same model,
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

## DeepSeek V4 — only two SKUs

Verified 2026-05-01 against `https://api.deepseek.com/v1/models`: only
`deepseek-v4-pro` and `deepseek-v4-flash` are exposed. There's no plain
`deepseek-v4`. The catalog points both Opus and Sonnet at `deepseek-v4-pro`;
Haiku at `deepseek-v4-flash`.

If DeepSeek ships a middle-tier model later, edit `data\providers.json`
to remap Sonnet.

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
| `cc-nemotron` (Nemotron 3 Super, free) | yes | 1M (uniform across tiers) |
| `cc-owl` (Owl Alpha, free) | yes | 1M (uniform across tiers) |
| `cc-deepseek` (V4 Pro) | yes | 1M (uniform across tiers) |
| `cc-glm`, `cc-zai-glm51` (GLM-5.2) | yes | 1M |
| `cc-gemini` (Gemini 3.1 Pro) | yes | 1M |
| `cc-minimax`, `cc-minimax-or` (MiniMax M3) | yes | 1M |
| `cc-qwen` (Qwen3.7 Max on OpenRouter) | yes | 1M (flagship only) |
| `cc-ollama-glm` (GLM-5.2, Ollama Cloud) | yes | 976K |
| `cc-ollama-minimax` (MiniMax M3, Ollama Cloud) | yes | 512K |
| `cc-kimi` (K2.7 Code) | no | 256K (below the 500K threshold) |
| `cc-opencode-minimax` | no | ~205K (OpenCode Go cap unverified) |
| `cc-codex` | no | 200K |
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
`cc-glm` (OpenRouter) covers GLM-5.2 with US/EU latency and no local proxy.

The local Python proxy at `<your-tools-path>\claude-code-proxy` is now
orphaned.

If format translation is ever needed again, prefer the upstream
`free-claude-code` project — broader provider support, actively maintained.

---

## Untested commands

These commands exist in the catalog but haven't been launched end-to-end. Run
`cc-doctor` for a quick reachability check before relying on any:

- `cc-codex` (OAuth flow not exercised)
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

## Owl Alpha — intermittent at peak times

Owl Alpha (`cc-owl`, `openrouter/owl-alpha`) is a FREE cloaked model on
OpenRouter's Stealth provider. Direct API testing (2026-05-26) confirms:

- Anthropic Messages API: working (200 OK, proper format)
- Tool calling: working (correct `tool_use` blocks)
- Full agent loop (tool_use → tool_result → answer): working
- 8-tool complex schema: working

However, the model can fail intermittently due to free-tier rate limits and
provider load. Usage log shows both successful (24-turn May 17, 739-turn
May 26) and failed (0-turn May 3) sessions.

**Workaround:** Retry if first launch errors. If it consistently fails,
switch to a paid provider like `cc-mimo` or `cc-deepseek` for the session.

**Privacy note:** Prompts and completions may be logged by the Stealth
provider for model improvement.
