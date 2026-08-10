@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0OptimizarPC_App.ps1"

if %errorLevel% neq 0 (
    echo.
    echo  ERROR: El script cerro con codigo %errorLevel%
    echo  Revisa el mensaje de error arriba.
    echo.
    pause
)
