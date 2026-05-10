# Catalog schema

Reference for `data/providers.json`. Edit this file to add, remove, or reconfigure providers — no PowerShell changes needed for the common case.

## File location and version

- **Path:** `data/providers.json`
- **Top-level `version`** (string): tracks schema + content revisions. Bumped whenever the file changes meaningfully. Currently `"3.1.0"`. Must move in lockstep with `cc-switcher.psd1`'s `ModuleVersion` and `cc-switcher.psm1`'s `$script:CCSwitcherVersion`.
- **Schema reference**: `"$schema": "https://json-schema.org/draft-07/schema#"` (advisory; no formal JSON Schema is published).

## Top-level structure

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "version": "3.1.0",
  "_doc": { ... },
  "providers": {
    "<id>": { <provider definition> },
    ...
  }
}
```

- **`version`** — semver string. Bump per the rules in `README.md` "Versioning".
- **`_doc`** — a non-functional documentation block. The dispatcher ignores it. Treat it as inline docs for human and AI editors. Keep field-level commentary here so the file is self-explanatory.
- **`providers`** — map of provider id (used internally by `Invoke-CCProvider -Id <id>`) to provider definition.

## Provider definition fields

Every field below appears under one provider key in `providers`. Mandatory fields are flagged.

### `command` *(mandatory)*

The alias name registered in `cc-switcher.psm1` for this provider. By convention `cc-<id>`, but free-form. Example: `"cc-deepseek"`. Matches the alias declared in `Set-Alias -Name cc-deepseek` in the psm1.

### `displayName`

Human-readable name shown in `cc-help`, `cc-launch`, and `cc-status`. Free-form; include disambiguation suffixes when needed (e.g., `"GLM-5.1 (Z.AI via OpenRouter)"` vs `"Z.AI GLM-5.1 [SLOW — China endpoint]"`).

### `qualityTier`

Sort/tag label, one of:

- `flagship` — top-tier provider for general use; no tag rendered.
- `standard` — default workhorse.
- `budget` — cheap or rate-limited.
- `free` — free tier; tagged `[free]`.
- `slow` — sorted last in pickers; tagged `[SLOW]`. Used for endpoints that work but have prohibitive latency (e.g., China endpoints from US).

The picker (`cc-launch`) sorts alphabetically except `slow` which is forced to the bottom (`lib/picker.ps1:9-11`).

### `baseUrl` *(mandatory)*

The Anthropic-compatible endpoint. Examples:

- `"https://api.deepseek.com/anthropic"` — direct provider with native Anthropic format
- `"https://openrouter.ai/api/v1"` — OpenRouter (handles format translation)
- `"https://api.minimax.io/anthropic"` — direct provider, Anthropic-native

### `authVar` *(mandatory unless `requiresOAuth: true`)*

The env-var **name** that holds the API key. NOT the key itself — never put real keys in this file. `Invoke-CCProvider` reads the env var at launch time via `[Environment]::GetEnvironmentVariable($authVar)`. Examples: `"DEEPSEEK_API_KEY"`, `"OPENROUTER_API_KEY"`.

When `requiresOAuth: true`, this field is ignored; the auth token comes from `Get-CC-CodexToken` instead (the only current OAuth provider is Codex; the placeholder string `"_codex_oauth_token"` is in the catalog for cosmetic consistency).

### `tiers` *(mandatory: all three keys)*

Map of tier name → model id:

```json
"tiers": {
  "flagship": "<model-id-for-/model-opus>",
  "standard": "<model-id-for-/model-sonnet>",
  "fast":     "<model-id-for-/model-haiku>"
}
```

All three keys are required even when the same model id repeats across tiers (the Kimi pattern: one model on all three slots). The dispatcher (`lib/providers.ps1:72-74`) translates these into Anthropic's `opus/sonnet/haiku` slot names.

### `context`

Uniform context cap in tokens; used as fallback when `contextByTier` is absent. Either set this OR `contextByTier`. When both are set (legacy mimo/qwen pattern), `contextByTier.flagship` wins for auto-context derivation; `context` is treated as the safe minimum across tiers.

### `contextByTier`

Per-tier context cap when tiers differ. Map of `flagship/standard/fast` → token count. Example (MiMo):

```json
"context": 262144,
"contextByTier": { "flagship": 1048576, "standard": 1048576, "fast": 262144 }
```

The picker shows the min-max range when `contextByTier` is set and the values differ (`lib/picker.ps1:22-31`). The auto-context derivation reads `contextByTier.flagship` first, falling back to `context`.

### `timeoutMs`

Request timeout in milliseconds. Sets `API_TIMEOUT_MS`. Default in `Invoke-CCLaunch` is 3000000 (50 minutes) when not specified by the catalog. Direct providers often set lower (e.g., 600000 = 10 min) to fail fast on stalls.

### `disableNonEssential`

Boolean. When `true`, sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, which suppresses telemetry-class requests Claude Code sends. Useful for direct providers to avoid 404s on endpoints they don't implement.

### `envVars`

Extra `{ NAME: value }` map applied AFTER the auto-context block (`lib/core.ps1:86-90`). Two roles:

1. **Override auto-derived values.** A provider whose flagship context is 1M but where the user wants to cap output explicitly can set `CLAUDE_CODE_MAX_OUTPUT_TOKENS` here.
2. **Opt in a sub-500K provider** to extended-context behavior. Auto-context only fires at `>= 500000`; smaller providers needing the env vars must declare them here.

```json
"envVars": {
  "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "256000",
  "DISABLE_COMPACT": "1"
}
```

### `requiresOAuth`

Boolean. When `true`, `Invoke-CCProvider` routes auth through `Get-CC-CodexToken` instead of reading `authVar`. Currently used only by `codex`. The user must run `cc-codex-login` first to populate the token cache at `~/.config/codex-oauth/token.json`.

### `notes`

Free-form provider-specific gotchas. Read by humans and agents — keep current. Document things like: "tier IDs verified <date>", "no flash SKU exists, fast slot maps to v2-pro", "earlier 1M context claim was wrong — verified 200K via api docs".

### `docs`

URL to the provider's own documentation. Surfaced through tooling (not currently rendered, but agents reading the catalog use it).

## Validation

The dispatcher (`Invoke-CCProvider` in `lib/providers.ps1`) tolerates missing optional fields:

- Missing `disableNonEssential` → defaults to `false` via `[bool]` cast on `$null`.
- Missing `envVars` → empty hashtable, no extra env applied.
- Missing `context` AND `contextByTier` → `$flagshipContext = 0`, auto-context skipped.
- Missing `notes` / `docs` → ignored.
- Missing `timeoutMs` → falls through to `Invoke-CCLaunch`'s 3000000 default.

**Mandatory fields:**

- `command`
- `baseUrl`
- `authVar` (unless `requiresOAuth: true`)
- `tiers.flagship`, `tiers.standard`, `tiers.fast` — all three required

If `tiers.flagship` is missing, the dispatcher will pass `$null` as `-OpusModel` to `Invoke-CCLaunch`, which is a `[Parameter(Mandatory)]` so PowerShell will error before the launch.

## Examples

### Uniform-context provider (DeepSeek)

All tiers same model + 1M context. Auto-context fires (1M >= 500K).

```json
"deepseek": {
  "command": "cc-deepseek",
  "displayName": "DeepSeek V4",
  "qualityTier": "flagship",
  "baseUrl": "https://api.deepseek.com/anthropic",
  "authVar": "DEEPSEEK_API_KEY",
  "tiers": {
    "flagship": "deepseek-v4-pro",
    "standard": "deepseek-v4-pro",
    "fast": "deepseek-v4-flash"
  },
  "context": 1000000,
  "timeoutMs": 600000,
  "disableNonEssential": true
}
```

### Per-tier-context provider (MiMo)

Flagship/standard at 1M, fast at 256K. Auto-context fires from `contextByTier.flagship` (1M >= 500K). Documented caveat: status bar shows 1M even when on `/model haiku`.

```json
"mimo": {
  "command": "cc-mimo",
  "displayName": "MiMo V2.5 (Xiaomi via OpenRouter)",
  "qualityTier": "flagship",
  "baseUrl": "https://openrouter.ai/api/v1",
  "authVar": "OPENROUTER_API_KEY",
  "tiers": {
    "flagship": "xiaomi/mimo-v2.5-pro",
    "standard": "xiaomi/mimo-v2.5",
    "fast":     "xiaomi/mimo-v2-flash"
  },
  "context": 262144,
  "contextByTier": { "flagship": 1048576, "standard": 1048576, "fast": 262144 },
  "timeoutMs": 600000,
  "disableNonEssential": true
}
```

### Free / token-budgeted provider (NVIDIA)

Explicit `qualityTier: free` so the picker tags it `[free]` and sorts it sensibly. Sub-500K context, so auto-context does NOT fire.

```json
"nvidia": {
  "command": "cc-nvidia",
  "displayName": "NVIDIA NIM (free)",
  "qualityTier": "free",
  "baseUrl": "https://integrate.api.nvidia.com/v1",
  "authVar": "NVIDIA_API_KEY",
  "tiers": {
    "flagship": "moonshotai/kimi-k2-instruct",
    "standard": "meta/llama-4-maverick-17b-128e-instruct",
    "fast":     "meta/llama-4-scout-17b-16e-instruct"
  },
  "context": 128000,
  "timeoutMs": 3000000,
  "disableNonEssential": true,
  "notes": "Free tier with rate limits. Tier IDs are best-guess defaults — verify at https://build.nvidia.com/explore/discover and edit this JSON to taste."
}
```

## Auto-context interaction

`CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `DISABLE_COMPACT=1` are **auto-set** when the resolved flagship context (`contextByTier.flagship` if present, else `context`) is `>= 500000`. The threshold is hardcoded in `lib/core.ps1:75` and rationalized in `docs/architecture.md`.

To opt in a smaller-context provider, add `envVars` explicitly in the catalog block:

```json
"envVars": {
  "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "256000",
  "DISABLE_COMPACT": "1"
}
```

`envVars` is applied AFTER the auto-block, so for a `>= 500K` provider where you want a different context cap (e.g., 800K instead of 1M), `envVars` will override the auto-derived value.

For per-tier auto-context honesty, see the "Tradeoff" note in `docs/architecture.md` — when flagship and fast tiers differ in size, the env var stays at the flagship size for the whole session.
