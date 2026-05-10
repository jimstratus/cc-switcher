# Adding a provider

Step-by-step walkthrough using a hypothetical `cohere` provider — Cohere Command R+/R/R-mini accessed through an Anthropic-compatible endpoint at `https://api.cohere.com/anthropic`. The Cohere Anthropic endpoint is hypothetical for this example; the steps generalize to any real provider.

## Decide: catalog-only or wrapper-needed?

Two paths:

- **Catalog-only** — works for the standard pattern: env-var auth, three-tier mapping, no custom logic. The dispatcher (`Invoke-CCProvider`) reads `data/providers.json` at runtime and handles everything generically. You still need a wrapper function and alias for the user-facing command, but the wrapper is one line. This is the right path for ~95% of providers, including the Cohere example below.

- **Wrapper-needed** — the provider needs custom logic outside the catalog. Examples: OAuth flow (Codex), generic dispatcher with required model arg (`cc-openrouter`, `cc-opencode`). You write a real function in `lib/providers.ps1` (or a new file in `lib/`), bypassing or extending `Invoke-CCProvider`. Reach for this only when you've confirmed the standard path can't express what you need.

The Cohere example below is catalog-only.

## Step 1 — add a catalog entry

Edit `data/providers.json`. Add a new key under `"providers"`:

```json
"cohere": {
  "command": "cc-cohere",
  "displayName": "Cohere Command R+",
  "qualityTier": "standard",
  "baseUrl": "https://api.cohere.com/anthropic",
  "authVar": "COHERE_API_KEY",
  "tiers": {
    "flagship": "command-r-plus",
    "standard": "command-r",
    "fast": "command-r-mini"
  },
  "context": 256000,
  "timeoutMs": 600000,
  "disableNonEssential": true,
  "notes": "Hypothetical Cohere Anthropic-compatible endpoint. Verify endpoint URL and model ids before relying on this entry.",
  "docs": "https://docs.cohere.com"
}
```

Field reference: `docs/catalog-schema.md`. Quick checklist:

- `qualityTier` is one of `flagship | standard | budget | free | slow`. Picks the picker tag.
- All three `tiers` keys are required even when ids repeat.
- `authVar` is the env var **name**, not the key itself.
- 256K context here — sub-500K, so auto-context does NOT fire. If Command R+ were 1M, it would fire automatically. To opt in at 256K explicitly, add `envVars` (see catalog-schema.md "Auto-context interaction").

## Step 2 — register the alias and wrapper

Two lines, one in each file.

**`lib/providers.ps1`** — add a one-line wrapper alongside the others (the existing block runs alphabetically by id around line 105):

```powershell
function Invoke-CC-Cohere     { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'cohere' -ClaudeArgs $ClaudeArgs }
```

The wrapper is one line because `Invoke-CCProvider` does all the catalog work. The wrapper just names the provider and forwards `$ClaudeArgs`.

**`cc-switcher.psm1`** — add a `Set-Alias` line in the alphabetical block (around line 25):

```powershell
Set-Alias -Name cc-cohere            -Value Invoke-CC-Cohere
```

Match the existing column alignment for readability.

## Step 3 — add to `FunctionsToExport` / `AliasesToExport`

Open `cc-switcher.psd1`. Add the function name to `FunctionsToExport` and the alias to `AliasesToExport`:

```powershell
FunctionsToExport = @(
    ...
    'Invoke-CC-Cohere',     # <-- add
    ...
)
AliasesToExport   = @(
    ...
    'cc-cohere',            # <-- add
    ...
)
```

**This step is not optional.** A function or alias not listed in the manifest is invisible to consumers after `Import-Module` from outside the module's session. `Export-ModuleMember -Function * -Alias *` in the psm1 looks like it covers everything, but the manifest takes precedence.

## Step 4 — verify

Run all four. Adapt the env-var name and command for your provider.

```powershell
# 1. Reload from clean state
Remove-Module cc-switcher -ErrorAction SilentlyContinue
Import-Module .\cc-switcher.psd1

# 2. Health check — confirms catalog parses, lists endpoint reachability
cc-doctor

# 3. Smoke-test the launch path with a stubbed `claude`
function global:claude { Write-Host "[stub] claude invoked"; Write-Host "URL=$env:ANTHROPIC_BASE_URL"; Write-Host "OPUS=$env:ANTHROPIC_DEFAULT_OPUS_MODEL" }
$env:COHERE_API_KEY = 'sk-test-fake-key-1234567890'
cc-cohere
# Expect: URL=https://api.cohere.com/anthropic, OPUS=command-r-plus

# 4. Confirm env vars restored after exit
cc-status
# Expect: ANTHROPIC_BASE_URL = (unset — Anthropic default)
Remove-Item Function:\claude
```

If `cc-status` after the stub returns shows `ANTHROPIC_BASE_URL` still pointing at the Cohere endpoint, the snapshot/restore path is broken — see `docs/architecture.md` "Snapshot / restore lifecycle".

For end-to-end testing with the real `claude`:

```powershell
$env:COHERE_API_KEY = '<your-real-key>'
cc-cohere --version    # Claude Code prints version then exits
```

## Step 5 — update CHANGELOG and docs

Bump version per semver (a new provider is MINOR per `README.md` "Versioning"):

- `cc-switcher.psd1` → `ModuleVersion = '3.2.0'`
- `cc-switcher.psm1` → `$script:CCSwitcherVersion = '3.2.0'`
- `data/providers.json` → top-level `"version": "3.2.0"`

Add an entry to `CHANGELOG.md` under the latest unreleased section (or create a `## 3.2.0 — YYYY-MM-DD` heading):

```markdown
## 3.2.0 — YYYY-MM-DD

### Added

- **`cc-cohere`** — Cohere Command R+/R/R-mini via Anthropic-compatible endpoint at `api.cohere.com/anthropic`. Tiers: command-r-plus (flagship) / command-r (standard) / command-r-mini (fast). 256K context.
```

Update `README.md`'s provider table with the new row. If the provider has a known gotcha worth a heading, add a section to `ISSUES.md`.

## Common pitfalls

- **Forgetting the model-id prefix when the provider is OpenRouter-routed.** OpenRouter model ids are `<vendor>/<model>` (e.g., `xiaomi/mimo-v2.5-pro`, not `mimo-v2.5-pro`). Direct-provider model ids usually have no prefix (`deepseek-v4-pro`, not `deepseek/deepseek-v4-pro`). Mixing them up causes 404s. Verify by curling the provider's `/v1/models` endpoint or checking the OpenRouter pricing list.

- **Mixing per-tier and uniform context.** Use `contextByTier` (per-tier) OR `context` (uniform), not both — except as a documented fallback minimum. The convention in existing entries (mimo, qwen) is to set `context` to the *minimum* across tiers and `contextByTier` to the per-tier truth; the picker reads `contextByTier` first. For a uniform provider, set only `context`.

- **Setting `envVars: { CLAUDE_CODE_MAX_CONTEXT_TOKENS: ... }` for a provider whose flagship is already >= 500K.** The auto-derive does it for you. Manual entry is redundant. If you want to *override* the auto value (e.g., cap at 800K instead of 1M), `envVars` applies AFTER the auto-block so the override works — but for the common "I want 1M" case, just leave it to auto-context.

- **Adding the alias but forgetting `AliasesToExport` in the psd1.** The alias works inside the module's own session (because of `Export-ModuleMember -Alias *` in the psm1), but disappears when the module is imported from elsewhere. Always edit all three places (psm1 `Set-Alias`, providers.ps1 wrapper, psd1 export lists).

- **Not bumping all three version markers.** psd1 `ModuleVersion`, psm1 `$script:CCSwitcherVersion`, and providers.json `version` move together. PowerShell's `Test-ModuleManifest` only checks the psd1 — drift in the other two won't fail any check, but it confuses agents and users reading the source.

- **Putting the API key value (not just the env var name) in the catalog.** `authVar` is the env-var **name**. Real keys live in the user's `$PROFILE` or `.env`. Committing a real key to `data/providers.json` is the kind of mistake that gets the repo flagged by GitHub's secret scanning.
