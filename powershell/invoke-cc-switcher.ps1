# Purpose: Run one exported cc-switcher command in PowerShell 7 for a PS5 profile proxy.
# Usage: pwsh -NoProfile -File .\invoke-cc-switcher.ps1 -CommandName cc-help [arguments]
# Prerequisites: PowerShell 7 and the cc-switcher module in the parent directory.

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CommandName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$CommandArgs
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

Get-Command $CommandName -CommandType Alias -ErrorAction Stop | Out-Null
$invocationTokens = @('&', ("'{0}'" -f $CommandName.Replace("'", "''")))
foreach ($argument in @($CommandArgs)) {
    if ($null -eq $argument) { continue }
    $text = [string]$argument
    if ($text -match '^-[A-Za-z][A-Za-z0-9]*$') {
        # Only a strict parameter-name token is emitted as syntax. Everything
        # else is single-quoted below, so user data cannot become code.
        $invocationTokens += $text
    }
    else {
        $invocationTokens += ("'{0}'" -f $text.Replace("'", "''"))
    }
}

$invocation = [scriptblock]::Create($invocationTokens -join ' ')
& $invocation

if ($LASTEXITCODE -is [int]) {
    exit $LASTEXITCODE
}
