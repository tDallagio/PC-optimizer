#Requires -Version 5.1
<#
.SYNOPSIS
    Publish + instalador - WinBoost (C#/WPF)
    Compila la app C# a un .exe self-contained single-file (win-x64) y arma
    el instalador Inno Setup. No toca el .ps1 legacy ni su Build.ps1/iss.

.NOTES
    Uso:
        .\src-csharp\Publish-CSharp.ps1                # publish + instalador
        .\src-csharp\Publish-CSharp.ps1 -SkipInstaller # solo publish (.exe)

    Prerequisitos:
        - .NET 8 SDK (dotnet publish)
        - Inno Setup 6 (ISCC.exe) para el paso de instalador; si no esta
          instalado, el script publica igual y avisa que salteo ese paso.

    Salida:
        src-csharp\WinBoost\bin\publish\win-x64\WinBoost.exe   (self-contained)
        src-csharp\installer\Output\WinBoost_Setup_<version>.exe
#>

param(
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

$ROOT       = $PSScriptRoot
$PROJ       = Join-Path $ROOT "WinBoost\WinBoost.csproj"
$PUBLISHDIR = Join-Path $ROOT "WinBoost\bin\publish\win-x64"
$EXE        = Join-Path $PUBLISHDIR "WinBoost.exe"
$ISS        = Join-Path $ROOT "installer\WinBoost.iss"
$APPXAML_CS = Join-Path $ROOT "WinBoost\App.xaml.cs"

Write-Host ""
Write-Host "=== WinBoost C# - Publish self-contained single-file ===" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------
# 1. Version desde App.xaml.cs (fuente de verdad: App.Version)
# ----------------------------------------------------------------
if (-not (Test-Path $APPXAML_CS)) {
    Write-Host "ERROR: no se encontro $APPXAML_CS" -ForegroundColor Red
    exit 1
}
$appSrc = Get-Content $APPXAML_CS -Raw
$m = [regex]::Match($appSrc, 'Version\s*=\s*"([^"]+)"')
if (-not $m.Success) {
    Write-Host "ERROR: no se pudo leer App.Version de App.xaml.cs" -ForegroundColor Red
    exit 1
}
$VERSION = $m.Groups[1].Value
Write-Host "Version detectada: $VERSION" -ForegroundColor Gray

# ----------------------------------------------------------------
# 2. dotnet publish (self-contained, single-file, win-x64)
# ----------------------------------------------------------------
Write-Host "Publicando..." -ForegroundColor Cyan

if (Test-Path $PUBLISHDIR) {
    Remove-Item $PUBLISHDIR -Recurse -Force
}

dotnet publish $PROJ -c Release -p:PublishProfile=win-x64-selfcontained
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: dotnet publish fallo (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $EXE)) {
    Write-Host "ERROR: no se genero $EXE" -ForegroundColor Red
    exit 1
}

$exeSizeMB = [math]::Round((Get-Item $EXE).Length / 1MB, 1)
Write-Host "Publish OK: $EXE  ($exeSizeMB MB)" -ForegroundColor Green

$sha256 = (Get-FileHash $EXE -Algorithm SHA256).Hash
Write-Host "SHA256 (exe): $sha256" -ForegroundColor Gray

# ----------------------------------------------------------------
# 3. Chequeo estatico del bundle (sin ejecutarlo)
# ----------------------------------------------------------------
# No se lanza el exe aca: WinBoost requiere elevacion (app.manifest
# requireAdministrator), asi que cualquier arranque dispara un UAC real en el
# escritorio del usuario -- no es algo para hacer sin avisar desde un script
# automatico. Verificacion en frio: cabecera PE valida + que sea REALMENTE
# single-file (nada de DLLs de runtime sueltas al lado, salvo el .pdb).
$header = [System.IO.File]::ReadAllBytes($EXE) | Select-Object -First 2
if (-not ($header[0] -eq 0x4D -and $header[1] -eq 0x5A)) {
    Write-Host "ERROR: $EXE no tiene cabecera PE valida (MZ)." -ForegroundColor Red
    exit 1
}
$stragglers = Get-ChildItem $PUBLISHDIR -File |
    Where-Object { $_.Extension -notin @(".exe", ".pdb") }
if ($stragglers) {
    Write-Host "AVISO: quedaron archivos sueltos ademas del single-file:" -ForegroundColor Yellow
    $stragglers | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Yellow }
} else {
    Write-Host "Bundle OK: single-file real, sin dependencias sueltas." -ForegroundColor Green
}
Write-Host "Prueba manual pendiente: correr $EXE, aceptar el UAC y confirmar que" -ForegroundColor Gray
Write-Host "abre, la UI rendea y el monitor en tiempo real anda." -ForegroundColor Gray

# ----------------------------------------------------------------
# 4. Instalador (Inno Setup)
# ----------------------------------------------------------------
if ($SkipInstaller) {
    Write-Host ""
    Write-Host "Instalador salteado (-SkipInstaller)." -ForegroundColor Gray
} else {
    $isccPath = $null
    $isccCmd  = Get-Command "ISCC.exe" -EA SilentlyContinue
    if ($isccCmd) { $isccPath = $isccCmd.Source }
    if (-not $isccPath) {
        foreach ($cand in @(
            "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
            "C:\Program Files\Inno Setup 6\ISCC.exe"
        )) {
            if (Test-Path $cand) { $isccPath = $cand; break }
        }
    }

    if (-not $isccPath) {
        Write-Host ""
        Write-Host "AVISO: no se encontro ISCC.exe (Inno Setup 6). Instalador salteado." -ForegroundColor Yellow
        Write-Host "Descarga: https://jrsoftware.org/isdl.php" -ForegroundColor Gray
    } else {
        Write-Host ""
        Write-Host "Compilando instalador..." -ForegroundColor Cyan
        & $isccPath $ISS "/DAppVersion=$VERSION"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: ISCC fallo (exit $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }

        $setupExe = Join-Path $ROOT "installer\Output\WinBoost_Setup_$VERSION.exe"
        if (Test-Path $setupExe) {
            $setupSizeMB = [math]::Round((Get-Item $setupExe).Length / 1MB, 1)
            $setupSha256 = (Get-FileHash $setupExe -Algorithm SHA256).Hash
            Write-Host "Instalador OK: $setupExe  ($setupSizeMB MB)" -ForegroundColor Green
            Write-Host "SHA256 (instalador): $setupSha256" -ForegroundColor Gray
        } else {
            Write-Host "AVISO: ISCC termino OK pero no se encontro $setupExe" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host ""
