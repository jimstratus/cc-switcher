# =============================================================================
# codex.ps1 — OpenAI Codex OAuth device flow + launcher
# Token cached at $env:USERPROFILE\.config\codex-oauth\token.json
# =============================================================================

$script:CodexTokenCachePath = Join-Path $env:USERPROFILE '.config\codex-oauth\token.json'

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

function Invoke-CC-Codex-Login {
    Write-Host "[cc-codex] OAuth device code flow..." -ForegroundColor Cyan
    try {
        $resp = Invoke-RestMethod -Uri "https://oauth.openai.com/v1/device_authorization" `
            -Method Post -ContentType "application/x-www-form-urlencoded" `
            -Body "client_id=chatbot&scope=platform"
        $deviceCode = $resp.device_code
        $userCode   = $resp.user_code
        $verifyUri  = $resp.verification_uri

        Write-Host "[cc-codex] URL:  $verifyUri" -ForegroundColor Cyan
        Write-Host "[cc-codex] Code: $userCode" -ForegroundColor Yellow
        Start-Process -FilePath $verifyUri

        $deadline = [DateTimeOffset]::Now.ToUnixTimeSeconds() + 120
        while ([DateTimeOffset]::Now.ToUnixTimeSeconds() -lt $deadline) {
            Start-Sleep -Seconds 5
            try {
                $tokenResp = Invoke-RestMethod -Uri "https://oauth.openai.com/v1/token" `
                    -Method Post -ContentType "application/x-www-form-urlencoded" `
                    -Body "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=$deviceCode&client_id=chatbot"
                if ($tokenResp.access_token) {
                    $cacheDir = Split-Path $script:CodexTokenCachePath -Parent
                    if (-not (Test-Path $cacheDir)) {
                        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                    }
                    $tokenResp | ConvertTo-Json | Set-Content $script:CodexTokenCachePath
                    Write-Host "[cc-codex] Login successful." -ForegroundColor Green
                    return
                }
            } catch {
                if ($_.Exception.Message -match "authorization_pending|pending") { continue }
                Write-Host "[cc-codex] Polling error: $($_.Exception.Message)" -ForegroundColor Yellow
                break
            }
        }
        Write-Host "[cc-codex] Timeout. Manual code: $userCode | URL: $verifyUri" -ForegroundColor Yellow
    } catch {
        Write-Host "[cc-codex] Login failed: $($_.Exception.Message)" -ForegroundColor Red
    }
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
    Invoke-CCProvider -Id 'codex' -ClaudeArgs $ClaudeArgs
}
