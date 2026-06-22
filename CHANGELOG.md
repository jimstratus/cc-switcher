# Changelog

## Unreleased

## 3.3.0 — 2026-06-21

### Added — 2026-06 model refresh (1M-context wave)

- **GLM-5.2** (1M): `cc-glm` bumped GLM-5.1→5.2 (fast tier GLM-4.7-Flash);
  `cc-zai-glm51` (Z.AI direct) → `glm-5.2[1m]` / `glm-4.7`, now 1M.
- **MiniMax M3** (1M): `cc-minimax` (direct) M2.7→M3; new `cc-minimax-or`
  (OpenRouter, US-latency) and `cc-ollama-minimax` (Ollama Cloud);
  `cc-opencode-minimax` → `minimax-m3`. The direct `/anthropic` endpoint
  self-reports ~200K (upstream bug) so `context` is pinned to 1M to drive
  the extended window.
- **Qwen3.7 Max** (1M flagship): `cc-qwen` flagship `qwen3.6-plus`→`qwen3.7-max`.
- **New providers:** `cc-gemini` (Gemini 3.1 Pro, 1M), `cc-grok` (Grok 4.20,
  **2M** — largest window in the catalog), `cc-ollama-glm` / `cc-ollama-minimax`
  (Ollama Cloud, Anthropic-compatible at `https://ollama.com`, `:cloud` suffix,
  auth `OLLAMA_API_KEY`).
- **Kimi K2.7 Code:** `cc-kimi` bumped K2.6→`kimi-k2.7-code` but **stays 256K**
  — K2.7 ships only as "Code" and did not widen the window. Not 1M.
- **Bash `cc-nemotron` / `cc-owl` functions** — these providers shipped in the
  v3.2.0 PowerShell catalog and were synced into the bash catalog when the port
  merged, but their bash command functions were missing (menu showed "No handler").
- `OLLAMA_API_KEY` added to the `cc-status` / `cc-doctor` key list.
- Note: GLM-5.2 is intentionally **not** offered via OpenCode Go — that surface
  serves GLM over an OpenAI-only API, incompatible with this tool. Use
  `cc-glm` (OpenRouter), `cc-zai-glm51`, or `cc-ollama-glm` instead.

### Fixed — cross-platform + Codex (PR #1 review follow-up)

- **macOS/BSD portability:** portable `_cc_mtime` / `_cc_fmt_ts` helpers replace
  GNU-only `stat -c %Y` and `date -d`; `cc-doctor` latency now uses curl's
  `%{time_total}` instead of `date +%s%3N`.
- **Codex token expiry:** `cc-codex-login` now derives an absolute `expires_at`
  from the OAuth `expires_in`, so a freshly minted token is no longer treated as
  expired by `get_cc_codex_token`.
- Catalog notes reference `core.ps1/core.sh` (was PowerShell-only `core.ps1`).

### Added

- **bash/zsh port** (`bash/`) — full Linux/macOS implementation of the
  module: all `cc-*` provider commands, `cc-launch` menu, `cc-doctor`,
  `cc-pricing`, `cc-status`, `cc-usage` (JSONL + SQLite), Codex OAuth
  device flow, tab completion, and a Makefile installer (user and
  system-wide). Sourced from `~/.bashrc`; shares the catalog format with
  the PowerShell module via a synchronized copy at
  `bash/data/providers.json`.
- **CI** (`.github/workflows/ci.yml`) — bash syntax + ShellCheck, a
  sourced-module smoke test against a stubbed `claude`, install-layout
  verification, catalog validation and cross-copy sync check, and a
  PowerShell parse/manifest check.

### Fixed (bash port code review — issues #2–#14)

- Provider lookup returned from a pipeline subshell, so **every catalog
  command failed** with "Unknown provider id" (#2).
- `set -euo pipefail` in sourced files leaked errexit/nounset/pipefail
  into the user's interactive shell and could skip env restore when
  `claude` exited nonzero (#3).
- `make install` flattened `lib/` and `data/` so the installed module
  never loaded (#4).
- `cc-openrouter` was documented but never defined (#5).
- Catalog `envVars` were exported permanently via `eval` and applied
  before (not after) the auto-context block (#6).
- Tab completion was never registered; `COMP_CWORDS` typo (#7).
- `cc-nvidia` crashed with no args and ignored catalog edits (#8).
- Codex OAuth token cache was world-readable; tokens without
  `expires_at` were treated as valid (#9).
- Session-end token aggregation crashed on empty file lists and on the
  first turn increment; ~5 jq forks per transcript line (#10).
- ~180 jq subprocess forks per launch / per catalog listing (#11);
  managed env-var lists deduplicated (#12); menu dispatch made
  catalog-driven (#13); README diagram `+model` → `/model` (#14).

### Docs

- `docs/architecture.md`: new "The bash port" section — file/function
  mapping, launch-lifecycle sequence diagram, behavioral deltas.
- `AGENTS.md`, `docs/catalog-schema.md`, `docs/adding-a-provider.md`,
  `CONTRIBUTING.md`: dual-implementation invariants (catalog sync,
  sourced-file constraints, five version markers), bash verification
  recipes, CI documentation.
- `README.md`: CI badge, flagship context-window chart, `jq` listed as
  a required bash dependency.

## 3.2.0 — 2026-05-26

### Added

- **Owl Alpha (`cc-owl`):** FREE cloaked 1M-context alpha model via OpenRouter
  Stealth provider. Agentic-optimized, tool calling verified working through
  the Anthropic Messages API. May be intermittent at peak times due to
  free-tier demand; retry if first launch errors. Best for exploratory
  sessions.
- **NVIDIA Nemotron 3 Super (`cc-nemotron`):** FREE 1M-context 120B hybrid MoE
  (Mamba+Transformer, 12B active) via OpenRouter. 50%+ faster than
  transformer-only models. Good for multi-agent and cross-document reasoning.
- **Menu reference section:** `cc-launch` now displays a "Recommended OpenRouter
  Models" section below the numbered provider list, showing free and paid
  1M-context model IDs usable with the `[O] Custom OpenRouter model` option.
  Covers owl-alpha, nemotron, lyria-3, llama-4-scout (10M ctx), qwen3.6-flash,
  claude-sonnet-4.6, and grok-4.20.
- **Install point fix:** Restored `C:\Users\ryanm\ClaudeCodeProviders.ps1` as a
  wrapper that loads the module from `d:\projects\scripts\cc-switcher`.

### Provider catalog (`data/providers.json` v3.2.0)

- New entries: `owl-alpha` (free, cc-owl), `nemotron` (free, cc-nemotron)
- Both are 1M uniform-context, auto-derive `CLAUDE_CODE_MAX_CONTEXT_TOKENS`

### Owl Alpha diagnosis

- Full Anthropic Messages API test suite passed: basic text, single tool call,
  full agent loop (tool_use → tool_result → final answer), and 8-tool complex
  schema all returned 200 with correct Anthropic-format responses.
- Usage log shows successful sessions: 24-turn (May 17) and 739-turn (May 26).
- Root cause of intermittent failures: free cloaked model on Stealth provider
  is subject to rate limiting and provider load. Not a compatibility issue.
- Docs at https://openrouter.ai/openrouter/owl-alpha claim Claude Code support
  — confirmed working.

### Changed

- Module version bumped 3.1.0 → 3.2.0.
- All docs (README, AGENTS.md, ISSUES.md, architecture.md, catalog-schema.md,
  adding-a-provider.md) updated for version and new providers.

## 3.1.0 — 2026-05-09

### Added (auto-context for 1M-class flagships)

- **`Invoke-CCLaunch` now auto-derives `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  and `DISABLE_COMPACT=1`** from the catalog's flagship-tier context
  whenever it is `>= 500000`. Removes the manual envVars boilerplate
  per provider and ensures `/model opus` actually exposes the model's
  full context to Claude Code's status bar (no more 200K display
  default for 1M-capable providers).
- **Threshold rationale (500K):** cleanly separates 1M-class
  providers (DeepSeek, MiMo, Qwen, Xiaomi v2.5-pro) from sub-256K
  models where losing auto-compact would not be worth the modest
  context bump. To opt in a sub-500K provider explicitly, set the
  envVars in its catalog block — `ExtraEnv` applies after the
  auto-block.
- **New `Invoke-CCLaunch` parameter:** `-FlagshipContext <int>`
  (passed through automatically by `Invoke-CCProvider`).
- **Provider catalog updates (`data/providers.json` v3.1.0):**
  - Removed redundant `envVars` from `deepseek` (auto-derive handles it).
  - `xiaomi` (direct SGP): added `contextByTier.flagship: 1048576`
    after Ryan confirmed v2.5-pro is 1M on the direct gateway.
    standard/fast left at 256K conservatively until verified.
  - Updated notes on `mimo`, `qwen`, `deepseek` to reference
    `_doc._auto_context` instead of repeating the env-var contract.

### Changed

- **`CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `DISABLE_COMPACT` are now
  snapshotted by `Invoke-CCLaunch`** so they get fully restored on
  exit — fixes a small leak where these would persist across cc-*
  switches when set manually via envVars.
- Module version bumped 3.0.3 → 3.1.0.

### Added (public release scaffolding)

- `LICENSE` (MIT) — copyright Ryan Mander, 2025-2026.
- `CONTRIBUTING.md` — short contributor guide (issue/PR conventions,
  how to add a provider via JSON, `cc-doctor` health-check loop).
- `.gitignore` — covers runtime caches (`data/.pricing-cache.json`,
  `data/.usage-log.jsonl`, `data/.last-load`), logs, OS detritus,
  editor cruft, build artifacts, and `.env*`.
- Public-quality `README.md` rewrite with ASCII banner, architecture
  mermaid diagram, full provider table (incl. `cc-xiaomi`),
  configuration env-var block, repo-layout tree, requirements,
  versioning section, and a "first public cut" note pointing at this
  CHANGELOG for prior history.
- `cc-switcher.psd1` gained `ProjectUri` and `LicenseUri` pointing at
  `github.com/jimstratus/cc-switcher`.

### Fixed

- `cc-status` now reports `XIAOMI_API_KEY` presence alongside the other
  provider keys (it was already being checked by `cc-doctor` but missing
  from the `Get-CC-Status` keys block).
- Stale path in `cc-usage` documentation: the scanner recursively walks
  `~/.claude/projects/**/*.jsonl`, not the older `~/.claude/projects/*/sessions/*.jsonl`
  pattern. README and CHANGELOG corrected.

### Changed (publication hygiene)

- Swept residual `C:\Users\ryanm\...` and `D:\projects\...` username
  paths out of `CHANGELOG.md` (4 occurrences), `ISSUES.md` (1), and
  the `cc-switcher.psm1` header — replaced with neutral
  `<your-modules-path>` / `<your-tools-path>` placeholders.
- Removed broken cross-repo link to `D:\repos\free-claude-code` from
  `ISSUES.md`; replaced with plain-text reference.
- Deleted `backup/opencode-glm.ps1` — dead code already documented in
  3.0.0 *Removed* section. The empty `backup/` directory is gone too.

## 3.0.3 — 2026-05-03

### Changed (catalog readability)

- **Catalog tier slot names renamed** for semantic clarity:
  - `tiers.opus` → `tiers.flagship`
  - `tiers.sonnet` → `tiers.standard`
  - `tiers.haiku` → `tiers.fast`
  - Same rename in `contextByTier` for MiMo and Qwen
- The new names are translated to Claude Code's wire-protocol slot names
  (opus / sonnet / haiku) inside `lib/providers.ps1`'s dispatcher — so
  `/model opus|sonnet|haiku` inside a session still works exactly the same.
- **Mapping reference** (now documented in `data/providers.json` under `_doc`):
  ```
  flagship → /model opus
  standard → /model sonnet
  fast     → /model haiku
  ```
- Catalog notes updated to use the new tier names so they read consistently.

### Why

Some providers (Qwen, MiMo, MiniMax) don't have anything called "opus" or
"sonnet" — those names are Claude-Code-internal slots. The catalog was
mixing protocol names with model concepts, which was confusing. New names
describe the role within the provider's lineup ("which is the flagship?")
rather than borrowing Anthropic's product names.

## 3.0.2 — 2026-05-03

### Fixed (catalog accuracy)

- **MiniMax M2.7 context: 1M → 204,800 (~200K).** Earlier `1000000` was a
  hallucination — verified against `platform.minimax.io/docs/api-reference/text-anthropic-api`.
- **`opencode-minimax` context** corrected from 1M to 204800 (same model as
  direct MiniMax).
- **MiMo and Qwen context** changed from a single `context` field to per-tier
  `contextByTier` because the tiers differ wildly:
  - **MiMo**: Pro/Standard are 1024K, but V2-Flash (Haiku) is only 256K
  - **Qwen**: only Qwen3.6-Plus (Opus) is 1M; Coder/Coder-Next are 256K each
  - DISABLE_COMPACT/MAX_CONTEXT_TOKENS override deliberately NOT applied to
    these — would lie when user `/model`s down to the smaller tier
- **Picker context display** now shows ranges ("262-1049K") when tiers differ,
  and uses decimal /1000 to match Claude Code's UI convention (was /1024 → off
  by ~2.4%, e.g., "977K" instead of "1000K" for DeepSeek).

### Added

- **`contextByTier` catalog field** for providers with non-uniform tier
  context. When present, the picker shows the min-max range; otherwise falls
  back to the single `context` field.

## 3.0.1 — 2026-05-02

### Fixed

- **DeepSeek 1M context now displays correctly.** Previous catalog set
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS=1000000` — wrong knob (that controls
  *response* length). Replaced with `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000`
  *plus* `DISABLE_COMPACT=1` (both required per Claude Code docs).
- **`Reset-CC` and `cc-status`** now know about `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  and `DISABLE_COMPACT` — clears them on reset and shows them in status.

### Added

- **Configurable load banner.** `$env:CC_BANNER = full | compact | minimal`
  controls verbosity at module load. Default is `full` (matches v2.3 UX).
  Set in `$PROFILE` to make sticky.

### Notes

- The 200K → 1M context fix is opt-in per provider via the catalog's
  `envVars` field. DeepSeek has it; MiMo / Qwen / MiniMax do not yet but
  can be enabled with one JSON edit. See `ISSUES.md`.

---

## 3.0.0 — 2026-05-01

Major restructure. Old single-file script `<old-modules-path>\ClaudeCodeProviders.ps1`
replaced by a proper PowerShell module.

### Added

- **Tier mapping per provider.** One command per provider now sets Opus / Sonnet /
  Haiku to a flagship / standard / fast variant. Use `/model` inside Claude Code
  to switch tiers mid-session. Replaces 13 single-model commands with 7 tier-mapped
  commands:
  - `cc-deepseek`: v4-pro / v4 / v4-flash
  - `cc-mimo`: v2.5-pro / v2.5 / v2-flash
  - `cc-glm`: glm-5.1 / glm-5.1 / glm-4.5-air
  - `cc-qwen`: qwen3.6-plus / qwen3-coder / qwen3-coder-next
  - `cc-minimax`: M2.7 / M2.7 / M2.7-highspeed
  - `cc-nvidia`: kimi-k2-instruct / llama-4-maverick / llama-4-scout (override
    with `cc-nvidia <model>`)
  - `cc-kimi`: kimi-k2.6 (single model on all three)
- **JSON-driven provider catalog** at `data\providers.json`. Add a provider by
  editing JSON — no PowerShell function needed.
- **`cc-doctor`** — validates API keys (presence + heuristic format check) and
  pings each provider's endpoint with latency reporting.
- **`cc-usage`** — recursively scans `~/.claude/projects/**/*.jsonl` after every
  session, aggregates input / output / cache tokens per provider, and persists to
  `data\.usage-log.jsonl`.
- **`cc-pick`** — searchable grid picker via `Out-ConsoleGridView` (when
  `Microsoft.PowerShell.ConsoleGuiTools` is installed); falls back to `cc-launch`.
- **`cc-help`** — pretty-prints the full command catalog with tags.
- **Tab completion** for model args of `cc-openrouter`, `cc-opencode`, `cc-nvidia`
  via `Register-ArgumentCompleter`.
- **Disk-cached OpenRouter pricing** at `data\.pricing-cache.json`. First
  `cc-pricing` after a fresh shell is instant if the cache is warm.
- **`$env:CC_YOLO=1` global flag** — every `cc-*` launch auto-adds
  `--dangerously-skip-permissions`.
- **Module update detection** — `cc-switcher.psm1` mtime is compared against
  `data\.last-load`; load banner shows `[updated since last shell]` when newer.
- **`ExtraEnv` in catalog** — providers can declare extra env vars to set during
  launch. DeepSeek now sets `CLAUDE_CODE_MAX_OUTPUT_TOKENS=1000000` so the UI
  reflects the V4 Pro 1M context.

### Changed

- **DeepSeek endpoint** swapped from `api.deepseek.com/v1` (OpenAI-compat) to
  `api.deepseek.com/anthropic` (Anthropic-native). Avoids format translation;
  unlocks 1M context display.
- **Provider commands renamed for consolidation:**
  - `cc-deepseek-v4-pro` / `cc-deepseek-v4-flash` → `cc-deepseek` (tiered)
  - `cc-mimo-v25-pro` / `cc-mimo-v25` / `cc-mimo-v2-flash` → `cc-mimo`
  - `cc-qwen` / `cc-qwen-plus` / `cc-qwen-coder-next` → `cc-qwen`
  - `cc-glm5` / `cc-ling-flash` (dropped) → `cc-glm`
  - `cc-minimax-fast` → folded into `cc-minimax` (highspeed on Haiku)
- **Lazy-load banner.** Single one-line load message; full help on `cc-help`.
  Reduces shell start cost and noise.

### Removed

- `cc-anthropic` — use `cc-reset` then `claude`.
- `cc-copilot` — Removed per request.
- `cc-deepseek-v4-pro`, `cc-deepseek-v4-flash` — collapsed into `cc-deepseek`.
- `cc-mimo-v25-pro`, `cc-mimo-v25`, `cc-mimo-v2-flash` — collapsed into `cc-mimo`.
- `cc-qwen-plus`, `cc-qwen-coder-next` — collapsed into `cc-qwen`.
- `cc-glm5`, `cc-ling-flash` — collapsed; `cc-glm` covers GLM-5.1.
- `cc-minimax-fast` — `cc-minimax` Haiku tier covers highspeed.
- `cc-opencode-glm51`, `cc-opencode-glm5t` — covered by `cc-glm` (OpenRouter).
  Local Python proxy at `<your-tools-path>\claude-code-proxy` is now orphaned.
  Archived to `backup\opencode-glm.ps1` if needed.
- `cc-proxy-start` / `cc-proxy-stop` — only relevant for the dropped OpenCode
  GLM proxy. Archived.

### Migration notes

- `$PROFILE` line changed:
  ```powershell
  # OLD:  . <old-modules-path>\ClaudeCodeProviders.ps1
  # NEW:
  Import-Module <your-modules-path>\cc-switcher\cc-switcher.psd1
  ```
- Old script + docs preserved at `<your-archive-path>\cc-switcher-v2\` for
  reference.
- Replacement for orphaned commands: see Removed section above.

---

## 2.3.0 — 2026-05-01 (pre-restructure)

Last release before the cc-switcher folder structure. From the original
`HANDOFF.md`:

- Added NVIDIA NIM (`cc-nvidia-nim`).
- Switched DeepSeek to direct API endpoints. Fixed DeepSeek V3.2 model ID
  (was `deepseek/deepseek-v3.2`, now `deepseek-v3.2`).
- `cc-glm5` alias re-pointed to GLM-5.1 (`z-ai/glm-5.1`) instead of GLM-5.

## 2.2.0 and earlier

See git history. Pre-3.0 changes were ad-hoc; 3.0 is the first numbered release
with a CHANGELOG.
