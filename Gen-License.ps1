<#
.SYNOPSIS
    WinBoost — Generador de licencias (herramienta interna).
    Requiere _private_key.xml en la raiz del proyecto.
    NUNCA distribuir este script ni _private_key.xml.

.USAGE
    # Generar licencia Pro para un equipo (requiere Hardware ID del cliente)
    .\Gen-License.ps1 -HardwareID "A1B2C3D4E5F60718"

    # Generar licencia Tecnico (multi-PC, sin hardware ID)
    .\Gen-License.ps1 -Tech

    # Generar un nuevo par de claves RSA (solo si se rota la clave)
    .\Gen-License.ps1 -GenerateKeys
#>
param(
    [string]$HardwareID,
    [switch]$Tech,
    [switch]$GenerateKeys
)

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot

if ($GenerateKeys) {
    Write-Host ""
    Write-Host "Generando par de claves RSA-2048..." -ForegroundColor Yellow
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 2048
    $pub  = $rsa.ToXmlString($false)
    $priv = $rsa.ToXmlString($true)
    $rsa.Dispose()

    $priv | Out-File (Join-Path $ROOT "_private_key.xml") -Encoding UTF8
    Write-Host ""
    Write-Host "=== CLAVE PUBLICA (pegar en OptimizarPC_App.ps1 como LICENSE_PUBLIC_KEY_XML) ===" -ForegroundColor Green
    Write-Host $pub
    Write-Host ""
    Write-Host "Clave privada guardada en _private_key.xml (NO commitear al repo)." -ForegroundColor Red
    return
}

$privKeyPath = Join-Path $ROOT "_private_key.xml"
if (-not (Test-Path $privKeyPath)) {
    Write-Host "ERROR: no se encontro _private_key.xml en $ROOT" -ForegroundColor Red
    Write-Host "Ejecuta primero: .\Gen-License.ps1 -GenerateKeys"
    exit 1
}

$privKeyXml = Get-Content $privKeyPath -Raw -Encoding UTF8

$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.FromXmlString($privKeyXml)
$sha = [System.Security.Cryptography.SHA256]::Create()

if ($Tech) {
    $msg  = "WINBOOST-TECH"
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($msg))
    $sig  = $rsa.SignHash($hash, "SHA256")
    $b64  = [System.Convert]::ToBase64String($sig)
    Write-Host ""
    Write-Host "=== LICENCIA TECNICO ===" -ForegroundColor Cyan
    Write-Host "TECH-$b64"
    Write-Host ""
} elseif ($HardwareID) {
    $hwid = $HardwareID.Trim().ToUpper()
    $msg  = "WINBOOST-PRO-$hwid"
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($msg))
    $sig  = $rsa.SignHash($hash, "SHA256")
    $b64  = [System.Convert]::ToBase64String($sig)
    Write-Host ""
    Write-Host "=== LICENCIA PRO para Hardware ID: $hwid ===" -ForegroundColor Cyan
    Write-Host $b64
    Write-Host ""
} else {
    Write-Host "Uso:"
    Write-Host "  .\Gen-License.ps1 -HardwareID <ID>   # licencia Pro"
    Write-Host "  .\Gen-License.ps1 -Tech               # licencia Tecnico"
    Write-Host "  .\Gen-License.ps1 -GenerateKeys       # rotar claves RSA"
}

$sha.Dispose()
$rsa.Dispose()
