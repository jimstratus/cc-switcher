# PowerShell Profile Version Boundary
Date: 2026-08-09
Project: cc-switcher
Tags: powershell, profile, module-loading, compatibility, windows

## Context
`cc-minimax` was missing in a fresh terminal. Running `cc-help` then emitted
parse errors and left `cc-minimax` present but unable to find `Invoke-CCLaunch`.

## What we tried
1. Reproduced module loading under Windows PowerShell 5.1 and PowerShell 7.6.4.
2. Inspected the OneDrive-redirected PowerShell profiles and their shared
   `C:\Users\ryanm\ClaudeCodeProviders.ps1` wrapper.
3. Tested a tracked profile loader in both shells, including a stubbed
   `cc-minimax` launch through the Windows PowerShell proxy.
4. Installed the loader through the existing shared wrapper and verified fresh
   real-user shell sessions.

## What happened
The shared wrapper intentionally defined only `cc-help`, so every other `cc-*`
command was absent until help ran. It then imported `cc-switcher.psm1` directly,
bypassing the manifest's PowerShell 7 minimum-version guard. Windows PowerShell
5 misread UTF-8 punctuation and could not parse the PowerShell 7 `??` operator,
leaving a partially imported module.

## Root cause / why
Lazy loading hid every provider command, and the lazy entry point bypassed the
module's declared runtime boundary. Directly parsing a PowerShell 7 module in
Windows PowerShell 5 can never be a safe compatibility strategy.

## Takeaway
Expose all commands at profile load. Import normally in PowerShell 7; in Windows
PowerShell 5, use thin proxy functions that run the unchanged module in an
installed `pwsh` child process. Always import through the manifest.

## References
- `powershell/profile-loader.ps1`
- `powershell/invoke-cc-switcher.ps1`
- `tests/profile-loader-smoke.ps1`
- `C:\Users\ryanm\ClaudeCodeProviders.ps1`
- `C:\Users\ryanm\ClaudeCodeProviders.ps1.bak-20260809-pre-profile-fix`
