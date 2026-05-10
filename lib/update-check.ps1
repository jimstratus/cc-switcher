# =============================================================================
# update-check.ps1 — Notice when cc-switcher.psm1 has been updated
# since the last shell load. Cheap mtime comparison, no network.
# =============================================================================

$script:CCLastLoadFile = Join-Path $script:CCSwitcherRoot 'data\.last-load'

function Test-CCUpdated {
    $entry = Join-Path $script:CCSwitcherRoot 'cc-switcher.psm1'
    if (-not (Test-Path $entry)) { return $false }
    $current = (Get-Item $entry).LastWriteTimeUtc
    if (-not (Test-Path $script:CCLastLoadFile)) {
        $current.ToString('o') | Set-Content $script:CCLastLoadFile
        return $false
    }
    try {
        $prev = [DateTime]::Parse((Get-Content $script:CCLastLoadFile -Raw).Trim()).ToUniversalTime()
        $current.ToString('o') | Set-Content $script:CCLastLoadFile
        return ($current -gt $prev)
    } catch {
        $current.ToString('o') | Set-Content $script:CCLastLoadFile
        return $false
    }
}
