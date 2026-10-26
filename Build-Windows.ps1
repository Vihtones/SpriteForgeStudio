param([Parameter(Mandatory=$true)][string]$Godot, [string]$Destination = (Join-Path $PSScriptRoot '../Windows'))
$ErrorActionPreference = 'Stop'
$enginePath = (Resolve-Path -LiteralPath $Godot).Path
if ($enginePath.EndsWith('_console.exe')) { $enginePath = $enginePath.Replace('_console.exe', '.exe') }
if (-not (Test-Path -LiteralPath $enginePath)) { throw 'Executável GUI do Godot não encontrado.' }
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$buildPath = (Resolve-Path -LiteralPath $Destination).Path
$resultsPath = Join-Path $PSScriptRoot 'test_results'
New-Item -ItemType Directory -Path $resultsPath -Force | Out-Null
$engineLog = Join-Path $resultsPath 'windows-build-engine.log'
$exportLog = Join-Path $resultsPath 'windows-build-export.log'
$sampleCheckLog = Join-Path $resultsPath 'windows-build-sample-check.log'
$sampleCheckEngineLog = Join-Path $resultsPath 'windows-build-sample-check-engine.log'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $Godot --headless --path $PSScriptRoot --log-file $engineLog --export-pack 'Windows Desktop' (Join-Path $buildPath 'SpriteForgeStudio.pck') 2>&1 | Tee-Object -FilePath $exportLog | Out-Null
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($exitCode -ne 0) { throw "Falha ao empacotar (Godot retornou $exitCode). Consulte $exportLog." }
if (-not (Test-Path -LiteralPath (Join-Path $buildPath 'SpriteForgeStudio.pck'))) { throw "Godot não criou o pacote. Consulte $exportLog." }
$ErrorActionPreference = 'Continue'
& $Godot --headless --log-file $sampleCheckEngineLog --main-pack (Join-Path $buildPath 'SpriteForgeStudio.pck') -- --sfs-sample-check 2>&1 | Tee-Object -FilePath $sampleCheckLog | Out-Null
$sampleExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($sampleExitCode -ne 0) { throw "A demonstração embutida não passou no self-check (Godot retornou $sampleExitCode). Consulte $sampleCheckLog." }
Copy-Item -LiteralPath $enginePath -Destination (Join-Path $buildPath 'SpriteForgeStudio.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md'),(Join-Path $PSScriptRoot 'THIRD_PARTY.md') -Destination $buildPath
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-SpriteForgeStudio.ps1'),(Join-Path $PSScriptRoot 'Uninstall-SpriteForgeStudio.ps1'),(Join-Path $PSScriptRoot 'Instalar-SpriteForgeStudio.cmd') -Destination $buildPath
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY_LICENSES.txt')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY_LICENSES.txt') -Destination $buildPath }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs') -Destination $buildPath -Recurse -Force
$localRuntime = Join-Path $PSScriptRoot 'vendor/stable-diffusion-cpp'
if (-not (Test-Path -LiteralPath (Join-Path $localRuntime 'sd-server.exe'))) { throw 'Motor local ausente em vendor/stable-diffusion-cpp; consulte docs/LOCAL-AI.md.' }
$localBuildPath = Join-Path $buildPath 'local-ai'
New-Item -ItemType Directory -Path $localBuildPath -Force | Out-Null
Get-ChildItem -LiteralPath $localRuntime | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $localBuildPath -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-LocalAI-Models.ps1') -Destination $buildPath
Set-Content -LiteralPath (Join-Path $buildPath 'Revisar-Animacoes.cmd') -Value '@echo off', 'start "" "%~dp0SpriteForgeStudio.exe" -- --sfs-review' -Encoding ascii
Set-Content -LiteralPath (Join-Path $buildPath 'Abrir-Biblioteca.cmd') -Value '@echo off', 'start "" "%~dp0SpriteForgeStudio.exe" -- --sfs-public-library' -Encoding ascii
Write-Output "Pacote portátil em $buildPath."
Write-Output "Testes do instalador são independentes: execute tests/installer_tests.ps1 -PackagePath `"$buildPath`" quando quiser validá-los."
