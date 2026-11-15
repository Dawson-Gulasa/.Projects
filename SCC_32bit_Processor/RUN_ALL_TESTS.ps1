# Run the curated SCC verification suites from any working directory.
param([switch]$RegressionOnly,[switch]$NormalOnly,[switch]$ForceOnly)
$ErrorActionPreference = 'Stop'
if ((@($RegressionOnly,$NormalOnly,$ForceOnly) | Where-Object { $_ }).Count -gt 1) {
    throw 'Choose at most one of -RegressionOnly, -NormalOnly, and -ForceOnly.'
}
$verification = Join-Path (Join-Path $PSScriptRoot 'processor') 'verification'
$plans = @()
if ($RegressionOnly -or (-not $NormalOnly -and -not $ForceOnly)) {
    $plans += @{Name='20-case internal regression'; File='run_cp5_regression.ps1'; Force=$false}
}
if ($NormalOnly -or (-not $RegressionOnly -and -not $ForceOnly)) {
    $plans += @{Name='Fall 2026 normal classwide'; File='run_f26_demo.ps1'; Force=$false}
}
if ($ForceOnly -or (-not $RegressionOnly -and -not $NormalOnly)) {
    $plans += @{Name='Fall 2026 forced-fault'; File='run_f26_demo.ps1'; Force=$true}
}
foreach ($plan in $plans) {
    Write-Host "`n=== $($plan.Name) ==="
    $script = Join-Path $verification $plan.File
    if ($plan.Force) { & $script -Force } else { & $script }
    if ($LASTEXITCODE -ne 0) { throw "Verification failed: $($plan.Name)" }
}
Write-Host "Selected suites completed; review each suite's summary."
