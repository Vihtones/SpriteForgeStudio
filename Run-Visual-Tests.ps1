param([Parameter(Mandatory=$true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
$resultsPath = Join-Path $projectPath 'test_results'
New-Item -ItemType Directory -Path $resultsPath -Force | Out-Null

function Invoke-VisualSuite([string]$Script, [string]$LogName, [string]$ReportName) {
    $logPath = Join-Path $resultsPath $LogName
    $reportPath = Join-Path $resultsPath $ReportName
    Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
    & $Godot --path $projectPath --log-file $logPath --script "res://$Script" | Out-Host
    if ($null -ne $LASTEXITCODE -and [int]$LASTEXITCODE -ne 0) { throw "Godot retornou $LASTEXITCODE ao executar $Script. Consulte $logPath." }
    if (-not (Test-Path -LiteralPath $reportPath)) { throw "Relatório ausente: $reportPath" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.failed -gt 0) { throw "Há falhas em $Script. Consulte $logPath." }
    Write-Host ("{0}: {1} verificações visuais passaram." -f $Script, $report.passed)
    return [int]$report.passed
}

$passed = 0
$passed += Invoke-VisualSuite 'tests/library_review_visual.gd' 'library-review-visual-latest.log' 'library-review-ui-report.json'
$passed += Invoke-VisualSuite 'tests/bleeding_runtime_visual.gd' 'bleeding-runtime-visual-latest.log' 'bleeding-runtime-visual-report.json'
$passed += Invoke-VisualSuite 'tests/three_d_motion_viewport_tests.gd' 'three-d-motion-visual-latest.log' 'three-d-motion-viewport-report.json'
$passed += Invoke-VisualSuite 'tests/three_d_motion_turntable_visual.gd' 'three-d-motion-turntable-visual-latest.log' 'three-d-motion-turntable-visual-report.json'
$passed += Invoke-VisualSuite 'tests/three_d_motion_batch_visual_smoke.gd' 'three-d-motion-batch-visual-smoke-latest.log' 'three-d-motion-batch-visual-report.json'
Write-Output ("{0} verificações visuais passaram no total." -f $passed)
