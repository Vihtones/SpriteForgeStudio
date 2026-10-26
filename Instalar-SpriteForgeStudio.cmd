@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-SpriteForgeStudio.ps1"
if errorlevel 1 (
  echo A instalacao falhou. Consulte a mensagem acima.
  pause
  exit /b 1
)
echo Instalacao concluida.
pause
