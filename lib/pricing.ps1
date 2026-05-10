# =============================================================================
# pricing.ps1 — OpenRouter live pricing with disk-persisted cache
# =============================================================================

$script:ORPricingCacheFile = Join-Path $script:CCSwitcherRoot 'data\.pricing-cache.json'
$script:ORPricingTTL_sec = 300

function Get-CCLivePricing {
    # Memory cache first
    if ($script:ORPricingCache -and $script:ORPricingCacheTime) {
        $age = [DateTimeOffset]::Now.ToUnixTimeSeconds() - $script:ORPricingCacheTime
        if ($age -lt $script:ORPricingTTL_sec) { return $script:ORPricingCache }
    }
    # Disk cache next
    if (Test-Path $script:ORPricingCacheFile) {
        try {
            $cached = Get-Content $script:ORPricingCacheFile -Raw | ConvertFrom-Json
            $age = [DateTimeOffset]::Now.ToUnixTimeSeconds() - $cached.fetchedAt
            if ($age -lt $script:ORPricingTTL_sec) {
                $script:ORPricingCache = $cached.data
                $script:ORPricingCacheTime = $cached.fetchedAt
                return $script:ORPricingCache
            }
        } catch {}
    }
    if ([string]::IsNullOrEmpty($env:OPENROUTER_API_KEY)) { return $null }
    try {
        $resp = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" `
            -Headers @{ Authorization = "Bearer $env:OPENROUTER_API_KEY" } `
            -TimeoutSec 10
        $script:ORPricingCache = $resp.data
        $script:ORPricingCacheTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        # Persist to disk for next shell
        @{ fetchedAt = $script:ORPricingCacheTime; data = $resp.data } |
            ConvertTo-Json -Depth 10 -Compress |
            Set-Content $script:ORPricingCacheFile
        return $script:ORPricingCache
    } catch {
        Write-Host "[cc-pricing] Could not fetch: $($_.Exception.Message)" -ForegroundColor DarkGray
        return $null
    }
}

function Get-CCPricing {
    $models = Get-CCLivePricing
    $providers = Get-CCProviders
    # Collect every OpenRouter-style model id from the catalog (slash in name)
    $configured = @()
    foreach ($p in $providers) {
        foreach ($id in @($p.Opus, $p.Sonnet, $p.Haiku) | Select-Object -Unique) {
            if ($id -match '/') {
                $configured += @{ id = $id; provider = $p.DisplayName }
            }
        }
    }
    $configured = $configured | Sort-Object id -Unique

    if (-not $models) {
        Write-Host "[cc-pricing] No live data (set OPENROUTER_API_KEY)." -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host " Live pricing (OpenRouter, $script:ORPricingTTL_sec s cache) " -ForegroundColor Magenta
    Write-Host ("=" * 78) -ForegroundColor Magenta
    Write-Host ("{0,-35} {1,10} {2,12} {3,12}" -f "Model", "$/1M in", "$/1M out", "Context") -ForegroundColor White
    Write-Host ("-" * 78) -ForegroundColor Magenta

    foreach ($m in $configured) {
        $entry = $models | Where-Object { $_.id -eq $m.id } | Select-Object -First 1
        $promptStr = "-"; $compStr = "-"; $ctxStr = "-"
        if ($entry) {
            if ($entry.pricing.prompt) {
                $promptStr = "{0:N2}" -f ([math]::Round([double]$entry.pricing.prompt * 1e6, 2))
            }
            if ($entry.pricing.completion) {
                $compStr = "{0:N2}" -f ([math]::Round([double]$entry.pricing.completion * 1e6, 2))
            }
            if ($entry.context_length) {
                $ctxStr = "{0:N0}" -f ([int64]$entry.context_length)
            }
        }
        Write-Host ("{0,-35} {1,10} {2,12} {3,12}" -f $m.id, $promptStr, $compStr, $ctxStr) -ForegroundColor Gray
    }
    Write-Host ""
}
