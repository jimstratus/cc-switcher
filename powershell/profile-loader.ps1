# Purpose: Load cc-switcher from PowerShell profiles without leaving commands unavailable.
# Usage: Dot-source this file from $PROFILE.
# Prerequisites: PowerShell 7 (`pwsh`) must be installed; Windows PowerShell 5 uses it as a child host.

$ccSwitcherRoot = Split-Path -Parent $PSScriptRoot
$ccSwitcherManifest = Join-Path $ccSwitcherRoot 'cc-switcher.psd1'

if (-not (Test-Path -LiteralPath $ccSwitcherManifest)) {
    throw "[cc-switcher] Module manifest not found at $ccSwitcherManifest"
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    # Keep profile startup quiet while importing eagerly so every cc-* command is
    # available in a fresh shell. Restore the caller's banner preference after.
    $previousBanner = $env:CC_BANNER
    try {
        $env:CC_BANNER = 'minimal'
        Import-Module $ccSwitcherManifest -Force -Global -ErrorAction Stop 3>$null 6>$null
    }
    finally {
        if ($null -eq $previousBanner) {
            Remove-Item Env:CC_BANNER -ErrorAction SilentlyContinue
        }
        else {
            $env:CC_BANNER = $previousBanner
        }
    }
    return
}

$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
$ccSwitcherRunner = Join-Path $PSScriptRoot 'invoke-cc-switcher.ps1'
$ccSwitcherManagedEnvironment = Join-Path $PSScriptRoot 'get-managed-environment.ps1'
$manifestData = Import-PowerShellDataFile $ccSwitcherManifest

foreach ($aliasName in $manifestData.AliasesToExport) {
    if ($aliasName -in @('cc-reset', 'cc-yolo')) { continue }
    if ($pwshCommand) {
        $pwshPath = $pwshCommand.Source
        $runnerPath = $ccSwitcherRunner
        $proxy = {
            # The module intentionally requires PowerShell 7. A child process is
            # safer than partially parsing PS7 source inside Windows PowerShell 5.
            # Serialize arguments into one opaque value so PowerShell's native
            # command parser cannot reinterpret Claude flags as runner params.
            $forwardArgs = @($args | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
            $argumentJson = ConvertTo-Json -InputObject @($forwardArgs) -Compress
            $encodedArguments = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($argumentJson)
            )
            & $pwshPath -NoLogo -NoProfile -File $runnerPath `
                -CommandName $MyInvocation.MyCommand.Name `
                -EncodedArguments $encodedArguments
        }.GetNewClosure()
    }
    else {
        $proxy = {
            throw '[cc-switcher] PowerShell 7 is required. Install pwsh and reopen this shell.'
        }
    }

    Set-Item -Path ("Function:\global:{0}" -f $aliasName) -Value $proxy -Force
}

if ($pwshCommand) {
    $pwshPath = $pwshCommand.Source
    $managedEnvironmentPath = $ccSwitcherManagedEnvironment
    $resetProxy = {
        [CmdletBinding()]
        param([switch]$Quiet)

        $managedNames = @(& $pwshPath -NoLogo -NoProfile -File $managedEnvironmentPath)
        if ($LASTEXITCODE -ne 0) {
            throw '[cc-switcher] PowerShell 7 could not resolve the managed environment list.'
        }
        foreach ($name in $managedNames) {
            Remove-Item -LiteralPath ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
        }
        if (-not $Quiet) {
            Write-Host '[cc] Provider overrides cleared. Native Anthropic restored.' -ForegroundColor Green
        }
    }.GetNewClosure()
}
else {
    $resetProxy = {
        throw '[cc-switcher] PowerShell 7 is required. Install pwsh and reopen this shell.'
    }
}
Set-Item -Path 'Function:\global:cc-reset' -Value $resetProxy -Force

if ($pwshCommand) {
    $pwshPath = $pwshCommand.Source
    $runnerPath = $ccSwitcherRunner
    $parentReset = $resetProxy
    $yoloProxy = {
        # Invoke-CC-Yolo resets before launching native Claude. In a PS5 proxy,
        # that reset must happen in this parent process, not only in child pwsh.
        & $parentReset -Quiet
        $forwardArgs = @($args | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        $argumentJson = ConvertTo-Json -InputObject @($forwardArgs) -Compress
        $encodedArguments = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($argumentJson)
        )
        & $pwshPath -NoLogo -NoProfile -File $runnerPath `
            -CommandName 'cc-yolo' `
            -EncodedArguments $encodedArguments
    }.GetNewClosure()
}
else {
    $yoloProxy = {
        throw '[cc-switcher] PowerShell 7 is required. Install pwsh and reopen this shell.'
    }
}
Set-Item -Path 'Function:\global:cc-yolo' -Value $yoloProxy -Force
