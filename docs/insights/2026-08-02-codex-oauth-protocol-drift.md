# Codex OAuth Protocol Drift
Date: 2026-08-02
Project: cc-switcher
Tags: codex, oauth, device-flow, app-server, protocol-bridge, powershell, bash

## Context
`cc-codex-login` failed before displaying a device code with HTTP 403. We needed
to determine whether the failure was account-specific or caused by the client.

## What we tried
1. Traced the PowerShell and bash implementations and their token-cache readers.
2. Compared their requests with the current official `openai/codex` login source.
3. Checked the project history and CI coverage for prior end-to-end validation.
4. Compared the Codex CLI app-server protocol with Claude Code's Anthropic
   Messages HTTP contract.
5. Inspected the current OpenClaw and Hermes Agent Codex integrations to verify
   how working third-party ChatGPT OAuth clients route requests.

## What happened
Both implementations use the retired `oauth.openai.com/v1/device_authorization`
and `/v1/token` endpoints with form data and `client_id=chatbot`. Current Codex
uses JSON device-auth requests under `auth.openai.com/api/accounts/deviceauth`,
then exchanges the returned authorization code and PKCE verifier at
`auth.openai.com/oauth/token`. The PowerShell implementation also writes the raw
token response without deriving the absolute `expires_at` required by its own
cache reader.

PR #23 subsequently retired the broken integration. That was a safe failure
mode, but it was not a repair. OpenClaw and Hermes demonstrate that third-party
ChatGPT OAuth-backed Codex integrations are viable when they use a Codex-specific
transport. OpenClaw can use `codex app-server` or a direct Codex Responses
transport; Hermes implements both patterns. Neither sends Anthropic Messages to
the public OpenAI API.

## Root cause / why
The immediate 403 came from an obsolete device-flow request, not a bad ChatGPT
account or a general ban on third-party OAuth. The old launch path had a separate
transport defect: it pointed Claude Code's Anthropic Messages client at the
public OpenAI API. A ChatGPT OAuth token not being a public Platform API key does
not make third-party Codex OAuth unsupported; it means the client must use a
Codex transport.

The supported credential owner for cc-switcher should be the installed Codex
CLI (`codex login --device-auth`). Its app-server exposes stateful JSONL/JSON-RPC,
not an Anthropic-compatible HTTP endpoint. Preserving cc-switcher's promise that
`cc-*` launches Claude Code therefore requires a resident Anthropic
Messages-to-Codex adapter. A cross-platform listener cannot be implemented in
the existing PowerShell/Bash scripts with only their allowed dependencies, so
the project must approve either a runtime prerequisite or shipped native bridge
executables before implementation.

## Takeaway
Treat authentication and transport as separate contracts. Delegate authentication
to Codex, never copy its token cache, and translate Claude Code traffic through a
tested local bridge. Do not infer that Codex OAuth itself is unsupported merely
because its token cannot be used as a public API key.

## References
- `lib/codex.ps1`
- `bash/lib/codex.sh`
- `docs/architecture.md`
- `ISSUES.md`
- https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/manager.rs
- https://github.com/openai/codex/issues/7144
- https://learn.chatgpt.com/docs/auth
- https://learn.chatgpt.com/docs/app-server
- https://docs.openclaw.ai/providers/openai
- https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md
- https://github.com/jimstratus/cc-switcher/pull/23
- https://github.com/jimstratus/cc-switcher/issues/24
