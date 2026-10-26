param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Sprite Forge Studio'),
    [string]$UninstallKeyName = 'SpriteForgeStudio',
    [switch]$NoShortcuts,
    [switch]$NoRegistry
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$targetRoot = [IO.Path]::GetFullPath($InstallRoot)
if ($UninstallKeyName -notmatch '^[A-Za-z0-9._-]+$') { throw 'Nome de registro de desinstalação inválido.' }
$required = @(
    'SpriteForgeStudio.exe',
    'SpriteForgeStudio.pck',
    'README.md',
    'local-ai\sd-server.exe'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf)) {
        throw "O pacote está incompleto: $relative não foi encontrado em $sourceRoot."
    }
}
if ($sourceRoot.TrimEnd('\') -ieq $targetRoot.TrimEnd('\')) {
    throw 'A pasta de instalação não pode ser a mesma pasta do pacote extraído.'
}
if ([IO.Path]::GetPathRoot($targetRoot).TrimEnd('\') -ieq $targetRoot.TrimEnd('\')) {
    throw 'Não é permitido instalar na raiz de uma unidade.'
}
if (Test-Path -LiteralPath $targetRoot) {
	$existingRecordPath = Join-Path $targetRoot '.sfs-install.json'
	if (-not (Test-Path -LiteralPath $existingRecordPath -PathType Leaf)) {
		throw 'A pasta de destino já existe e não pertence ao Sprite Forge Studio; escolha outro local.'
	}
	$existingRecord = Get-Content -LiteralPath $existingRecordPath -Raw | ConvertFrom-Json
	if ($existingRecord.application -ne 'Sprite Forge Studio' -or $existingRecord.install_id -ne 'sprite-forge-studio-user-install' -or [IO.Path]::GetFullPath([string]$existingRecord.install_root) -ine $targetRoot) {
		throw 'A pasta de destino contém um registro incompatível; ela não será substituída.'
	}
}

$parent = Split-Path -Parent $targetRoot
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$token = [guid]::NewGuid().ToString('N')
$stage = "$targetRoot.__stage_$token"
$backup = "$targetRoot.__backup_$token"
$movedOld = $false
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $stage -Recurse -Force
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $relative) -PathType Leaf)) {
            throw "A cópia de instalação não contém $relative."
        }
    }
    if (Test-Path -LiteralPath $targetRoot) {
        Move-Item -LiteralPath $targetRoot -Destination $backup
        $movedOld = $true
    }
    try {
        Move-Item -LiteralPath $stage -Destination $targetRoot
    }
    catch {
        if ($movedOld -and -not (Test-Path -LiteralPath $targetRoot)) {
            Move-Item -LiteralPath $backup -Destination $targetRoot
            $movedOld = $false
        }
        throw
    }
    $installRecord = [ordered]@{
		application = 'Sprite Forge Studio'
		install_id = 'sprite-forge-studio-user-install'
        version = '0.64.0'
        install_root = $targetRoot
        installed_at = (Get-Date).ToString('o')
        uninstall_script = 'Uninstall-SpriteForgeStudio.ps1'
		uninstall_key_name = $UninstallKeyName
    }
    $installRecord | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetRoot '.sfs-install.json') -Encoding UTF8
    if ($movedOld) {
		Remove-Item -LiteralPath $backup -Recurse -Force
        $movedOld = $false
    }
}
catch {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if ($movedOld -and -not (Test-Path -LiteralPath $targetRoot) -and (Test-Path -LiteralPath $backup)) {
        Move-Item -LiteralPath $backup -Destination $targetRoot
    }
    throw
}

if (-not $NoShortcuts) {
    $menuRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Sprite Forge Studio'
    New-Item -ItemType Directory -Path $menuRoot -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $appShortcut = $shell.CreateShortcut((Join-Path $menuRoot 'Sprite Forge Studio.lnk'))
    $appShortcut.TargetPath = Join-Path $targetRoot 'SpriteForgeStudio.exe'
    $appShortcut.WorkingDirectory = $targetRoot
    $appShortcut.IconLocation = Join-Path $targetRoot 'SpriteForgeStudio.exe'
    $appShortcut.Save()
    if (Test-Path -LiteralPath (Join-Path $targetRoot 'Uninstall-SpriteForgeStudio.ps1')) {
        $removeShortcut = $shell.CreateShortcut((Join-Path $menuRoot 'Desinstalar Sprite Forge Studio.lnk'))
        $removeShortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $removeShortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $targetRoot 'Uninstall-SpriteForgeStudio.ps1') + '"'
        $removeShortcut.WorkingDirectory = $targetRoot
        $removeShortcut.Save()
    }
}

if (-not $NoRegistry) {
	$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $UninstallKeyName
    New-Item -Path $uninstallKey -Force | Out-Null
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Set-ItemProperty -LiteralPath $uninstallKey -Name DisplayName -Value 'Sprite Forge Studio'
    Set-ItemProperty -LiteralPath $uninstallKey -Name DisplayVersion -Value '0.64.0'
    Set-ItemProperty -LiteralPath $uninstallKey -Name Publisher -Value 'Sprite Forge Studio'
    Set-ItemProperty -LiteralPath $uninstallKey -Name InstallLocation -Value $targetRoot
    Set-ItemProperty -LiteralPath $uninstallKey -Name UninstallString -Value ('"' + $powershell + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $targetRoot 'Uninstall-SpriteForgeStudio.ps1') + '"')
	New-ItemProperty -LiteralPath $uninstallKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
	New-ItemProperty -LiteralPath $uninstallKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
}

Write-Output "Sprite Forge Studio instalado em $targetRoot"
if (-not $NoShortcuts) { Write-Output 'Atalho criado no menu Iniciar: Sprite Forge Studio.' }
Write-Output 'Projetos e dados do usuário são mantidos fora da pasta do aplicativo.'
