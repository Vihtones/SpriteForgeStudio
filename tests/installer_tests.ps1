param([Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$requiredPackageFiles = @(
    'Install-SpriteForgeStudio.ps1',
    'Uninstall-SpriteForgeStudio.ps1',
    'SpriteForgeStudio.exe',
    'SpriteForgeStudio.pck',
    'README.md',
    'docs\INSTALL-WINDOWS.md',
    'local-ai\sd-server.exe'
)
foreach ($relative in $requiredPackageFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $relative) -PathType Leaf)) {
        throw "O pacote indicado não contém o arquivo necessário aos testes: $relative"
    }
}
$resultsRoot = [IO.Path]::GetFullPath((Join-Path $env:TEMP 'SFS-InstallerTests'))
New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
$fixture = Join-Path $resultsRoot ('installer-fixture-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $fixture 'Install\Sprite Forge Studio'
$unsafeRoot = Join-Path $fixture 'Unrelated'
$registryName = 'SpriteForgeStudio-Test-' + [guid]::NewGuid().ToString('N')
$previousAppData = $env:APPDATA
$passed = 0
function Check([bool]$condition, [string]$description) {
    if (-not $condition) { throw "Falha no teste do instalador: $description" }
    $script:passed += 1
    Write-Output "PASS $description"
}
if (-not $fixture.StartsWith($resultsRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'O diretório temporário de teste saiu de test_results; limpeza recusada.'
}
try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    New-Item -ItemType Directory -Path $unsafeRoot -Force | Out-Null
	$testPackage = Join-Path $fixture 'Package'
	New-Item -ItemType Directory -Path (Join-Path $testPackage 'docs'),(Join-Path $testPackage 'local-ai') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $testPackage 'SpriteForgeStudio.exe') -Value 'installer-test-stub' -Encoding ASCII
	Set-Content -LiteralPath (Join-Path $testPackage 'SpriteForgeStudio.pck') -Value 'installer-test-stub' -Encoding ASCII
	Set-Content -LiteralPath (Join-Path $testPackage 'README.md') -Value 'Installer fixture.' -Encoding ASCII
	Set-Content -LiteralPath (Join-Path $testPackage 'docs\INSTALL-WINDOWS.md') -Value 'Installer fixture.' -Encoding ASCII
	Set-Content -LiteralPath (Join-Path $testPackage 'local-ai\sd-server.exe') -Value 'optional runtime fixture.' -Encoding ASCII
	Copy-Item -LiteralPath (Join-Path $package 'Install-SpriteForgeStudio.ps1'),(Join-Path $package 'Uninstall-SpriteForgeStudio.ps1') -Destination $testPackage
	$env:APPDATA = Join-Path $fixture 'Profile\Roaming'
	New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $unsafeRoot 'keep.txt') -Value 'preservar' -Encoding UTF8
	$installer = Join-Path $testPackage 'Install-SpriteForgeStudio.ps1'
    $uninstaller = Join-Path $installRoot 'Uninstall-SpriteForgeStudio.ps1'
    $refused = $false
    try {
        & $installer -InstallRoot $unsafeRoot -NoShortcuts -NoRegistry | Out-Null
    }
    catch { $refused = $true }
    Check ($refused -and (Test-Path -LiteralPath (Join-Path $unsafeRoot 'keep.txt'))) 'não substitui uma pasta alheia'

	& $installer -InstallRoot $installRoot -UninstallKeyName $registryName | Out-Null
    $record = Get-Content -LiteralPath (Join-Path $installRoot '.sfs-install.json') -Raw | ConvertFrom-Json
    Check ($record.version -eq '0.64.0' -and $record.install_id -eq 'sprite-forge-studio-user-install') 'instalação grava registro validável'
    Check ((Test-Path -LiteralPath (Join-Path $installRoot 'SpriteForgeStudio.exe')) -and (Test-Path -LiteralPath (Join-Path $installRoot 'SpriteForgeStudio.pck'))) 'instala binário e pacote do Godot'
    Check (Test-Path -LiteralPath (Join-Path $installRoot 'docs\INSTALL-WINDOWS.md')) 'instala documentação de uso'
    Check (Test-Path -LiteralPath (Join-Path $installRoot 'local-ai\sd-server.exe')) 'preserva runtime local opcional'
	$menuRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Sprite Forge Studio'
	$shortcutPath = Join-Path $menuRoot 'Sprite Forge Studio.lnk'
	Check (Test-Path -LiteralPath $shortcutPath) 'cria atalho no perfil Start Menu isolado'
	$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
	Check ([IO.Path]::GetFullPath($shortcut.TargetPath) -ieq [IO.Path]::GetFullPath((Join-Path $installRoot 'SpriteForgeStudio.exe'))) 'atalho aponta para o executável instalado'
	$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $registryName
	$registry = Get-ItemProperty -LiteralPath $registryPath
	Check ($registry.DisplayVersion -eq '0.64.0' -and $registry.InstallLocation -eq $installRoot) 'registra a instalação por usuário para desinstalação'

	& $installer -InstallRoot $installRoot -UninstallKeyName $registryName | Out-Null
    Check (Test-Path -LiteralPath (Join-Path $installRoot 'SpriteForgeStudio.exe')) 'atualização no mesmo destino termina sem perder o executável'
	Check (-not (Get-ChildItem -LiteralPath (Join-Path $fixture 'Install') -Directory -Filter 'Sprite Forge Studio.__backup_*' -ErrorAction SilentlyContinue)) 'atualização remove somente o backup temporário validado'

	& $uninstaller -InstallRoot $installRoot | Out-Null
    Check (-not (Test-Path -LiteralPath $installRoot) -and (Test-Path -LiteralPath (Join-Path $unsafeRoot 'keep.txt'))) 'remove a instalação verificada e preserva dados não relacionados'
	Check (-not (Test-Path -LiteralPath $menuRoot)) 'desinstalador remove seus atalhos Start Menu'
	Check (-not (Test-Path -LiteralPath $registryPath)) 'desinstalador limpa somente sua entrada de registro'
    Write-Output "Installer result: $passed aprovados, 0 falhas."
}
finally {
	if ([string]::IsNullOrEmpty($previousAppData)) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue }
	else { $env:APPDATA = $previousAppData }
	$testRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $registryName
	if (Test-Path -LiteralPath $testRegistryPath) { Remove-Item -LiteralPath $testRegistryPath -Recurse -Force }
    $fixtureFull = [IO.Path]::GetFullPath($fixture)
    if (-not $fixtureFull.StartsWith($resultsRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'O diretório temporário saiu de test_results; limpeza recusada.'
    }
    if (Test-Path -LiteralPath $fixtureFull) { Remove-Item -LiteralPath $fixtureFull -Recurse -Force }
}
