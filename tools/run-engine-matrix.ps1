# Run the cfTOML unit test suite across all configured engines.
# Stops any current server first. For each engine, starts, hits the test runner, captures
# the summary line, and stops the server. Outputs a matrix table at the end.

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$engines = @(
    @{ name = "cf2016"; port = 12016 },
    @{ name = "cf2021"; port = 12021 },
    @{ name = "cf2023"; port = 12023 },
    @{ name = "cf2025"; port = 12025 },
    @{ name = "lucee5"; port = 13005 },
    @{ name = "lucee6"; port = 13006 },
    @{ name = "lucee7"; port = 13007 },
    @{ name = "boxlang"; port = 14000 },
    @{ name = "boxlang-adobe"; port = 14001 },
    @{ name = "boxlang-lucee"; port = 14002 }
)

# Stop any currently-running cfTOML server (best-effort)
box server stop name=cfTOML 2>$null

$results = @()
foreach ($engine in $engines) {
    Write-Host ""
    Write-Host "===== Engine: $($engine.name) port $($engine.port) ====="
    $configFile = "server.$($engine.name).json"
    if (-not (Test-Path $configFile)) {
        Write-Host "  SKIP: $configFile not found"
        $results += [PSCustomObject]@{ Engine = $engine.name; Status = "MISSING_CONFIG"; Summary = "" }
        continue
    }
    Write-Host "  Starting..."
    box server start serverConfigFile=$configFile 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    try {
        $url = "http://localhost:$($engine.port)/tests/runner.cfm"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60
        $body = $response.Content
        # Find the summary line: "N passed, N failed, N errors"
        $summary = ""
        if ($body -match "(\d+) passed, (\d+) failed, (\d+) errors") {
            $summary = $matches[0]
            $passed = [int]$matches[1]
            $failed = [int]$matches[2]
            $errors = [int]$matches[3]
            $status = if ($failed -eq 0 -and $errors -eq 0) { "PASS" } else { "FAIL" }
        } else {
            $status = "NO_SUMMARY"
            $summary = "(could not parse summary)"
        }
        Write-Host "  $status : $summary"
        $results += [PSCustomObject]@{ Engine = $engine.name; Status = $status; Summary = $summary }
    } catch {
        Write-Host "  ERROR: $_"
        $results += [PSCustomObject]@{ Engine = $engine.name; Status = "ERROR"; Summary = $_.Exception.Message }
    } finally {
        Write-Host "  Stopping..."
        box server stop serverConfigFile=$configFile 2>&1 | Out-Null
    }
}

Write-Host ""
Write-Host "===== Matrix summary ====="
$results | Format-Table -AutoSize