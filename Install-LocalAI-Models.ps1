param([string]$Destination = (Join-Path $env:APPDATA 'Godot/app_userdata/Sprite Forge Studio/local_ai/models'))
$ErrorActionPreference = 'Stop'
$model = Join-Path $Destination 'DreamShaper8_LCM_q8_0.gguf'
$loraFolder = Join-Path $Destination 'loras'
$lora = Join-Path $loraFolder 'pixel-art-LoRa.safetensors'
New-Item -ItemType Directory -Path $Destination,$loraFolder -Force | Out-Null

function Save-VerifiedModel([string]$Path,[string]$Url,[string]$Sha256) {
    if (Test-Path -LiteralPath $Path) {
        $existing = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($existing -eq $Sha256) { Write-Host "Já verificado: $Path"; return }
        Write-Host "Retomando/verificando transferência incompleta: $Path"
    }
    & curl.exe --fail --location --retry 12 --retry-all-errors --retry-delay 4 --connect-timeout 30 --continue-at - --output $Path $Url
    if ($LASTEXITCODE -ne 0) { throw "Falha ao baixar $Path (curl $LASTEXITCODE). Execute novamente para retomar." }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256) { throw "SHA-256 inválido para $Path. Esperado $Sha256, recebido $actual." }
    Write-Host "Arquivo verificado: $Path"
}

Save-VerifiedModel $model 'https://huggingface.co/haven-ai-companion/dreamshaper8-lcm-gguf/resolve/main/DreamShaper8_LCM_q8_0.gguf' 'dd06826d1eca711efa38190395a5ee949d0427fc6422c39433358a815e5b066c'
Save-VerifiedModel $lora 'https://huggingface.co/SedatAl/pixel-art-LoRa/resolve/main/pytorch_lora_weights.safetensors' 'ad5034703699e910d5f9525ea5db64abcbd8d7396ff8f771c09403f3adb048ad'
Write-Host 'Modelos locais instalados. Abra o SFS > HyperLearn Lab > Iniciar/verificar motor local.'
