# Catalog Environment Restoration Across Shells
Date: 2026-08-09
Project: cc-switcher
Tags: env-vars, powershell, bash, git-bash, jq, muse

## Context
Muse adds two catalog-defined environment variables. Its parity smoke tests had
to prove those values exist only while Claude Code is running.

## What we tried
1. Added PowerShell and Bash stubs that inspect Muse's launch environment.
2. Started with one pre-existing extra variable and one absent extra variable.
3. Ran Bash through native Windows Git Bash, not only Linux-style tooling.

## What happened
PowerShell restored an absent variable as an empty-but-present entry because a
null argument to `SetEnvironmentVariable` bound as an empty string on this
Windows runtime. Native `jq.exe` emitted CRLF records under Git Bash, and the
carriage return became part of each catalog `envVars` value.

## Root cause / why
Both implementations assumed platform newline/null behavior that was true in
their primary CI environment but not in the real Windows shells.

## Takeaway
Remove absent PowerShell environment variables through `Env:` rather than a
null string call. Strip a trailing carriage return from native jq tabular output.
Test catalog `envVars` with real Windows PowerShell and Git Bash as well as CI.

## References
- `lib/core.ps1`
- `bash/lib/providers.sh`
- `tests/muse-provider-smoke.ps1`
- `tests/muse-provider-smoke.sh`
