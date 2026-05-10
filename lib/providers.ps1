# =============================================================================
# providers.ps1 — Loads providers.json and generates wrapper functions
# =============================================================================

$script:CCCatalogPath = Join-Path $script:CCSwitcherRoot 'data\providers.json'
$script:CCCatalog = $null

function Get-CCCatalog {
    if ($null -ne $script:CCCatalog) { return $script:CCCatalog }
    if (-not (Test-Path $script:CCCatalogPath)) {
        throw "Provider catalog not found at $script:CCCatalogPath"
    }
    $script:CCCatalog = Get-Content $script:CCCatalogPath -Raw | ConvertFrom-Json
    return $script:CCCatalog
}

function Get-CCProviders {
    $cat = Get-CCCatalog
    $list = @()
    foreach ($key in $cat.providers.PSObject.Properties.Name) {
        $p = $cat.providers.$key
        $list += [pscustomobject]@{
            Id           = $key
            Command      = $p.command
            DisplayName  = $p.displayName
            QualityTier  = $p.qualityTier
            BaseUrl      = $p.baseUrl
            AuthVar      = $p.authVar
            Flagship     = $p.tiers.flagship
            Standard     = $p.tiers.standard
            Fast         = $p.tiers.fast
            Context      = $p.context
            ContextByTier= $p.contextByTier
            TimeoutMs    = $p.timeoutMs
            DisableNonEss= $p.disableNonEssential
            ExtraEnv     = $p.envVars
            RequiresOAuth= $p.requiresOAuth
            Notes        = $p.notes
            Docs         = $p.docs
        }
    }
    return $list
}

# Single dispatcher for catalog-driven providers
function Invoke-CCProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Id,
        [string]$ModelOverride,
        [string[]]$ClaudeArgs
    )
    $providers = Get-CCProviders
    $p = $providers | Where-Object Id -eq $Id | Select-Object -First 1
    if (-not $p) { Write-Host "[ERROR] Unknown provider id: $Id" -ForegroundColor Red; return }

    if ($p.RequiresOAuth) {
        $token = Get-CC-CodexToken
        if ([string]::IsNullOrEmpty($token)) {
            Write-Host "[ERROR] OAuth token missing. Run 'cc-codex-login' first." -ForegroundColor Red
            return
        }
        $authToken = $token
    } else {
        $authToken = [Environment]::GetEnvironmentVariable($p.AuthVar)
    }

    # Translate semantic tier names → Claude Code's env-var contract:
    # flagship → ANTHROPIC_DEFAULT_OPUS_MODEL  (selected by /model opus)
    # standard → ANTHROPIC_DEFAULT_SONNET_MODEL (/model sonnet)
    # fast     → ANTHROPIC_DEFAULT_HAIKU_MODEL  (/model haiku)
    $opus   = if ($ModelOverride) { $ModelOverride } else { $p.Flagship }
    $sonnet = if ($ModelOverride) { $ModelOverride } else { $p.Standard }
    $haiku  = if ($ModelOverride) { $ModelOverride } else { $p.Fast }

    $extraEnv = @{}
    if ($p.ExtraEnv) {
        foreach ($k in $p.ExtraEnv.PSObject.Properties.Name) {
            $extraEnv[$k] = $p.ExtraEnv.$k
        }
    }

    # Resolve flagship-tier context for auto-derived CLAUDE_CODE_MAX_CONTEXT_TOKENS.
    # Prefer per-tier override (contextByTier.flagship), fall back to uniform context field.
    $flagshipContext = 0
    if ($p.ContextByTier -and $p.ContextByTier.flagship) {
        $flagshipContext = [int]$p.ContextByTier.flagship
    } elseif ($p.Context) {
        $flagshipContext = [int]$p.Context
    }

    Invoke-CCLaunch `
        -ProviderName ($p.DisplayName) `
        -BaseUrl ($p.BaseUrl) `
        -AuthToken $authToken `
        -OpusModel $opus -SonnetModel $sonnet -HaikuModel $haiku `
        -TimeoutMs ($p.TimeoutMs) `
        -FlagshipContext $flagshipContext `
        -DisableNonEssential:([bool]$p.DisableNonEss) `
        -ExtraEnv $extraEnv `
        -ClaudeArgs $ClaudeArgs
}

# Public wrappers — thin adapters with consistent param signature
function Invoke-CC-DeepSeek    { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'deepseek' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-Glm         { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'glm' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-Kimi        { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'kimi' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-MiniMax     { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'minimax' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-MiMo        { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'mimo' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-Qwen        { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'qwen' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-Xiaomi      { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'xiaomi' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-ZAI-GLM51   { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'zai-glm51' -ClaudeArgs $ClaudeArgs }
function Invoke-CC-OpenCode-MiniMax { param([string[]]$ClaudeArgs) Invoke-CCProvider -Id 'opencode-minimax' -ClaudeArgs $ClaudeArgs }

# NVIDIA: tier mapping by default, optional model override
function Invoke-CC-Nvidia {
    param([string]$Model, [string[]]$ClaudeArgs)
    if ($Model) {
        Invoke-CCProvider -Id 'nvidia' -ModelOverride $Model -ClaudeArgs $ClaudeArgs
    } else {
        Invoke-CCProvider -Id 'nvidia' -ClaudeArgs $ClaudeArgs
    }
}

# OpenRouter: model param required (passes through to all three tiers)
function Invoke-CC-OpenRouter {
    param([string]$Model, [string[]]$ClaudeArgs)
    if (-not $Model) { $Model = "moonshotai/kimi-k2.6" }
    $auth = $env:OPENROUTER_API_KEY
    Write-Host "[cc] OpenRouter model: $Model" -ForegroundColor Yellow
    Invoke-CCLaunch `
        -ProviderName "OpenRouter ($Model)" `
        -BaseUrl "https://openrouter.ai/api/v1" -AuthToken $auth `
        -OpusModel $Model -SonnetModel $Model -HaikuModel $Model `
        -ClaudeArgs $ClaudeArgs
}

# OpenCode Go generic: pass any model
function Invoke-CC-OpenCode {
    param([string]$Model, [string[]]$ClaudeArgs)
    if (-not $Model) { $Model = "minimax-m2.7" }
    $auth = $env:OPENCODE_GO_API_KEY
    Write-Host "[cc] OpenCode Go model: $Model" -ForegroundColor Yellow
    Invoke-CCLaunch `
        -ProviderName "OpenCode Go ($Model)" `
        -BaseUrl "https://opencode.ai/zen/go" -AuthToken $auth `
        -OpusModel $Model -SonnetModel $Model -HaikuModel $Model `
        -DisableNonEssential `
        -ClaudeArgs $ClaudeArgs
}
