# AGENTS.md

> Read this first if you are an AI coding agent (Claude Code, Codex, Cursor, Copilot, etc.) working in this repo.
> Cross-tool, not Claude-specific.

## What this is

`cc-switcher` is a PowerShell module that launches [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) against any Anthropic-compatible LLM provider (DeepSeek, MiMo, GLM, Qwen, MiniMax, Kimi, NVIDIA NIM, Codex, etc.). It flips the `ANTHROPIC_*` environment variables Claude Code reads on startup, points them at an alternate provider's endpoint, runs `claude`, and restores the previous environment when the session exits. The catalog of providers is JSON-driven (`data/providers.json`) so adding a new provider is usually one JSON block plus a one-line wrapper.

## Where to read first

Order depends on intent:

1. **`AGENTS.md`** (this file) — orientation and invariants.
2. **`README.md`** — user-facing overview, command tables, quick start.
3. **`docs/architecture.md`** — internals: launch lifecycle, env-var contract, snapshot/restore, auto-context derivation.
4. **`docs/catalog-schema.md`** — every field in `data/providers.json`.
5. **`docs/adding-a-provider.md`** — step-by-step contributor walkthrough.
6. **`CHANGELOG.md`** — recent changes, especially the v3.1.0 auto-context entry.
7. **`ISSUES.md`** — known footguns and workarounds.

If your task touches `lib/core.ps1`, `lib/providers.ps1`, or `data/providers.json`, read `docs/architecture.md` and `docs/catalog-schema.md` before editing.

## Project layout

```
cc-switcher/
├── cc-switcher.psd1            # module manifest (FunctionsToExport, AliasesToExport, version)
├── cc-switcher.psm1            # entry point: dot-sources lib/, registers aliases, banner
├── lib/
│   ├── core.ps1                # Invoke-CCLaunch (env contract), Reset-CC, Get-CC-Status
│   ├── providers.ps1           # Get-CCCatalog, Get-CCProviders, Invoke-CCProvider, wrappers
│   ├── codex.ps1               # OAuth device flow, Get-CC-CodexToken
│   ├── pricing.ps1             # OpenRouter live pricing + disk cache
│   ├── doctor.ps1              # cc-doctor health check
│   ├── completers.ps1          # tab completion for cc-openrouter / cc-opencode / cc-nvidia
│   ├── usage.ps1               # session token tracking (.usage-log.jsonl)
│   ├── picker.ps1              # cc-launch (numbered) + cc-pick (gridview)
│   └── update-check.ps1        # mtime delta -> "[updated since last shell]" banner
├── data/
│   ├── providers.json          # the catalog (source of truth)
│   ├── .pricing-cache.json     # gitignored runtime cache
│   ├── .usage-log.jsonl        # gitignored token log
│   └── .last-load              # gitignored mtime sentinel
├── docs/
│   ├── architecture.md
│   ├── catalog-schema.md
│   └── adding-a-provider.md
├── README.md
├── AGENTS.md                   # this file
├── CHANGELOG.md
├── CONTRIBUTING.md
├── ISSUES.md
└── LICENSE                     # MIT
```

## Key invariants — DO NOT VIOLATE

These are load-bearing. If you change one without updating the other(s), things break silently.

1. **The env-var contract in `lib/core.ps1` is symmetric.** Every variable that `Invoke-CCLaunch` *sets* must also appear in the `$snapshot` hashtable at the top of the function AND in the `Reset-CC` cleanup list. Asymmetry causes env leaks across `cc-*` switches. The v3.1.0 fix added `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `DISABLE_COMPACT` to all three places — keep them in sync.

2. **The `flagship → opus, standard → sonnet, fast → haiku` tier mapping is the public contract.** Translation happens in `Invoke-CCProvider` (`lib/providers.ps1`). Renaming would break every user's `/model opus|sonnet|haiku` muscle memory. Catalog uses the semantic names; Claude Code's wire protocol uses the Anthropic names.

3. **Auto-context threshold (`>= 500000`) is deliberately tuned.** See `docs/architecture.md` for the rationale. It cleanly separates 1M-class flagships (DeepSeek, MiMo v2.5-Pro, Qwen3.6-Plus, Xiaomi v2.5-Pro) from 256K and 200K models where losing auto-compact would be a bad trade. Don't lower the threshold without reading the rationale.

4. **The catalog (`data/providers.json`) is the source of truth for which providers exist.** Never hardcode a provider name, model id, base URL, or auth-var name inside `lib/`. The dispatcher reads it all from JSON. Wrapper functions in `lib/providers.ps1` are one-liners that pass an `Id` to `Invoke-CCProvider`.

5. **Module version, catalog version, and `$script:CCSwitcherVersion` must move together.** Three places: `cc-switcher.psd1` (`ModuleVersion`), `cc-switcher.psm1` (`$script:CCSwitcherVersion`), and `data/providers.json` (top-level `version`). All three bumped on every user-visible release.

6. **`FunctionsToExport` and `AliasesToExport` in the psd1 are not optional.** A function or alias not listed there will not be visible after `Import-Module` from outside the module's session. Adding a new wrapper or alias means three edits, not one.

## Common tasks

### Add a provider

Edit `data/providers.json` to add a new key under `"providers"`. If a new alias is wanted, add `Set-Alias` line in `cc-switcher.psm1`, a one-line wrapper in `lib/providers.ps1`, and entries in `cc-switcher.psd1`'s `FunctionsToExport` / `AliasesToExport`. Walkthrough in `docs/adding-a-provider.md`. Catalog field reference in `docs/catalog-schema.md`.

```json
"cohere": {
  "command": "cc-cohere",
  "displayName": "Cohere Command R+",
  "qualityTier": "standard",
  "baseUrl": "https://api.cohere.com/anthropic",
  "authVar": "COHERE_API_KEY",
  "tiers": { "flagship": "command-r-plus", "standard": "command-r", "fast": "command-r-mini" },
  "context": 256000,
  "timeoutMs": 600000
}
```

### Add a wrapper command

In `lib/providers.ps1`:

```powershell
function Invoke-CC-Cohere { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'cohere' -ClaudeArgs $ClaudeArgs }
```

In `cc-switcher.psm1`:

```powershell
Set-Alias -Name cc-cohere -Value Invoke-CC-Cohere
```

In `cc-switcher.psd1`, add `'Invoke-CC-Cohere'` to `FunctionsToExport` and `'cc-cohere'` to `AliasesToExport`.

### Debug a launch

Run `cc-status` to see the current env state. Run `cc-doctor` to validate keys and ping endpoints. To trace what `Invoke-CCLaunch` is doing, set `$VerbosePreference = 'Continue'` before calling — the function uses `[CmdletBinding()]` so `-Verbose` is available. `Get-CCProviders | Format-List` dumps the parsed catalog.

### Regenerate the help output

`cc-help` prints the help text on demand. There is no separate generated artifact; the function reads `Get-CCProviders` at call time. To verify your new provider appears: `Remove-Module cc-switcher; Import-Module .\cc-switcher.psd1; cc-help`.

## Verification before declaring done

Run all four. Each step has a concrete pass condition.

1. **Manifest parses cleanly.**
   ```powershell
   Test-ModuleManifest .\cc-switcher.psd1
   ```
   Pass: returns the manifest object with no errors. Fail: red error text from `Test-ModuleManifest`.

2. **Module imports in a fresh shell.**
   ```powershell
   Remove-Module cc-switcher -ErrorAction SilentlyContinue
   Import-Module .\cc-switcher.psd1
   ```
   Pass: banner prints, no `ParseException` / `RuntimeException`. Fail: any red text.

3. **Smoke-test the affected `cc-*` command with a stubbed `claude`.** Stub `claude`, set a fake API key, invoke the command, and assert env vars went where they should.
   ```powershell
   function global:claude { Write-Host "[stub] claude invoked"; Write-Host "URL=$env:ANTHROPIC_BASE_URL"; Write-Host "MODEL=$env:ANTHROPIC_DEFAULT_OPUS_MODEL" }
   $env:OPENROUTER_API_KEY = 'sk-or-test-fake-key-1234567890'
   cc-mimo
   # Expect: URL=https://openrouter.ai/api/v1, MODEL=xiaomi/mimo-v2.5-pro
   cc-status   # confirm env vars cleared after stub returns
   Remove-Item Function:\claude
   ```
   Pass: stub prints expected URL + model id; `cc-status` after exit shows the env vars unset (restored). Fail: env vars persist after exit, or wrong values printed.

4. **CHANGELOG updated.** Add an entry under the latest unreleased section in `CHANGELOG.md` describing the change.

## What to avoid

- **Hardcoding API keys anywhere.** `authVar` in the catalog names the env var; the value comes from the user's environment.
- **Breaking the snapshot/restore symmetry.** Adding a `$env:FOO = 'bar'` line in `Invoke-CCLaunch` without also adding `FOO` to the snapshot dict and to `Reset-CC` is the recipe for env leaks across switches.
- **Provider-specific logic outside the catalog.** If you find yourself writing `if ($Id -eq 'mimo') { ... }` in `lib/providers.ps1`, you're working around a missing catalog field. Add the field to `_doc` in `providers.json` and read it generically.
- **Polluting `Reset-CC` without updating `Invoke-CCLaunch`'s snapshot dict.** They must stay symmetric (see invariant 1).
- **Putting model ids in `lib/`.** They belong in the catalog. The only exceptions are completer fallback lists in `lib/completers.ps1` (curated lists for `cc-opencode` / `cc-nvidia` since those vendors don't expose a model-listing API).
- **Adding external dependencies.** No third-party PowerShell modules. The only optional dep is `Microsoft.PowerShell.ConsoleGuiTools` for `cc-pick`, and the picker falls back gracefully when it's absent.

## Style guide

- PowerShell-idiomatic: verb-noun function names, `[CmdletBinding()]` for advanced functions, `param()` blocks with explicit types.
- Match what's already in `lib/`. Skim a sibling file before adding a new one.
- No external dependencies (see "What to avoid" above).
- Comment only the non-obvious "why" — the auto-context threshold rationale in `core.ps1` is a good example of when a comment is worth its weight.
- Keep functions small. The dispatcher in `Invoke-CCProvider` is the upper bound of complexity; new code should stay under it.
