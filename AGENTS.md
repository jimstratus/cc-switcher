# AGENTS.md

> Read this first if you are an AI coding agent (Claude Code, Codex, Cursor, Copilot, etc.) working in this repo.
> Cross-tool, not Claude-specific.

## What this is

`cc-switcher` launches [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) against any Anthropic-compatible LLM provider (DeepSeek, MiMo, GLM, Qwen, MiniMax, Kimi, NVIDIA NIM, Codex, etc.). It flips the `ANTHROPIC_*` environment variables Claude Code reads on startup, points them at an alternate provider's endpoint, runs `claude`, and restores the previous environment when the session exits. The catalog of providers is JSON-driven (`data/providers.json`) so adding a new provider is usually one JSON block plus a one-line wrapper.

There are **two parallel implementations** with the same commands and catalog format:

- **PowerShell module** (repo root: `cc-switcher.psd1` / `cc-switcher.psm1` / `lib/*.ps1`) — Windows/macOS.
- **bash port** (`bash/cc-switcher.sh` + `bash/lib/*.sh`) — Linux/macOS, **sourced** into the interactive shell (not executed).

A change to launch behavior, the env-var contract, or the catalog schema almost always needs to land in **both** implementations. The two catalog copies (`data/providers.json` and `bash/data/providers.json`) must stay byte-identical (modulo formatting) — CI fails the build if they diverge.

## Where to read first

Order depends on intent:

1. **`AGENTS.md`** (this file) — orientation and invariants.
2. **`README.md`** — user-facing overview, command tables, quick start.
3. **`docs/architecture.md`** — internals: launch lifecycle, env-var contract, snapshot/restore, auto-context derivation.
4. **`docs/catalog-schema.md`** — every field in `data/providers.json`.
5. **`docs/adding-a-provider.md`** — step-by-step contributor walkthrough.
6. **`CHANGELOG.md`** — recent changes, especially the v3.2.0 entry.
7. **`ISSUES.md`** — known footguns and workarounds.

If your task touches `lib/core.ps1`, `lib/providers.ps1`, or `data/providers.json`, read `docs/architecture.md` and `docs/catalog-schema.md` before editing.

## Project layout

```
cc-switcher/
├── cc-switcher.psd1            # module manifest (FunctionsToExport, AliasesToExport, version)
├── cc-switcher.psm1            # entry point: dot-sources lib/, registers aliases, banner
├── lib/                        # PowerShell implementation
│   ├── core.ps1                # Invoke-CCLaunch (env contract), Reset-CC, Get-CC-Status
│   ├── providers.ps1           # Get-CCCatalog, Get-CCProviders, Invoke-CCProvider, wrappers
│   ├── codex.ps1               # OAuth device flow, Get-CC-CodexToken
│   ├── pricing.ps1             # OpenRouter live pricing + disk cache
│   ├── doctor.ps1              # cc-doctor health check
│   ├── completers.ps1          # tab completion for cc-openrouter / cc-opencode / cc-nvidia
│   ├── usage.ps1               # session token tracking (.usage-log.jsonl)
│   ├── picker.ps1              # cc-launch (numbered) + cc-pick (gridview)
│   └── update-check.ps1        # mtime delta -> "[updated since last shell]" banner
├── bash/                       # bash port (sourced module; see docs/architecture.md "The bash port")
│   ├── cc-switcher.sh          # entry point: sources lib/, defines cc-* functions, banner
│   ├── Makefile                # make install (~/.cc-switcher) / install-system
│   ├── lib/                    # 1:1 ports of the PowerShell lib files (no picker)
│   │   ├── core.sh             # invoke_cc_launch, reset_cc, get_cc_status, _CC_MANAGED_VARS
│   │   ├── providers.sh        # catalog lookup, invoke_cc_provider, cc-launch menu
│   │   ├── codex.sh            # OAuth device flow, token cache (0600)
│   │   ├── pricing.sh          # OpenRouter live pricing + disk cache
│   │   ├── doctor.sh           # cc-doctor health check
│   │   ├── completers.sh       # bash tab completion
│   │   ├── usage.sh            # session token tracking (SQLite + JSONL)
│   │   └── update-check.sh     # mtime banner flag + show_cc_help
│   └── data/
│       └── providers.json      # bash copy of the catalog — must match data/providers.json (CI-enforced)
├── data/
│   ├── providers.json          # the catalog (source of truth)
│   ├── .pricing-cache.json     # gitignored runtime cache
│   ├── .usage-log.jsonl        # gitignored token log
│   └── .last-load              # gitignored mtime sentinel
├── .github/workflows/ci.yml    # CI: shellcheck + bash smoke test, catalog validation/sync, PS parse
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

1. **The env-var contract is symmetric — in both implementations.** Every variable the launcher *sets* must also be snapshotted at function entry AND cleared by the reset command. PowerShell: the `$snapshot` hashtable and `Reset-CC` in `lib/core.ps1`. Bash: the single `_CC_MANAGED_VARS` array in `bash/lib/core.sh` drives snapshot, restore, and `cc-reset` — add new managed vars there, never as a one-off. Asymmetry causes env leaks across `cc-*` switches.

2. **The `flagship → opus, standard → sonnet, fast → haiku` tier mapping is the public contract.** Translation happens in `Invoke-CCProvider` (`lib/providers.ps1`) / `invoke_cc_provider` (`bash/lib/providers.sh`). Renaming would break every user's `/model opus|sonnet|haiku` muscle memory. Catalog uses the semantic names; Claude Code's wire protocol uses the Anthropic names.

3. **Auto-context threshold (`>= 500000`) is deliberately tuned.** See `docs/architecture.md` for the rationale. It cleanly separates 1M-class flagships (DeepSeek, MiMo v2.5-Pro, Qwen3.6-Plus, Xiaomi v2.5-Pro) from 256K and 200K models where losing auto-compact would be a bad trade. Don't lower the threshold without reading the rationale.

4. **The catalog (`data/providers.json`) is the source of truth for which providers exist.** Never hardcode a provider name, model id, base URL, or auth-var name inside `lib/` or `bash/lib/`. The dispatchers read it all from JSON. Wrapper functions are one-liners that pass an id to the dispatcher.

5. **Version markers move together.** Five places: `cc-switcher.psd1` (`ModuleVersion`), `cc-switcher.psm1` (`$script:CCSwitcherVersion`), `bash/cc-switcher.sh` (`CCSWITCHER_VERSION`), and the `version` field in both catalog copies. All bumped on every user-visible release.

6. **`FunctionsToExport` and `AliasesToExport` in the psd1 are not optional.** A function or alias not listed there will not be visible after `Import-Module` from outside the module's session. Adding a new wrapper or alias means three edits, not one.

7. **The two catalog copies must stay in sync.** `data/providers.json` and `bash/data/providers.json` are byte-equivalent JSON; CI (`.github/workflows/ci.yml`, "catalogs in sync" step) fails if they diverge. Edit both in the same commit.

8. **The bash files are sourced into interactive shells — they must not change shell state.** No `set -e`/`-u`/`pipefail`, no `shopt` changes, no traps at load time: anything set at source time leaks into the user's session permanently. Use explicit guards (`${var:-}`, `|| true`) instead. CI's smoke test asserts `$-` is unchanged after sourcing.

## Common tasks

### Add a provider

Edit `data/providers.json` to add a new key under `"providers"` **and copy the change to `bash/data/providers.json`** (CI enforces sync). For the PowerShell side, add a `Set-Alias` line in `cc-switcher.psm1`, a one-line wrapper in `lib/providers.ps1`, and entries in `cc-switcher.psd1`'s `FunctionsToExport` / `AliasesToExport`. For the bash side, add one line to the alias block in `bash/cc-switcher.sh` (`cc-<id>() { invoke_cc_provider "<id>" "" "$@"; }`) — the `cc-launch` menu picks it up automatically via the catalog's `command` field. Walkthrough in `docs/adding-a-provider.md`. Catalog field reference in `docs/catalog-schema.md`.

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

4. **Bash port verified (when the change touches `bash/`).** Each step has a concrete pass condition; CI runs the same checks.
   ```bash
   # Syntax + lint
   (cd bash && for f in cc-switcher.sh lib/*.sh; do bash -n "$f"; done)
   (cd bash && shellcheck -x -S warning -e SC2148 cc-switcher.sh lib/*.sh)

   # Smoke-test with a stubbed claude
   mkdir -p /tmp/mockbin && printf '#!/bin/bash\necho "URL=$ANTHROPIC_BASE_URL"\n' > /tmp/mockbin/claude && chmod +x /tmp/mockbin/claude
   PATH="/tmp/mockbin:$PATH" bash -c '
     source ./bash/cc-switcher.sh >/dev/null
     export DEEPSEEK_API_KEY=sk-test1234567890
     cc-deepseek           # expect URL=https://api.deepseek.com/anthropic
     cc-status             # expect ANTHROPIC_BASE_URL = (unset — Anthropic default)
   '
   ```
   Pass: stub prints the provider URL and `cc-status` afterwards shows the vars unset (restored). Fail: env vars persist after exit, or sourcing prints errors.

5. **CHANGELOG updated.** Add an entry under the latest unreleased section in `CHANGELOG.md` describing the change.

## What to avoid

- **Hardcoding API keys anywhere.** `authVar` in the catalog names the env var; the value comes from the user's environment.
- **Breaking the snapshot/restore symmetry.** Adding a `$env:FOO = 'bar'` line in `Invoke-CCLaunch` without also adding `FOO` to the snapshot dict and to `Reset-CC` is the recipe for env leaks across switches.
- **Provider-specific logic outside the catalog.** If you find yourself writing `if ($Id -eq 'mimo') { ... }` in `lib/providers.ps1`, you're working around a missing catalog field. Add the field to `_doc` in `providers.json` and read it generically.
- **Polluting `Reset-CC` without updating `Invoke-CCLaunch`'s snapshot dict.** They must stay symmetric (see invariant 1).
- **Putting model ids in `lib/`.** They belong in the catalog. The only exceptions are completer fallback lists in `lib/completers.ps1` (curated lists for `cc-opencode` / `cc-nvidia` since those vendors don't expose a model-listing API).
- **Adding external dependencies.** No third-party PowerShell modules. The only optional dep is `Microsoft.PowerShell.ConsoleGuiTools` for `cc-pick`, and the picker falls back gracefully when it's absent. The bash port depends only on `jq`, `curl`, and optionally `sqlite3`.
- **Changing shell state in the bash port at source time.** See invariant 8. Also avoid per-line subprocess loops (`echo | jq` inside `while read`) — the port batches jq work into single passes for a reason; a Claude Code transcript can be thousands of lines.
- **Fixing a bug in one implementation only.** If the bug exists in both ports, fix both (or file an issue for the other side) — they are kept feature-equivalent.

## Style guide

- PowerShell-idiomatic: verb-noun function names, `[CmdletBinding()]` for advanced functions, `param()` blocks with explicit types.
- Bash: snake_case function names (`invoke_cc_provider`), `_`-prefixed internals, `local` everything, quote every expansion, prefer one jq pass over per-field calls. `shellcheck -x -S warning` must be clean (CI gate).
- Match what's already in `lib/` / `bash/lib/`. Skim a sibling file before adding a new one.
- No external dependencies (see "What to avoid" above).
- Comment only the non-obvious "why" — the auto-context threshold rationale in `core.ps1` is a good example of when a comment is worth its weight.
- Keep functions small. The dispatcher in `Invoke-CCProvider` is the upper bound of complexity; new code should stay under it.
