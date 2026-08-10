# WinBoost

## Archivos del proyecto
- `src-csharp/` — proyecto C#/.NET 8 WPF, unica version oficial y distribuida (ver
  "Convenciones C#" abajo)
- `version.json` — check de updates en GitHub
- `Create-Icon.ps1` — genera `WinBoost.ico` (usado por el instalador y el `.csproj` C#)
- `Gen-License.ps1` — emision de licencias (uso interno, NO trackeado en git)
- `docs/PENDIENTES.md` — features pendientes con checkboxes
- `docs/CHANGELOG.md` — historial completo de implementaciones
- `legacy/` — version PowerShell descontinuada (jubilada en el corte 6.3). Sin soporte,
  no se desarrolla mas. Ver `legacy/README.md`. No tocar salvo pedido explicito del usuario.

## Stack
- C# / .NET 8, WPF
- Nombre de la app: **WinBoost**

## Migracion a C# / WPF — COMPLETA (corte 6.3)
La migracion de PowerShell 5.1 a C#/WPF esta cerrada. El proyecto en `src-csharp/` es la
UNICA version oficial: el instalador, el auto-updater y el release de GitHub apuntan solo
a ella. El `.ps1` original (`OptimizarPC_App.ps1` + `OptimizarPC_UI.xaml`) fue jubilado a
`legacy/`. El XAML activo es `src-csharp/WinBoost/MainWindow.xaml` — ya NO se comparte con
el XAML legacy (`legacy/OptimizarPC_UI.xaml`), que quedo congelado y diverge del actual.

## Convenciones C# (src-csharp)
- .NET 8, WPF. Nullable habilitado.
- async/await + Task.Run para TODO trabajo pesado; nunca bloquear el hilo UI.
- Actualizar la UI desde background via Dispatcher.
- Los elementos con x:Name en el XAML son campos tipados generados; NO usar FindName
  manual.
- Brushes y colores desde recursos XAML tipados.
- P/Invoke nativo en una clase NativeMethods dedicada.
- Registrar cada cambio de codigo (feature, fix o mantenimiento) en CHANGELOG.md.
- Validacion funcional de un release candidate: SIEMPRE sobre el .exe generado por
  `src-csharp/Publish-CSharp.ps1` (self-contained single-file), NUNCA solo sobre
  `dotnet build` ni `dotnet run`. `dotnet build` sirve para validar que compila
  (sintaxis) durante el desarrollo; NO sustituye la validacion funcional sobre el
  publicado. Motivo: el single-file/self-contained cambia la carga de assemblies,
  la resolucion de rutas y la extraccion a disco respecto del Debug — hay bugs que
  solo existen en ese modo (ej. el FileNotFoundException de
  System.Text.RegularExpressions por cache de extraccion parcial, ver CHANGELOG.md).

## Codigo legacy (`legacy/`)
Congelado, sin soporte. Contiene una clave publica RSA VIEJA y rotada (ver
`legacy/README.md` y `docs/CHANGELOG.md`) — nunca redistribuir ni reactivar. Las reglas de
PowerShell 5.1/XAML con las que se desarrollo (operadores prohibidos, patron `Get-Ctrl`/
`Flush-UI`, etc.) quedan documentadas en el historial de `docs/CHANGELOG.md`, no aca; no
aplican a desarrollo activo. Si alguna vez hace falta tocar ese codigo (deberia ser
excepcional y a pedido explicito), revisar ese historial antes de editar.

## Estilo visual
- Fondo `#0D0D0D` | Cards `#161616` | Acento `#00C8FF`
- Tipografia Segoe UI | CornerRadius 6-8
- Colores de estado: ok `#22C55E` | warn `#F59E0B` | err `#EF4444` | info `#00C8FF`
- Estilos de boton: `BtnMain` / `BtnSec` / `BtnPreset` / `BtnDanger` / `BtnNav` / `BtnNavActive` / `BtnNavLicense` / `BtnToggleOn` / `BtnToggleOff`

## Orden de tabs (SelectedIndex / SetActiveNav en MainWindow.xaml.cs)
- 0 = Optimizar
- 1 = Herramientas
- 2 = Info del sistema
- 3 = Arranque
- 4 = Bloatware
- 5 = Consola
- 6 = Historial
- 7 = Ajustes
- 8 = Licencia
- 9 = Tuning Avanzado

## Modulos implementados
Ver `docs/PENDIENTES.md` (fases 0-6, todas completas salvo pendientes de producto/
distribucion) y `docs/CHANGELOG.md` para el detalle de cada implementacion.

## Arranque de sesion
1. Lee `CLAUDE.md` — reglas, stack
2. Lee `docs/PENDIENTES.md` — que falta implementar (checkboxes)
3. Lee `docs/CHANGELOG.md` — que se implemento (historial)

Continuar con el primer item sin tilde `[ ]` en PENDIENTES.md

## Probar
`dotnet build src-csharp\WinBoost\WinBoost.csproj` valida que compila. Para validacion
funcional real: `.\src-csharp\Publish-CSharp.ps1` y correr el .exe publicado (ver regla en
"Convenciones C#").
