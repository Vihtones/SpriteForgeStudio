param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string[]]$Suite = @(),
    [string]$ResumeFrom = '',
    [ValidateRange(2,600)][int]$SuiteTimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
$resultsPath = Join-Path $projectPath 'test_results'
$enginePath = (Resolve-Path -LiteralPath $Godot).Path
$allSuites = @(Get-Content -LiteralPath (Join-Path $projectPath 'tests/suites.json') -Raw | ConvertFrom-Json)
if ($Suite.Count -gt 0 -and $ResumeFrom) { throw 'Use -Suite ou -ResumeFrom, separadamente.' }
function Matches-Suite($Entry, [string]$Name) {
    return $Entry.script -eq $Name.Replace('\','/') -or [IO.Path]::GetFileNameWithoutExtension($Entry.script) -eq $Name
}
foreach ($requestedSuite in $Suite) {
    if (-not @($allSuites | Where-Object { Matches-Suite $_ $requestedSuite }).Count) { throw "Suíte desconhecida: $requestedSuite" }
}
if ($ResumeFrom -and -not @($allSuites | Where-Object { Matches-Suite $_ $ResumeFrom }).Count) { throw "Suíte de retomada desconhecida: $ResumeFrom" }
$selectedSuites = @()
$resumeReached = -not [bool]$ResumeFrom
foreach ($entry in $allSuites) {
    if ($ResumeFrom -and (Matches-Suite $entry $ResumeFrom)) { $resumeReached = $true }
    if (-not $resumeReached) { continue }
    if ($Suite.Count -gt 0 -and -not @($Suite | Where-Object { Matches-Suite $entry $_ }).Count) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $projectPath $entry.script) -PathType Leaf)) { throw "Script ausente: $($entry.script)" }
    $selectedSuites += $entry
}
if ($selectedSuites.Count -eq 0) { throw 'Nenhuma suíte selecionada.' }
New-Item -ItemType Directory -Path $resultsPath -Force | Out-Null
$runStarted = [DateTime]::UtcNow
$runResults = [Collections.Generic.List[object]]::new()
$runReportPath = Join-Path $resultsPath 'last-run.json'
function Write-RunReport {
    $passedCount = 0
    foreach ($resultEntry in $runResults) { $passedCount += [int]$resultEntry.passed }
    $runReport = [ordered]@{
        schema=1; started_utc=$runStarted.ToString('o'); updated_utc=[DateTime]::UtcNow.ToString('o')
        mode=$(if ($ResumeFrom) {'resume'} elseif ($Suite.Count) {'selected'} else {'full'})
        selected=@($selectedSuites | ForEach-Object script); suites=@($runResults.ToArray())
        complete=($runResults.Count -eq $selectedSuites.Count)
        ok=($runResults.Count -eq $selectedSuites.Count -and @($runResults | Where-Object status -ne 'passed').Count -eq 0)
        passed=$passedCount
    }
    $runReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runReportPath -Encoding utf8
}
function Invoke-GodotSuite($Entry) {
    $started = [DateTime]::UtcNow
    $suiteResult = [ordered]@{script=$Entry.script; status='running'; passed=0; failed=0; elapsed_ms=0; pid=0; error=''; log=$Entry.log}
    $logPath = Join-Path $resultsPath $Entry.log
    $engineLog = $logPath + '.engine.log'
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $enginePath
    $processInfo.WorkingDirectory = $projectPath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    foreach ($argument in @('--headless','--path',$projectPath,'--log-file',$engineLog,'--script',('res://' + $Entry.script))) { $processInfo.ArgumentList.Add($argument) }
    $testProcess = [Diagnostics.Process]::new()
    $testProcess.StartInfo = $processInfo
    $outputTask = $null; $errorTask = $null
    try {
        if (-not $testProcess.Start()) { throw 'Não foi possível iniciar o Godot.' }
        $suiteResult.pid = $testProcess.Id
        $outputTask = $testProcess.StandardOutput.ReadToEndAsync()
        $errorTask = $testProcess.StandardError.ReadToEndAsync()
        if (-not $testProcess.WaitForExit($SuiteTimeoutSeconds * 1000)) {
            $testProcess.Kill($true)
            $testProcess.WaitForExit()
            $suiteResult.status = 'timeout'
            throw "Tempo limite de $SuiteTimeoutSeconds segundos excedido. A árvore deste teste foi encerrada."
        }
        if ($testProcess.ExitCode -ne 0) { throw "Godot retornou $($testProcess.ExitCode)." }
        $reportPath = Join-Path $resultsPath $Entry.report
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf) -or (Get-Item -LiteralPath $reportPath).LastWriteTimeUtc -lt $started) { throw 'O teste não produziu um relatório novo.' }
        $suiteReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $suiteResult.passed = [int]$suiteReport.passed
        $suiteResult.failed = [int]$suiteReport.failed
        if ($suiteResult.failed -gt 0) { throw 'Há falhas no relatório do teste.' }
        $suiteResult.status = 'passed'
        Write-Host ("{0}: {1} testes passaram." -f $Entry.script, $suiteResult.passed)
        return [int]$suiteResult.passed
    } catch {
        if ($suiteResult.status -ne 'timeout') { $suiteResult.status = 'failed' }
        $suiteResult.error = $_.Exception.Message
        throw "Falha em $($Entry.script): $($suiteResult.error) Consulte $logPath. Retome com -ResumeFrom $([IO.Path]::GetFileNameWithoutExtension($Entry.script))."
    } finally {
        $logText = ''
        if ($outputTask) { $logText += $outputTask.GetAwaiter().GetResult() }
        if ($errorTask) { $logText += $errorTask.GetAwaiter().GetResult() }
        Set-Content -LiteralPath $logPath -Value $logText -Encoding utf8
        $suiteResult.elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
        $runResults.Add($suiteResult)
        Write-RunReport
        $testProcess.Dispose()
    }
}
$previousProtectedRoot = $env:SFS_TEST_PROTECTED_ROOT
$previousProtectedAlias = $env:SFS_TEST_PROTECTED_ALIAS
$fixtureCreated = $false
try {
    if ($env:OS -eq 'Windows_NT' -and @($selectedSuites | Where-Object script -eq 'tests/workspace_tests.gd').Count) {
        $securityFixture = Join-Path $resultsPath ('security-fixture-' + [guid]::NewGuid().ToString('N'))
        $protectedRoot = Join-Path $securityFixture 'approved-library'
        $protectedAlias = Join-Path $securityFixture 'library-alias'
        New-Item -ItemType Directory -Path $protectedRoot -Force | Out-Null
        New-Item -ItemType Junction -Path $protectedAlias -Target $protectedRoot | Out-Null
        $env:SFS_TEST_PROTECTED_ROOT = $protectedRoot
        $env:SFS_TEST_PROTECTED_ALIAS = $protectedAlias
        $fixtureCreated = $true
    }
    Write-RunReport
    $passedCount = 0
    foreach ($entry in $selectedSuites) { $passedCount += Invoke-GodotSuite $entry }
    Write-Output ("{0} testes passaram em {1} suítes selecionadas. Relatório: {2}" -f $passedCount, $selectedSuites.Count, $runReportPath)
} finally {
    if ($fixtureCreated) {
        $env:SFS_TEST_PROTECTED_ROOT = $previousProtectedRoot
        $env:SFS_TEST_PROTECTED_ALIAS = $previousProtectedAlias
    }
}
