# Purpose: Verify fresh-shell cc-* availability in PowerShell 7 and Windows PowerShell 5.
# Usage: pwsh -NoProfile -File .\tests\profile-loader-smoke.ps1
# Prerequisites: PowerShell 7; run with powershell.exe as well on Windows.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$loaderPath = Join-Path $repoRoot 'powershell\profile-loader.ps1'
$bannerWasPresent = Test-Path Env:CC_BANNER
$previousBanner = $env:CC_BANNER

. $loaderPath

if ((Test-Path Env:CC_BANNER) -ne $bannerWasPresent -or $env:CC_BANNER -ne $previousBanner) {
    throw 'The profile loader did not preserve the caller CC_BANNER state.'
}

$manifestData = Import-PowerShellDataFile (Join-Path $repoRoot 'cc-switcher.psd1')
foreach ($aliasName in $manifestData.AliasesToExport) {
    Get-Command $aliasName -ErrorAction Stop | Out-Null
}

$miniMax = Get-Command cc-minimax -ErrorAction Stop
if ($PSVersionTable.PSVersion.Major -ge 7) {
    if ($miniMax.CommandType -ne 'Alias') {
        throw "Expected cc-minimax to be an alias in PowerShell 7, got $($miniMax.CommandType)."
    }
    & (Get-Module cc-switcher) {
        Get-Command Invoke-CCLaunch -ErrorAction Stop | Out-Null
    }
}
else {
    if ($miniMax.CommandType -ne 'Function') {
        throw "Expected cc-minimax to be a proxy function in Windows PowerShell, got $($miniMax.CommandType)."
    }
    $helpOutput = cc-help 6>&1 | Out-String
    if ($helpOutput -notmatch 'cc-minimax') {
        throw 'The PowerShell 5 proxy did not successfully run cc-help in PowerShell 7.'
    }

    $doctorOutput = cc-doctor -NoNetwork 6>&1 | Out-String
    if ($doctorOutput -notmatch 'Skipped network checks') {
        throw 'The PowerShell 5 proxy did not preserve the cc-doctor -NoNetwork switch.'
    }

    $mockBin = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-switcher-smoke-{0}" -f [guid]::NewGuid())
    $previousPath = $env:PATH
    $previousKey = $env:MINIMAX_API_KEY
    $previousOpenRouterKey = $env:OPENROUTER_API_KEY
    try {
        New-Item -ItemType Directory -Path $mockBin | Out-Null
        Set-Content -LiteralPath (Join-Path $mockBin 'claude.cmd') -Encoding Ascii -Value @(
            '@echo off'
            'echo [stub] claude invoked %*'
            'exit /b 0'
        )
        $env:PATH = "$mockBin;$previousPath"
        $env:MINIMAX_API_KEY = 'sk-test-profile-loader-1234567890'

        $launchOutput = cc-minimax -p -Verbose --profile-smoke 6>&1 | Out-String
        if ($launchOutput -notmatch '\[stub\] claude invoked -p -Verbose --profile-smoke') {
            throw 'The PowerShell 5 proxy did not preserve Claude-style flags as raw arguments.'
        }

        $env:OPENROUTER_API_KEY = 'sk-or-test-profile-loader-1234567890'
        $modelLaunchOutput = cc-openrouter 'review/model' -p --model-smoke 6>&1 | Out-String
        if ($modelLaunchOutput -notmatch 'OpenRouter model: review/model' -or
            $modelLaunchOutput -notmatch '\[stub\] claude invoked -p --model-smoke') {
            throw 'The PowerShell 5 proxy did not preserve model-plus-Claude argument semantics.'
        }
    }
    finally {
        $env:PATH = $previousPath
        foreach ($keyState in @(
            @{ Name = 'MINIMAX_API_KEY'; Value = $previousKey },
            @{ Name = 'OPENROUTER_API_KEY'; Value = $previousOpenRouterKey }
        )) {
            if ($null -eq $keyState.Value) {
                Remove-Item -LiteralPath ("Env:{0}" -f $keyState.Name) -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($keyState.Name, $keyState.Value, 'Process')
            }
        }
        Remove-Item -LiteralPath $mockBin -Recurse -Force -ErrorAction SilentlyContinue
    }

    $resetNames = @('ANTHROPIC_BASE_URL', 'ANTHROPIC_MODEL', 'CLAUDE_CODE_SUBAGENT_MODEL', 'ENABLE_TOOL_SEARCH')
    $resetSnapshot = @{}
    foreach ($name in $resetNames) {
        $resetSnapshot[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    try {
        $env:ANTHROPIC_BASE_URL = 'ps5-parent-base'
        $env:CLAUDE_CODE_SUBAGENT_MODEL = 'ps5-parent-subagent'
        $env:ENABLE_TOOL_SEARCH = 'true'
        cc-reset -Quiet
        foreach ($name in @('ANTHROPIC_BASE_URL', 'CLAUDE_CODE_SUBAGENT_MODEL', 'ENABLE_TOOL_SEARCH')) {
            if (Test-Path -LiteralPath ("Env:{0}" -f $name)) {
                throw "The PowerShell 5 cc-reset proxy did not clear $name in its parent shell."
            }
        }

        $env:ANTHROPIC_MODEL = 'ps5-parent-model'
        $resetOutput = cc-reset 6>&1 | Out-String
        if ((Test-Path Env:ANTHROPIC_MODEL) -or $resetOutput -notmatch 'Native Anthropic restored') {
            throw 'The zero-argument PowerShell 5 cc-reset proxy failed.'
        }

        $env:ANTHROPIC_BASE_URL = 'ps5-parent-yolo-base'
        $env:CLAUDE_CODE_SUBAGENT_MODEL = 'ps5-parent-yolo-subagent'
        # The earlier launch block has already removed its temporary claude.cmd.
        # This assertion targets the parent-shell reset contract, not child launch output.
        cc-yolo --profile-yolo 6>&1 | Out-Null
        if ((Test-Path Env:ANTHROPIC_BASE_URL) -or (Test-Path Env:CLAUDE_CODE_SUBAGENT_MODEL)) {
            throw 'The PowerShell 5 cc-yolo proxy did not reset its parent environment before launch.'
        }
    }
    finally {
        foreach ($name in $resetNames) {
            if ($null -eq $resetSnapshot[$name]) {
                Remove-Item -LiteralPath ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $resetSnapshot[$name], 'Process')
            }
        }
    }
}

Write-Output "PASS: profile loader under PowerShell $($PSVersionTable.PSVersion)"
