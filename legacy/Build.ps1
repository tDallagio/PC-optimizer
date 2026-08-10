#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script - WinBoost v4.0
    Compila OptimizarPC_App.ps1 a WinBoost.exe y lo firma con cert autofirmado.
    Genera la carpeta dist\ lista para ser empaquetada con el instalador.

.NOTES
    Uso:
        .\Build.ps1                    # compilar + firmar
        .\Build.ps1 -SkipSign         # solo compilar, sin firma

    Prerequisito para el instalador:
        1. Ejecutar este script primero para generar dist\
        2. Compilar installer\WinBoost.iss con Inno Setup 6

    Icono opcional:
        Colocar WinBoost.ico en la raiz del proyecto.
        Si no existe, el exe se compila sin icono personalizado.
#>

param(
    [switch]$SkipSign
)

$ErrorActionPreference = "Stop"

$ROOT = $PSScriptRoot
$DIST = Join-Path $ROOT "dist"
$SRC  = Join-Path $ROOT "OptimizarPC_App.ps1"
$XAML = Join-Path $ROOT "OptimizarPC_UI.xaml"
$EXE  = Join-Path $DIST "WinBoost.exe"
$ICO  = Join-Path $ROOT "WinBoost.ico"

Write-Host ""
Write-Host "=== WinBoost Build Script ===" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------
# 1. Verificar fuentes
# ----------------------------------------------------------------
if (-not (Test-Path $SRC)) {
    Write-Host "ERROR: No se encontro OptimizarPC_App.ps1 en $ROOT" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $XAML)) {
    Write-Host "ERROR: No se encontro OptimizarPC_UI.xaml en $ROOT" -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------
# 2. Carpeta de salida
# ----------------------------------------------------------------
if (-not (Test-Path $DIST)) {
    New-Item -ItemType Directory -Path $DIST | Out-Null
}
Write-Host "Salida: $DIST" -ForegroundColor Gray

# ----------------------------------------------------------------
# 3. Instalar / importar ps2exe
# ----------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe -EA SilentlyContinue)) {
    Write-Host "Instalando modulo ps2exe..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -Force -EA Stop
Write-Host "ps2exe listo." -ForegroundColor Gray

# ----------------------------------------------------------------
# 4. Compilar PS1 -> EXE
# ----------------------------------------------------------------
Write-Host "Compilando..." -ForegroundColor Cyan

$ps2Params = @{
    inputFile    = $SRC
    outputFile   = $EXE
    title        = "WinBoost"
    description  = "Optimizador de rendimiento para Windows"
    product      = "WinBoost"
    company      = ""
    version      = "4.1.0.0"
    requireAdmin = $true
    noConsole    = $true
    x64          = $true
}

if (Test-Path $ICO) {
    $ps2Params["iconFile"] = $ICO
    Write-Host "Usando icono: $ICO" -ForegroundColor Gray
} else {
    Write-Host "Icono no encontrado (WinBoost.ico) - compilando sin icono." -ForegroundColor Yellow
}

Invoke-ps2exe @ps2Params

if (-not (Test-Path $EXE)) {
    Write-Host "ERROR: ps2exe no genero el ejecutable." -ForegroundColor Red
    Write-Host "Revisa que el PS1 no tenga errores de sintaxis y que ps2exe este instalado correctamente." -ForegroundColor Yellow
    exit 1
}

$exeSize = [math]::Round((Get-Item $EXE).Length / 1KB, 0)
Write-Host "Compilado OK  ($exeSize KB)" -ForegroundColor Green

# ----------------------------------------------------------------
# 5. Copiar XAML junto al exe
# ----------------------------------------------------------------
Copy-Item $XAML "$DIST\OptimizarPC_UI.xaml" -Force
Write-Host "XAML copiado." -ForegroundColor Gray

# ----------------------------------------------------------------
# 6. Firmar con certificado autofirmado
# ----------------------------------------------------------------
if (-not $SkipSign) {
    Write-Host "Firmando exe..." -ForegroundColor Cyan

    $certSubject = "CN=WinBoost"
    $cert = Get-ChildItem Cert:\CurrentUser\My -EA SilentlyContinue |
            Where-Object {
                $_.Subject -eq $certSubject -and
                $_.HasPrivateKey -and
                $_.NotAfter -gt (Get-Date)
            } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1

    if (-not $cert) {
        Write-Host "Creando certificado de firma de codigo..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate `
            -Subject           $certSubject `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -Type              CodeSigning `
            -HashAlgorithm     SHA256 `
            -KeyUsage          DigitalSignature `
            -NotAfter          (Get-Date).AddYears(5)
        Write-Host "Certificado: $($cert.Thumbprint)" -ForegroundColor Green
    } else {
        Write-Host "Cert existente: $($cert.Thumbprint) (vence $($cert.NotAfter.ToString('yyyy-MM-dd')))" -ForegroundColor Gray
    }

    $sig = Set-AuthenticodeSignature `
        -FilePath      $EXE `
        -Certificate   $cert `
        -HashAlgorithm SHA256 `
        -TimestampServer "http://timestamp.digicert.com"

    if ($sig.Status -eq "Valid") {
        Write-Host "Firmado correctamente (Valid)." -ForegroundColor Green
    } else {
        # UnknownError es normal cuando el cert autofirmado no esta en Trusted Root
        Write-Host "Estado firma: $($sig.Status)" -ForegroundColor Yellow
        Write-Host "Nota: 'UnknownError' es normal con cert autofirmado en equipos de desarrollo." -ForegroundColor Gray
    }
} else {
    Write-Host "Firma omitida (-SkipSign)." -ForegroundColor Gray
}

# ----------------------------------------------------------------
# 7. Resumen
# ----------------------------------------------------------------
Write-Host ""
Write-Host "=== Build completado ===" -ForegroundColor Green
Get-ChildItem $DIST | ForEach-Object {
    $sz = [math]::Round($_.Length / 1KB, 0)
    Write-Host ("  {0,-35} {1,6} KB" -f $_.Name, $sz) -ForegroundColor White
}
Write-Host ""
Write-Host "Siguiente paso: compilar installer\WinBoost.iss con Inno Setup 6" -ForegroundColor Cyan
Write-Host "Descarga: https://jrsoftware.org/isdl.php" -ForegroundColor Gray
Write-Host ""
