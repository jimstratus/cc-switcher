# Purpose: Verify the Muse catalog mapping, extra environment, and restoration contract.
# Usage: pwsh -NoProfile -File .\tests\muse-provider-smoke.ps1
# Prerequisites: PowerShell 7 and the repository catalog.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'cc-switcher.psd1'
$managedNames = @(
    'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL', 'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL', 'ANTHROPIC_SMALL_FAST_MODEL',
    'API_TIMEOUT_MS', 'CLAUDE_CODE_MAX_CONTEXT_TOKENS', 'CLAUDE_CODE_SUBAGENT_MODEL', 'ENABLE_TOOL_SEARCH',
    'MODEL_API_KEY', 'CC_BANNER'
)
$snapshot = @{}
foreach ($name in $managedNames) {
    $snapshot[$name] = [Environment]::GetEnvironmentVariable($name)
}

try {
    $env:CC_BANNER = 'minimal'
    $env:MODEL_API_KEY = 'sk-test-muse-1234567890'
    $env:ANTHROPIC_BASE_URL = 'original-base-url'
    $env:CLAUDE_CODE_SUBAGENT_MODEL = 'original-subagent'
    Remove-Item Env:CLAUDE_CODE_MAX_CONTEXT_TOKENS -ErrorAction SilentlyContinue
    Remove-Item Env:ENABLE_TOOL_SEARCH -ErrorAction SilentlyContinue

    function global:claude {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$Arguments
        )
        $global:CCMuseSmokeCaptured = @{
            BaseUrl       = $env:ANTHROPIC_BASE_URL
            AuthToken     = $env:ANTHROPIC_AUTH_TOKEN
            Model         = $env:ANTHROPIC_MODEL
            Opus          = $env:ANTHROPIC_DEFAULT_OPUS_MODEL
            Sonnet        = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
            Haiku         = $env:ANTHROPIC_DEFAULT_HAIKU_MODEL
            Context       = $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS
            SubagentModel = $env:CLAUDE_CODE_SUBAGENT_MODEL
            ToolSearch    = $env:ENABLE_TOOL_SEARCH
            Arguments     = @($Arguments)
        }
    }

    Import-Module $manifestPath -Force
    cc-muse '--muse-smoke'

    $captured = $global:CCMuseSmokeCaptured
    if ($captured.BaseUrl -ne 'https://api.meta.ai') { throw 'Muse base URL was not applied.' }
    if ($captured.AuthToken -ne $env:MODEL_API_KEY) { throw 'MODEL_API_KEY was not used.' }
    foreach ($slot in @('Model', 'Opus', 'Sonnet', 'Haiku', 'SubagentModel')) {
        if ($captured[$slot] -ne 'muse-spark-1.2') { throw "Muse mapping failed for $slot." }
    }
    if ($captured.ToolSearch -ne 'true') { throw 'ENABLE_TOOL_SEARCH was not enabled.' }
    if ($null -ne $captured.Context) { throw 'Muse must retain Claude Code auto-compaction until its context window is verified.' }
    if ($captured.Arguments -notcontains '--muse-smoke') { throw 'Claude arguments were not forwarded.' }
    if ($env:ANTHROPIC_BASE_URL -ne 'original-base-url') { throw 'Base URL was not restored.' }
    if ($env:CLAUDE_CODE_SUBAGENT_MODEL -ne 'original-subagent') { throw 'Subagent model was not restored.' }
    $toolSearchAfter = [Environment]::GetEnvironmentVariable('ENABLE_TOOL_SEARCH')
    if ($null -ne $toolSearchAfter) { throw "Tool search setting leaked after launch: '$toolSearchAfter'." }

    Write-Output 'PASS: PowerShell Muse provider mapping and restore'
}
finally {
    Remove-Module cc-switcher -ErrorAction SilentlyContinue
    Remove-Item Function:\global:claude -ErrorAction SilentlyContinue
    Remove-Variable CCMuseSmokeCaptured -Scope Global -ErrorAction SilentlyContinue
    foreach ($name in $managedNames) {
        if ($null -eq $snapshot[$name]) {
            Remove-Item -LiteralPath ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $snapshot[$name], 'Process')
        }
    }
}
