# =============================================================================
# core.ps1 — Invoke-CCLaunch
# Sets ANTHROPIC_* env vars, optionally launches `claude`, restores on exit.
# =============================================================================

function Invoke-CCLaunch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ProviderName,
        [Parameter(Mandatory)] [string]$BaseUrl,
        [Parameter(Mandatory)] [string]$AuthToken,
        [Parameter(Mandatory)] [string]$OpusModel,
        [Parameter(Mandatory)] [string]$SonnetModel,
        [Parameter(Mandatory)] [string]$HaikuModel,
        [int]$TimeoutMs = 3000000,
        [int]$FlagshipContext = 0,
        [switch]$DisableNonEssential,
        [hashtable]$ExtraEnv,
        [string[]]$ClaudeArgs
    )

    if ([string]::IsNullOrEmpty($AuthToken)) {
        Write-Host "[ERROR] Auth token is empty for provider: $ProviderName" -ForegroundColor Red
        Write-Host "        Set the relevant API key env var in your `$PROFILE." -ForegroundColor Red
        return
    }

    Write-Host "[cc] Launching: $ProviderName" -ForegroundColor Cyan
    Write-Host "[cc]   Opus   -> $OpusModel" -ForegroundColor DarkCyan
    Write-Host "[cc]   Sonnet -> $SonnetModel" -ForegroundColor DarkCyan
    Write-Host "[cc]   Haiku  -> $HaikuModel" -ForegroundColor DarkCyan
    Write-Host "[cc]   URL    -> $BaseUrl" -ForegroundColor DarkCyan

    # Snapshot every env var we touch so we can restore on exit
    $snapshot = @{
        ANTHROPIC_BASE_URL                          = $env:ANTHROPIC_BASE_URL
        ANTHROPIC_AUTH_TOKEN                        = $env:ANTHROPIC_AUTH_TOKEN
        ANTHROPIC_MODEL                             = $env:ANTHROPIC_MODEL
        ANTHROPIC_DEFAULT_OPUS_MODEL                = $env:ANTHROPIC_DEFAULT_OPUS_MODEL
        ANTHROPIC_DEFAULT_SONNET_MODEL              = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
        ANTHROPIC_DEFAULT_HAIKU_MODEL               = $env:ANTHROPIC_DEFAULT_HAIKU_MODEL
        ANTHROPIC_SMALL_FAST_MODEL                  = $env:ANTHROPIC_SMALL_FAST_MODEL
        API_TIMEOUT_MS                              = $env:API_TIMEOUT_MS
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC    = $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
        CLAUDE_CODE_MAX_OUTPUT_TOKENS               = $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS
        CLAUDE_CODE_MAX_CONTEXT_TOKENS              = $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS
        DISABLE_COMPACT                             = $env:DISABLE_COMPACT
    }
    if ($ExtraEnv) {
        foreach ($k in $ExtraEnv.Keys) {
            if (-not $snapshot.ContainsKey($k)) {
                $snapshot[$k] = [Environment]::GetEnvironmentVariable($k)
            }
        }
    }

    try {
        $env:ANTHROPIC_BASE_URL             = $BaseUrl
        $env:ANTHROPIC_AUTH_TOKEN           = $AuthToken
        $env:ANTHROPIC_MODEL                = $OpusModel
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $OpusModel
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $SonnetModel
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $HaikuModel
        $env:ANTHROPIC_SMALL_FAST_MODEL     = $HaikuModel
        $env:API_TIMEOUT_MS                 = "$TimeoutMs"
        if ($DisableNonEssential) {
            $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
        }

        # Auto-derive extended-context env vars when flagship tier is meaningfully larger than
        # Claude Code's 200K default. Threshold 500K cleanly separates 1M-class providers
        # (deepseek, mimo, qwen, xiaomi v2.5-pro) from sub-256K models where the gain from
        # losing auto-compact would be marginal. ExtraEnv applies AFTER this block, so a provider
        # can still override explicitly via providers.json envVars (or push a 256K provider in).
        if ($FlagshipContext -ge 500000) {
            $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$FlagshipContext"
            $env:DISABLE_COMPACT                = "1"
            $contextDisplay = if ($FlagshipContext -ge 1000000) {
                "{0:0.#}M" -f ($FlagshipContext / 1048576.0)
            } else {
                "{0}K" -f [int]($FlagshipContext / 1000)
            }
            Write-Host "[cc]   Context-> $contextDisplay (auto, DISABLE_COMPACT=1; /compact manually near limit)" -ForegroundColor DarkCyan
        }

        if ($ExtraEnv) {
            foreach ($k in $ExtraEnv.Keys) {
                [Environment]::SetEnvironmentVariable($k, $ExtraEnv[$k], 'Process')
            }
        }

        # --yolo shorthand → --dangerously-skip-permissions
        # Also honor global $env:CC_YOLO=1
        $yoloMode = $false
        if ($env:CC_YOLO -eq "1") { $yoloMode = $true }
        if ($ClaudeArgs) {
            $transformed = @()
            foreach ($arg in $ClaudeArgs) {
                if ($arg -eq '--yolo') {
                    $transformed += '--dangerously-skip-permissions'
                    $yoloMode = $true
                } else {
                    $transformed += $arg
                }
            }
            $ClaudeArgs = $transformed
        }
        if ($yoloMode) {
            Write-Host "[cc]   YOLO mode: --dangerously-skip-permissions" -ForegroundColor Yellow
            if ($ClaudeArgs -notcontains '--dangerously-skip-permissions') {
                $ClaudeArgs = @('--dangerously-skip-permissions') + @($ClaudeArgs)
            }
        }

        # Record session start for cc-usage
        $sessionStart = [DateTimeOffset]::Now
        if (Get-Command Write-CCSessionStart -ErrorAction SilentlyContinue) {
            Write-CCSessionStart -ProviderName $ProviderName -OpusModel $OpusModel
        }

        if ($ClaudeArgs.Count -gt 0) {
            & claude @ClaudeArgs
        } else {
            & claude
        }

        # Best-effort token aggregation after claude exits
        if (Get-Command Write-CCSessionEnd -ErrorAction SilentlyContinue) {
            Write-CCSessionEnd -ProviderName $ProviderName -StartedAt $sessionStart
        }
    }
    finally {
        foreach ($k in $snapshot.Keys) {
            [Environment]::SetEnvironmentVariable($k, $snapshot[$k], 'Process')
        }
    }
}

# Native Anthropic + YOLO (one-step launch with no env-var overrides)
function Invoke-CC-Yolo {
    param([string[]]$ClaudeArgs)
    Write-Host "[cc] Launching native Anthropic in YOLO mode" -ForegroundColor Yellow
    Reset-CC -Quiet
    $allArgs = @('--dangerously-skip-permissions') + @($ClaudeArgs)
    & claude @allArgs
}

# Clear all provider overrides; restores native Anthropic on next `claude`
function Reset-CC {
    [CmdletBinding()] param([switch]$Quiet)
    foreach ($var in @(
        'ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_MODEL',
        'ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL','ANTHROPIC_SMALL_FAST_MODEL',
        'API_TIMEOUT_MS','CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
        'CLAUDE_CODE_MAX_OUTPUT_TOKENS','CLAUDE_CODE_MAX_CONTEXT_TOKENS',
        'DISABLE_COMPACT'
    )) {
        [Environment]::SetEnvironmentVariable($var, $null, 'Process')
    }
    if (-not $Quiet) {
        Write-Host "[cc] Provider overrides cleared. Native Anthropic restored." -ForegroundColor Green
    }
}

# Status of current session env
function Get-CC-Status {
    $rows = @(
        @{ Name = 'ANTHROPIC_BASE_URL';             Val = $env:ANTHROPIC_BASE_URL }
        @{ Name = 'ANTHROPIC_MODEL';                Val = $env:ANTHROPIC_MODEL }
        @{ Name = 'ANTHROPIC_DEFAULT_OPUS_MODEL';   Val = $env:ANTHROPIC_DEFAULT_OPUS_MODEL }
        @{ Name = 'ANTHROPIC_DEFAULT_SONNET_MODEL'; Val = $env:ANTHROPIC_DEFAULT_SONNET_MODEL }
        @{ Name = 'ANTHROPIC_DEFAULT_HAIKU_MODEL';  Val = $env:ANTHROPIC_DEFAULT_HAIKU_MODEL }
        @{ Name = 'API_TIMEOUT_MS';                 Val = $env:API_TIMEOUT_MS }
        @{ Name = 'CLAUDE_CODE_MAX_CONTEXT_TOKENS'; Val = $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS }
        @{ Name = 'CLAUDE_CODE_MAX_OUTPUT_TOKENS';  Val = $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS }
        @{ Name = 'DISABLE_COMPACT';                Val = $env:DISABLE_COMPACT }
        @{ Name = 'CC_YOLO';                        Val = $env:CC_YOLO }
    )
    Write-Host ""
    Write-Host " cc-switcher status " -ForegroundColor Yellow
    Write-Host ("-" * 70) -ForegroundColor Yellow
    foreach ($r in $rows) {
        $val = if ([string]::IsNullOrEmpty($r.Val)) { "(unset — Anthropic default)" } else { $r.Val }
        Write-Host ("{0,-38} {1}" -f $r.Name, $val)
    }
    Write-Host ""
    Write-Host " API keys " -ForegroundColor Yellow
    Write-Host ("-" * 70) -ForegroundColor Yellow
    foreach ($keyName in @('ANTHROPIC_API_KEY','OPENROUTER_API_KEY','DEEPSEEK_API_KEY',
                            'MINIMAX_API_KEY','NVIDIA_API_KEY','OPENCODE_GO_API_KEY',
                            'ZAI_API_KEY','KIMI_API_KEY','XIAOMI_API_KEY','OLLAMA_API_KEY')) {
        $val = [Environment]::GetEnvironmentVariable($keyName)
        $status = if ([string]::IsNullOrEmpty($val)) { "(not set)" } else { "(set, len=$($val.Length))" }
        Write-Host ("{0,-22} {1}" -f $keyName, $status)
    }
    Write-Host ""
}
