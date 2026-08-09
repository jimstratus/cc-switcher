# =============================================================================
# codex.ps1 — Unsupported direct Codex guard + legacy token-cache cleanup
# Historical token cache: <user profile>/.config/codex-oauth/token.json
# =============================================================================

# USERPROFILE is Windows-specific and is unset on Linux CI. Ask .NET for the
# cross-platform user profile so importing the module never depends on a shell-
# specific environment variable.
$codexUserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$script:CodexTokenCachePath = Join-Path `
    (Join-Path (Join-Path $codexUserProfile '.config') 'codex-oauth') `
    'token.json'

function Get-CC-CodexToken {
    if (-not (Test-Path $script:CodexTokenCachePath)) { return $null }
    try {
        $cached = Get-Content $script:CodexTokenCachePath -Raw | ConvertFrom-Json
        if ($cached.access_token -and $cached.expires_at -gt [DateTimeOffset]::Now.ToUnixTimeSeconds()) {
            return $cached.access_token
        }
    } catch {}
    return $null
}

function Show-CCCodexUnsupported {
    Write-Host "[ERROR] Direct ChatGPT OAuth cannot be used as a Claude Code provider." -ForegroundColor Red
    Write-Host "        ChatGPT OAuth tokens do not authenticate api.openai.com, and that API" -ForegroundColor Yellow
    Write-Host "        does not implement Claude Code's Anthropic Messages protocol." -ForegroundColor Yellow
    Write-Host "        For native Codex: codex login --device-auth" -ForegroundColor Cyan
    Write-Host "        For GPT via Claude Code: cc-openrouter openai/gpt-5.4" -ForegroundColor Cyan
    throw "[cc-codex] Unsupported direct OAuth integration; no launch was attempted."
}

function Invoke-CC-Codex-Login {
    # Do not run the otherwise valid Codex device flow here: its token is scoped
    # to Codex's ChatGPT backend and cannot make this launcher's transport work.
    Show-CCCodexUnsupported
}

function Invoke-CC-Codex-Logout {
    if (Test-Path $script:CodexTokenCachePath) {
        Remove-Item $script:CodexTokenCachePath -Force
        Write-Host "[cc-codex] Logged out." -ForegroundColor Green
    } else {
        Write-Host "[cc-codex] No cached token." -ForegroundColor Yellow
    }
}

function Invoke-CC-Codex {
    param([string[]]$ClaudeArgs)
    Show-CCCodexUnsupported
}
