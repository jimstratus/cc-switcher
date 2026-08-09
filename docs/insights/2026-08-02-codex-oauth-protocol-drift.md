# Codex OAuth Protocol Drift
Date: 2026-08-09
Project: cc-switcher
Tags: codex, oauth, device-flow, powershell, bash

## Context
`cc-codex-login` failed before displaying a device code with HTTP 403. We needed
to determine whether the failure was account-specific or caused by the client,
and to choose a supported direction for the Codex integration.

## What we tried
1. Traced the PowerShell and bash implementations and their token-cache readers.
2. Compared their requests with the current official `openai/codex` login source.
3. Checked the project history and CI coverage for prior end-to-end validation.

## What happened
Both implementations use the retired `oauth.openai.com/v1/device_authorization`
and `/v1/token` endpoints with form data and `client_id=chatbot`. Current Codex
uses JSON device-auth requests under `auth.openai.com/api/accounts/deviceauth`,
then exchanges the returned authorization code and PKCE verifier at
`auth.openai.com/oauth/token`. The PowerShell implementation also writes the raw
token response without deriving the absolute `expires_at` required by its own
cache reader.

## Root cause / why
The OAuth implementation drifted from the current Codex device-flow contract.
The immediate 403 is therefore expected server rejection of an obsolete request,
not evidence of a bad ChatGPT account. The design has a deeper incompatibility:
OpenAI confirms Codex's ChatGPT OAuth token is invalid for the public API, and
the public API does not implement Claude Code's Anthropic Messages protocol.

## Decision
Formal retirement (issue #24, option 3). The alternatives were rejected:
- A protocol adapter (Anthropic Messages -> OpenAI API) has no supported target
  endpoint for ChatGPT credentials and would need separately billed Platform
  keys plus a permanent translation layer.
- A native Codex launcher would break cc-switcher's contract that every `cc-*`
  provider command launches Claude Code.

`cc-codex` / `cc-codex-login` remain as migration guards pointing to
`codex login --device-auth` (native CLI) or `cc-openrouter openai/gpt-5.4`
(Claude Code with separate OpenRouter billing). The catalog entry carries
`disabled: true` so menus and dispatchers stop before auth or launch.

## Takeaway
Validate both credential scope and wire-protocol compatibility before building
an OAuth flow. When either is unsupported, fail with migration guidance instead
of completing a login that cannot produce a working session.

## References
- `lib/codex.ps1`
- `bash/lib/codex.sh`
- `docs/architecture.md`
- `ISSUES.md`
- https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/manager.rs
- https://github.com/openai/codex/issues/7144
