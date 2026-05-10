# =============================================================================
# picker.ps1 — Interactive provider picker (cc-launch + cc-pick)
# cc-launch: numbered menu (no extra deps)
# cc-pick:   Out-ConsoleGridView if available, else falls back to cc-launch
# =============================================================================

function Invoke-CC-Launch-Menu {
    $providers = Get-CCProviders | Sort-Object @{ Expression = {
        # Slow tier always last; otherwise alphabetical
        if ($_.QualityTier -eq 'slow') { 'zzz_' + $_.Command } else { $_.Command }
    }}

    Write-Host ""
    Write-Host " cc-switcher launcher " -ForegroundColor Magenta
    Write-Host ("=" * 78) -ForegroundColor Magenta
    Write-Host ""

    $i = 1
    $idMap = @{}
    foreach ($p in $providers) {
        # Context display: range when tiers differ ("256K-1024K"), else single ("1000K")
        $context = "         "
        if ($p.ContextByTier) {
            $vals = @($p.ContextByTier.flagship, $p.ContextByTier.standard, $p.ContextByTier.fast) | Where-Object { $_ }
            $minK = [int](($vals | Measure-Object -Minimum).Minimum / 1000)
            $maxK = [int](($vals | Measure-Object -Maximum).Maximum / 1000)
            if ($minK -ne $maxK) {
                $context = "{0,4}-{1,-4}K" -f $minK, $maxK
            } else {
                $context = "{0,5}K   " -f $minK
            }
        } elseif ($p.Context) {
            $context = "{0,5}K   " -f ([int]($p.Context / 1000))
        }
        $tag = switch ($p.QualityTier) {
            'flagship' { '' }
            'free'     { '[free]' }
            'slow'     { '[SLOW]' }
            default    { '[' + $p.QualityTier + ']' }
        }
        Write-Host ("  [{0,2}] {1,-22} {2,12} {3,-50} {4}" -f $i, $p.Command, $context, $p.DisplayName, $tag)
        $idMap["$i"] = $p.Id
        $i++
    }
    Write-Host ""
    Write-Host "  [P]  Pricing table     [D]  Doctor     [U]  Usage" -ForegroundColor Cyan
    Write-Host "  [O]  Custom OpenRouter model     [N]  Custom NVIDIA model" -ForegroundColor Cyan
    Write-Host "  [R]  Reset (back to native Anthropic)         [Q]  Quit" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "Select"
    switch -Regex ($choice) {
        '^\d+$' {
            if ($idMap.ContainsKey($choice)) { Invoke-CCProvider -Id $idMap[$choice] }
            else { Write-Host "Unknown number: $choice" -ForegroundColor Yellow }
        }
        '^[Pp]$' { Get-CCPricing; Invoke-CC-Launch-Menu }
        '^[Dd]$' { Invoke-CC-Doctor; Invoke-CC-Launch-Menu }
        '^[Uu]$' { Get-CCUsage; Invoke-CC-Launch-Menu }
        '^[Oo]$' {
            $m = Read-Host "OpenRouter model id"
            if ($m) { Invoke-CC-OpenRouter -Model $m }
        }
        '^[Nn]$' {
            $m = Read-Host "NVIDIA NIM model id"
            if ($m) { Invoke-CC-Nvidia -Model $m }
        }
        '^[Rr]$' { Reset-CC }
        '^[Qq]$' { return }
        default {
            Write-Host "Unknown: $choice" -ForegroundColor Yellow
            Invoke-CC-Launch-Menu
        }
    }
}

function Invoke-CC-Pick {
    # Try Out-ConsoleGridView first (Microsoft.PowerShell.ConsoleGuiTools)
    $hasGridView = Get-Command Out-ConsoleGridView -ErrorAction SilentlyContinue
    if (-not $hasGridView) {
        Write-Host "[cc-pick] Out-ConsoleGridView unavailable — falling back to cc-launch" -ForegroundColor DarkGray
        Write-Host "[cc-pick] To enable: Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser" -ForegroundColor DarkGray
        Invoke-CC-Launch-Menu
        return
    }
    $providers = Get-CCProviders
    $rows = $providers | ForEach-Object {
        [pscustomobject]@{
            Command     = $_.Command
            Provider    = $_.DisplayName
            Tier        = $_.QualityTier
            Context     = if ($_.Context) { "{0}K" -f [int]($_.Context / 1000) } else { '' }
            Flagship    = $_.Flagship
        }
    }
    $picked = $rows | Out-ConsoleGridView -Title "Pick a provider" -OutputMode Single
    if ($picked) {
        $id = ($providers | Where-Object Command -eq $picked.Command).Id
        Invoke-CCProvider -Id $id
    }
}
