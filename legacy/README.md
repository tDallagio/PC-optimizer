# WinBoost — version PowerShell (descontinuada)

Esta carpeta contiene la version original de WinBoost escrita en PowerShell 5.1 + WPF
(`OptimizarPC_App.ps1` + `OptimizarPC_UI.xaml`), reemplazada por la version C#/.NET 8 WPF
en `src-csharp/`, que es la unica version oficial y soportada del proyecto (ver el `README.md`
de la raiz).

**Estado: descontinuada. Sin soporte ni actualizaciones.** No se corrigen bugs, no se agregan
features y no se distribuye (el auto-updater y el release oficial en GitHub apuntan solo al
instalador C#). Se conserva en el repo por historial, no para uso.

## Contenido

- `OptimizarPC_App.ps1` — logica principal (10400+ lineas)
- `OptimizarPC_UI.xaml` — interfaz WPF (version PS1)
- `Build.ps1` — compilaba el `.ps1` a `.exe` via `ps2exe`
- `EJECUTAR_COMO_ADMIN.bat` — launcher para desarrollo
- `installer/WinBoost.iss` — script Inno Setup del instalador PS1
- `installer/Output/` — instaladores compilados historicos (no se generan mas)
- `dist/` — artefactos de build historicos de `ps2exe` (no se generan mas)
