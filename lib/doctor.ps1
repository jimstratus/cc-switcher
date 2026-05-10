# =============================================================================
# doctor.ps1 — cc-doctor health check
# Validates API keys exist, format-checks them, optionally pings endpoints.
# =============================================================================

function Test-CCApiKey {
    param([string]$KeyName)
    $val = [Environment]::GetEnvironmentVariable($KeyName)
    if ([string]::IsNullOrEmpty($val)) { return @{ Status = 'missing'; Detail = '(env var unset)' } }
    # Heuristic format checks — most keys are 30+ chars, alphanum + dashes/underscores
    $patterns = @{
        'OPENROUTER_API_KEY'   = '^sk-or-[A-Za-z0-9_-]{20,}$'
        'DEEPSEEK_API_KEY'     = '^sk-[A-Za-z0-9]{20,}$'
        'ANTHROPIC_API_KEY'    = '^sk-ant-[A-Za-z0-9_-]{20,}$'
        'NVIDIA_API_KEY'       = '^nvapi-[A-Za-z0-9_-]{20,}$'
        'MINIMAX_API_KEY'      = '^[A-Za-z0-9._-]{20,}$'
        'OPENCODE_GO_API_KEY'  = '^[A-Za-z0-9_.-]{20,}$'
        'ZAI_API_KEY'          = '^[A-Za-z0-9._-]{20,}$'
        'KIMI_API_KEY'         = '^[A-Za-z0-9._-]{20,}$'
    }
    if ($patterns.ContainsKey($KeyName)) {
        if ($val -notmatch $patterns[$KeyName]) {
            return @{ Status = 'malformed'; Detail = "len=$($val.Length), prefix=$($val.Substring(0, [Math]::Min(8, $val.Length)))..." }
        }
    }
    return @{ Status = 'ok'; Detail = "len=$($val.Length)" }
}

function Test-CCEndpoint {
    param([string]$Url, [int]$TimeoutSec = 5)
    try {
        $stop = [Diagnostics.Stopwatch]::StartNew()
        $req = [System.Net.Http.HttpClient]::new()
        $req.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $task = $req.GetAsync($Url)
        if ($task.Wait([TimeSpan]::FromSeconds($TimeoutSec))) {
            $stop.Stop()
            return @{ Reachable = $true; Latency = $stop.ElapsedMilliseconds; Code = [int]$task.Result.StatusCode }
        } else {
            return @{ Reachable = $false; Latency = $TimeoutSec * 1000; Code = 0 }
        }
    } catch {
        return @{ Reachable = $false; Latency = 0; Code = 0; Error = $_.Exception.Message }
    } finally {
        if ($req) { $req.Dispose() }
    }
}

function Invoke-CC-Doctor {
    [CmdletBinding()] param([switch]$NoNetwork)

    Write-Host ""
    Write-Host " cc-switcher doctor " -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor Cyan

    Write-Host ""
    Write-Host " API keys " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    $keys = @('OPENROUTER_API_KEY','DEEPSEEK_API_KEY','MINIMAX_API_KEY','NVIDIA_API_KEY',
              'OPENCODE_GO_API_KEY','ZAI_API_KEY','KIMI_API_KEY','XIAOMI_API_KEY','ANTHROPIC_API_KEY')
    foreach ($k in $keys) {
        $r = Test-CCApiKey -KeyName $k
        $color = switch ($r.Status) {
            'ok'        { 'Green' }
            'malformed' { 'Yellow' }
            'missing'   { 'DarkGray' }
        }
        $glyph = switch ($r.Status) {
            'ok'        { '[OK] ' }
            'malformed' { '[?]  ' }
            'missing'   { '[--] ' }
        }
        Write-Host ("  {0}{1,-22} {2}" -f $glyph, $k, $r.Detail) -ForegroundColor $color
    }

    if ($NoNetwork) {
        Write-Host ""
        Write-Host "[doctor] Skipped network checks (--NoNetwork)" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host " Endpoint reachability " -ForegroundColor Yellow
    Write-Host ("-" * 78) -ForegroundColor DarkYellow
    $providers = Get-CCProviders | Sort-Object Command
    foreach ($p in $providers) {
        # Skip if auth var missing — we only ping endpoints the user can actually use
        $hasKey = -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($p.AuthVar))
        if (-not $hasKey -and -not $p.RequiresOAuth) {
            Write-Host ("  [--] {0,-30} (no API key)" -f $p.Command) -ForegroundColor DarkGray
            continue
        }
        $r = Test-CCEndpoint -Url $p.BaseUrl
        if ($r.Reachable) {
            Write-Host ("  [OK] {0,-30} {1,5}ms  HTTP {2}  -> {3}" -f $p.Command, $r.Latency, $r.Code, $p.BaseUrl) -ForegroundColor Green
        } else {
            Write-Host ("  [X]  {0,-30} unreachable -> {1}" -f $p.Command, $p.BaseUrl) -ForegroundColor Red
        }
    }
    Write-Host ""
}
