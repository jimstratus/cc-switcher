# =============================================================================
# cc-switcher.psm1 — Claude Code multi-provider launcher
# Version 3.3.1 — single source of truth: $script:CCSwitcherVersion below.
# Repo: https://github.com/jimstratus/cc-switcher
# =============================================================================

$script:CCSwitcherRoot = $PSScriptRoot
$script:CCSwitcherVersion = '3.3.1'

# Load lib files in dependency order. Tiny files — total parse <50ms.
. (Join-Path $PSScriptRoot 'lib\core.ps1')
. (Join-Path $PSScriptRoot 'lib\providers.ps1')
. (Join-Path $PSScriptRoot 'lib\codex.ps1')
. (Join-Path $PSScriptRoot 'lib\pricing.ps1')
. (Join-Path $PSScriptRoot 'lib\doctor.ps1')
. (Join-Path $PSScriptRoot 'lib\completers.ps1')
. (Join-Path $PSScriptRoot 'lib\usage.ps1')
. (Join-Path $PSScriptRoot 'lib\picker.ps1')
. (Join-Path $PSScriptRoot 'lib\update-check.ps1')

# Tab completion for model parameters
Register-CCCompleters

# Public command aliases (alphabetical, slow last)
Set-Alias -Name cc-deepseek          -Value Invoke-CC-DeepSeek
Set-Alias -Name cc-glm               -Value Invoke-CC-Glm
Set-Alias -Name cc-kimi              -Value Invoke-CC-Kimi
Set-Alias -Name cc-minimax           -Value Invoke-CC-MiniMax
Set-Alias -Name cc-mimo              -Value Invoke-CC-MiMo
Set-Alias -Name cc-nemotron          -Value Invoke-CC-Nemotron
Set-Alias -Name cc-nvidia            -Value Invoke-CC-Nvidia
Set-Alias -Name cc-qwen              -Value Invoke-CC-Qwen
Set-Alias -Name cc-xiaomi            -Value Invoke-CC-Xiaomi
Set-Alias -Name cc-codex             -Value Invoke-CC-Codex
Set-Alias -Name cc-codex-login       -Value Invoke-CC-Codex-Login
Set-Alias -Name cc-codex-logout      -Value Invoke-CC-Codex-Logout
Set-Alias -Name cc-opencode          -Value Invoke-CC-OpenCode
Set-Alias -Name cc-opencode-minimax  -Value Invoke-CC-OpenCode-MiniMax
Set-Alias -Name cc-openrouter        -Value Invoke-CC-OpenRouter
Set-Alias -Name cc-owl               -Value Invoke-CC-Owl-Alpha
Set-Alias -Name cc-zai-glm51         -Value Invoke-CC-ZAI-GLM51
Set-Alias -Name cc-gemini            -Value Invoke-CC-Gemini
Set-Alias -Name cc-grok              -Value Invoke-CC-Grok
Set-Alias -Name cc-minimax-or        -Value Invoke-CC-MiniMax-OR
Set-Alias -Name cc-ollama-glm        -Value Invoke-CC-Ollama-Glm
Set-Alias -Name cc-ollama-minimax    -Value Invoke-CC-Ollama-MiniMax

# Utility commands
Set-Alias -Name cc-launch    -Value Invoke-CC-Launch-Menu
Set-Alias -Name cc-pick      -Value Invoke-CC-Pick
Set-Alias -Name cc-doctor    -Value Invoke-CC-Doctor
Set-Alias -Name cc-pricing   -Value Get-CCPricing
Set-Alias -Name cc-status    -Value Get-CC-Status
Set-Alias -Name cc-usage     -Value Get-CCUsage
Set-Alias -Name cc-reset     -Value Reset-CC
Set-Alias -Name cc-yolo      -Value Invoke-CC-Yolo
Set-Alias -Name cc-help      -Value Show-CCHelp

function Show-CCHelp {
    Write-Host ""
    Write-Host " cc-switcher v$script:CCSwitcherVersion " -ForegroundColor Magenta
    Write-Host ("=" * 78) -ForegroundColor Magenta
    Write-Host ""
    Write-Host " Providers (alphabetical, /model switches tiers in-session) " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    Get-CCProviders | Sort-Object @{
        Expression = { if ($_.QualityTier -eq 'slow') { 'zzz_' + $_.Command } else { $_.Command } }
    } | ForEach-Object {
        $tier = $_.QualityTier
        $tag = switch ($tier) {
            'flagship' { '          ' }
            'free'     { '   [free] ' }
            'slow'     { '   [SLOW] ' }
            default    { ('   [{0}] ' -f $tier) }
        }
        Write-Host ("  {0,-22}{1}{2}" -f $_.Command, $tag, $_.DisplayName)
    }
    Write-Host ""
    Write-Host " Generic launchers (pass model id) " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    Write-Host "  cc-openrouter <model>          Any OpenRouter model"
    Write-Host "  cc-opencode <model>            Any OpenCode Go model"
    Write-Host "  cc-nvidia <model>              Any NVIDIA NIM model (omit for tier defaults)"
    Write-Host ""
    Write-Host " Utilities " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    Write-Host "  cc-launch     Interactive numbered menu"
    Write-Host "  cc-pick       Searchable grid view (requires Microsoft.PowerShell.ConsoleGuiTools)"
    Write-Host "  cc-doctor     Validate API keys + ping endpoints"
    Write-Host "  cc-pricing    Live pricing table (OpenRouter, 5-min cache)"
    Write-Host "  cc-status     Show current provider env state"
    Write-Host "  cc-usage      Token usage history (last 20 sessions)"
    Write-Host "  cc-reset      Clear overrides, restore native Anthropic"
    Write-Host "  cc-yolo       Native Anthropic + --dangerously-skip-permissions"
    Write-Host ""
    Write-Host " Flags " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    Write-Host "  --yolo                   Add to any command for --dangerously-skip-permissions"
    Write-Host "  `$env:CC_YOLO=1            Auto-applies --yolo to every cc-* launch"
    Write-Host ""
    Write-Host " Files " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    Write-Host "  Catalog:  $($script:CCSwitcherRoot)\data\providers.json"
    Write-Host "  Issues:   $($script:CCSwitcherRoot)\ISSUES.md"
    Write-Host ""
}

# Load-time banner — modes: minimal | compact | full (default)
# Override per-shell with: $env:CC_BANNER = 'minimal' | 'compact' | 'full'
$script:_ccUpdated = Test-CCUpdated
$updateFlag = if ($script:_ccUpdated) { ' [updated since last shell]' } else { '' }
$bannerMode = if ($env:CC_BANNER) { $env:CC_BANNER.ToLower() } else { 'full' }

switch ($bannerMode) {
    'minimal' {
        Write-Host "[cc-switcher v$script:CCSwitcherVersion loaded — type cc-help]$updateFlag" -ForegroundColor DarkCyan
    }
    'full' {
        Show-CCHelp
        if ($updateFlag) { Write-Host "[cc-switcher$updateFlag]" -ForegroundColor Yellow }
    }
    default {
        # compact: header + 3 lines of command names, dynamically generated
        Write-Host "[cc-switcher v$script:CCSwitcherVersion — cc-help for details]$updateFlag" -ForegroundColor DarkCyan
        $providerCmds = Get-CCProviders | Sort-Object @{
            Expression = { if ($_.QualityTier -eq 'slow') { 'zzz_' + $_.Command } else { $_.Command } }
        } | ForEach-Object {
            $cmd = $_.Command
            $tier = $_.QualityTier
            switch ($tier) {
                'slow' { "$cmd[slow]" }
                'free' { "$cmd[free]" }
                default { $cmd }
            }
        }
        Write-Host ("  Providers: {0}" -f ($providerCmds -join ' ')) -ForegroundColor DarkGray
        Write-Host "  Generic:   cc-openrouter <model>  cc-opencode <model>  cc-nvidia <model>" -ForegroundColor DarkGray
        Write-Host "  Utility:   cc-launch cc-pick cc-doctor cc-pricing cc-status cc-usage cc-reset cc-yolo cc-help" -ForegroundColor DarkGray
    }
}

Export-ModuleMember -Function * -Alias *
