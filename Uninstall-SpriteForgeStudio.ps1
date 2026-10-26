param([string]$InstallRoot = $PSScriptRoot, [switch]$NoShortcuts, [switch]$NoRegistry)
$ErrorActionPreference = 'Stop'
$targetRoot = [IO.Path]::GetFullPath($InstallRoot)
$recordPath = Join-Path $targetRoot '.sfs-install.json'
if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
    throw 'O registro do Sprite Forge Studio não foi encontrado; a pasta não será removida.'
}
$record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
if ($record.application -ne 'Sprite Forge Studio' -or $record.install_id -ne 'sprite-forge-studio-user-install' -or [IO.Path]::GetFullPath([string]$record.install_root) -ine $targetRoot) {
    throw 'O registro de instalação não corresponde a esta pasta; a remoção foi recusada.'
}
if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'SpriteForgeStudio.exe') -PathType Leaf)) {
    throw 'O executável esperado não foi encontrado; a remoção foi recusada.'
}
$menuRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Sprite Forge Studio'
if (-not $NoShortcuts -and (Test-Path -LiteralPath $menuRoot)) { Remove-Item -LiteralPath $menuRoot -Recurse -Force }
if (-not $NoRegistry) {
	$keyName = [string]$record.uninstall_key_name
	if ($keyName -notmatch '^[A-Za-z0-9._-]+$') { throw 'A chave de desinstalação registrada é inválida; a remoção foi recusada.' }
	$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $keyName
	if (Test-Path -LiteralPath $uninstallKey) { Remove-Item -LiteralPath $uninstallKey -Recurse -Force }
}
Remove-Item -LiteralPath $targetRoot -Recurse -Force
Write-Output 'Sprite Forge Studio removido. Projetos, referências e dados pessoais foram preservados.'
