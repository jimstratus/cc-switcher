# =============================================================================
# usage.ps1 — Token usage tracking
# Records session metadata; aggregates token counts from Claude Code's
# session JSONL files after exit.
# =============================================================================

$script:CCUsageLogPath = Join-Path $script:CCSwitcherRoot 'data\.usage-log.jsonl'

function Write-CCSessionStart {
    param(
        [Parameter(Mandatory)] [string]$ProviderName,
        [string]$OpusModel
    )
    $script:CCSessionStartedAt = [DateTimeOffset]::Now
    $script:CCSessionProvider = $ProviderName
    $script:CCSessionLatestSessionFile = $null
    # Capture the latest session file timestamp so we can find the new one after exit
    $script:CCSessionPreExistingFiles = @{}
    $sessionsRoot = Join-Path $env:USERPROFILE '.claude\projects'
    if (Test-Path $sessionsRoot) {
        Get-ChildItem $sessionsRoot -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
            ForEach-Object { $script:CCSessionPreExistingFiles[$_.FullName] = $_.LastWriteTime }
    }
}

function Write-CCSessionEnd {
    param(
        [Parameter(Mandatory)] [string]$ProviderName,
        [Parameter(Mandatory)] [DateTimeOffset]$StartedAt
    )
    $endedAt = [DateTimeOffset]::Now
    $duration = ($endedAt - $StartedAt).TotalSeconds

    # Find session JSONL files modified during this session
    $sessionsRoot = Join-Path $env:USERPROFILE '.claude\projects'
    $tokensIn = 0; $tokensOut = 0; $cacheReads = 0; $cacheCreates = 0; $turns = 0
    if (Test-Path $sessionsRoot) {
        $touched = Get-ChildItem $sessionsRoot -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -ge $StartedAt.LocalDateTime -and
                ($script:CCSessionPreExistingFiles[$_.FullName] -ne $_.LastWriteTime)
            }
        foreach ($file in $touched) {
            try {
                Get-Content $file.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                    if ([string]::IsNullOrWhiteSpace($_)) { return }
                    try {
                        $obj = $_ | ConvertFrom-Json -ErrorAction Stop
                        if ($obj.message.usage) {
                            $tokensIn    += [int]($obj.message.usage.input_tokens   ?? 0)
                            $tokensOut   += [int]($obj.message.usage.output_tokens  ?? 0)
                            $cacheReads  += [int]($obj.message.usage.cache_read_input_tokens     ?? 0)
                            $cacheCreates+= [int]($obj.message.usage.cache_creation_input_tokens ?? 0)
                            $turns++
                        }
                    } catch {}
                }
            } catch {}
        }
    }

    $entry = [pscustomobject]@{
        ts          = $endedAt.ToString('o')
        provider    = $ProviderName
        durationSec = [math]::Round($duration, 1)
        turns       = $turns
        tokensIn    = $tokensIn
        tokensOut   = $tokensOut
        cacheRead   = $cacheReads
        cacheCreate = $cacheCreates
    }
    try {
        $entry | ConvertTo-Json -Compress | Add-Content $script:CCUsageLogPath
    } catch {}
}

function Get-CCUsage {
    [CmdletBinding()] param([int]$Last = 20)
    if (-not (Test-Path $script:CCUsageLogPath)) {
        Write-Host "[cc-usage] No usage log yet ($script:CCUsageLogPath)" -ForegroundColor DarkGray
        return
    }
    $entries = Get-Content $script:CCUsageLogPath | ForEach-Object {
        if ($_) { try { $_ | ConvertFrom-Json } catch {} }
    } | Where-Object { $_ }
    if (-not $entries) { Write-Host "[cc-usage] Log is empty." -ForegroundColor DarkGray; return }

    Write-Host ""
    Write-Host " cc-switcher usage (last $Last sessions) " -ForegroundColor Cyan
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host ("{0,-19} {1,-32} {2,8} {3,7} {4,9} {5,9}" -f "When","Provider","Duration","Turns","Tokens In","Tokens Out") -ForegroundColor White
    Write-Host ("-" * 90) -ForegroundColor DarkCyan
    $tail = $entries | Select-Object -Last $Last
    foreach ($e in $tail) {
        $when = ([datetime]$e.ts).ToString('yyyy-MM-dd HH:mm')
        Write-Host ("{0,-19} {1,-32} {2,7}s {3,7} {4,9:N0} {5,9:N0}" -f `
            $when, $e.provider, $e.durationSec, $e.turns, $e.tokensIn, $e.tokensOut) -ForegroundColor Gray
    }

    # Aggregate totals
    $totalIn  = ($entries | Measure-Object -Property tokensIn -Sum).Sum
    $totalOut = ($entries | Measure-Object -Property tokensOut -Sum).Sum
    Write-Host ("-" * 90) -ForegroundColor DarkCyan
    Write-Host ("Total ({0} sessions): {1:N0} in, {2:N0} out" -f $entries.Count, $totalIn, $totalOut) -ForegroundColor Yellow

    # Per-provider summary
    Write-Host ""
    Write-Host " By provider " -ForegroundColor Yellow
    Write-Host ("-" * 60) -ForegroundColor DarkYellow
    $entries | Group-Object provider | Sort-Object { ($_.Group | Measure-Object tokensOut -Sum).Sum } -Descending | ForEach-Object {
        $tIn  = ($_.Group | Measure-Object tokensIn  -Sum).Sum
        $tOut = ($_.Group | Measure-Object tokensOut -Sum).Sum
        Write-Host ("  {0,-32} {1,4} sessions, {2,9:N0} in / {3,9:N0} out" -f $_.Name, $_.Count, $tIn, $tOut)
    }
    Write-Host ""
}
