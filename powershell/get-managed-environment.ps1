# Purpose: Emit cc-switcher's managed environment names for the Windows PowerShell reset proxy.
# Usage: pwsh -NoProfile -File .\get-managed-environment.ps1
# Prerequisites: PowerShell 7 and the cc-switcher module in the parent directory.

$ErrorActionPreference = 'Stop'
$ccSwitcherRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $ccSwitcherRoot 'cc-switcher.psd1'

$env:CC_BANNER = 'minimal'
Import-Module $manifestPath -Force -ErrorAction Stop 3>$null 6>$null
Get-CCManagedEnvironmentNames
