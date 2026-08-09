# Purpose: Run one exported cc-switcher command in PowerShell 7 for a PS5 profile proxy.
# Usage: pwsh -NoProfile -File .\invoke-cc-switcher.ps1 -CommandName cc-help -EncodedArguments <base64-json>
# Prerequisites: PowerShell 7 and the cc-switcher module in the parent directory.

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CommandName,

    [Parameter(Mandatory)]
    [string]$EncodedArguments
)

$ErrorActionPreference = 'Stop'
$ccSwitcherRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $ccSwitcherRoot 'cc-switcher.psd1'
$manifestData = Import-PowerShellDataFile $manifestPath

if ($manifestData.AliasesToExport -notcontains $CommandName) {
    throw "[cc-switcher] Refusing to invoke unexported command: $CommandName"
}

$env:CC_BANNER = 'minimal'
Import-Module $manifestPath -Force -ErrorAction Stop 3>$null 6>$null

$exportedAlias = Get-Command $CommandName -CommandType Alias -ErrorAction Stop
$targetParameterNames = @($exportedAlias.ResolvedCommand.Parameters.Keys)
$argumentJson = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($EncodedArguments)
)
$CommandArgs = @($argumentJson | ConvertFrom-Json)

if ($targetParameterNames -contains 'ClaudeArgs') {
    # Provider wrappers expose ClaudeArgs as a string array. Splat the complete
    # array explicitly so multiple dash-prefixed CLI flags remain raw data.
    $providerArgs = @($CommandArgs | ForEach-Object { [string]$_ })
    $invokeParameters = @{}
    if ($targetParameterNames -contains 'Model' -and
        $providerArgs.Count -gt 0 -and
        -not $providerArgs[0].StartsWith('-')) {
        $invokeParameters.Model = $providerArgs[0]
        $providerArgs = @($providerArgs | Select-Object -Skip 1)
    }
    $invokeParameters.ClaudeArgs = [string[]]$providerArgs
    & $CommandName @invokeParameters
}
else {
    $invocationTokens = @('&', ("'{0}'" -f $CommandName.Replace("'", "''")))
    foreach ($argument in @($CommandArgs)) {
        if ($null -eq $argument) { continue }
        $text = [string]$argument
        if ($text -match '^-(?<Name>[A-Za-z][A-Za-z0-9]*)$' -and
            $targetParameterNames -contains $Matches.Name) {
            # Only parameters actually declared by the resolved utility command
            # become syntax. Unknown flags remain quoted data.
            $invocationTokens += $text
        }
        else {
            $invocationTokens += ("'{0}'" -f $text.Replace("'", "''"))
        }
    }

    $invocation = [scriptblock]::Create($invocationTokens -join ' ')
    & $invocation
}

if ($LASTEXITCODE -is [int]) {
    exit $LASTEXITCODE
}
