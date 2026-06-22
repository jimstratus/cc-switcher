# Contributing

Thanks for your interest in `cc-switcher`. This module is small enough that the contribution flow is intentionally lightweight.

## Adding or updating a provider

**TL;DR:** the provider catalog lives in `data/providers.json`, with a synchronized copy at `bash/data/providers.json` (CI fails if they diverge — edit both). Append a new key under `"providers"` with the same shape as the existing entries (see `_doc` at the top of the file for field semantics). No script changes needed for the common case — both dispatchers read the catalog at runtime. For a new public command: PowerShell needs a thin wrapper in `lib/providers.ps1`, a `Set-Alias` line in `cc-switcher.psm1`, and entries in `cc-switcher.psd1`'s `FunctionsToExport` / `AliasesToExport`; bash needs one line in `bash/cc-switcher.sh`'s alias block.

For the deep walkthrough — including a worked `cohere` example, the verification recipe, and common pitfalls — see [`docs/adding-a-provider.md`](docs/adding-a-provider.md). Field-by-field catalog reference is in [`docs/catalog-schema.md`](docs/catalog-schema.md).

## Testing your change

Before opening a PR:

1. Reload the module in a fresh shell:
   ```powershell
   Remove-Module cc-switcher -ErrorAction SilentlyContinue
   Import-Module .\cc-switcher.psd1
   ```
   ```bash
   # bash port
   source ./bash/cc-switcher.sh
   ```
2. Run the health check:
   ```powershell
   cc-doctor
   ```
   Confirm your provider's row prints `[OK]` for endpoint reachability.
3. Smoke-test the launch path:
   ```powershell
   cc-<your-provider> --version    # Claude Code prints version then exits
   ```
4. For bash changes, lint locally — CI gates on it:
   ```bash
   (cd bash && shellcheck -x -S warning -e SC2148 cc-switcher.sh lib/*.sh)
   ```

CI (`.github/workflows/ci.yml`) runs on every PR: bash syntax + shellcheck + a sourced-module smoke test with a stubbed `claude`, `make install` layout verification, catalog validation and cross-copy sync, and a PowerShell parse/manifest check.

## Issues and PRs

- File issues with the output of `cc-doctor` and the relevant `cc-status` snapshot when reporting a problem.
- Keep PRs focused — provider additions, bug fixes, and doc updates separately.
- Update `CHANGELOG.md` under an unreleased heading if your change is user-visible.

## Style

PowerShell-idiomatic; match what's already in `lib/`. Keep functions small, keep parameters explicit, and avoid adding dependencies.
