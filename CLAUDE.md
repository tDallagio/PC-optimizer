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
- Estilos de boton: `BtnMain` / `BtnSec` / `BtnPreset` / `BtnDanger` / `BtnNav` / `BtnNavActive` / `BtnNavLicense` / `BtnNavIcon` / `BtnNavIconActive` / `BtnGlossyCyan` / `BtnGlossyDark` / `BtnToggleOn` / `BtnToggleOff` (+ `CardGlossy` para cards)

## Orden de tabs (SelectedIndex / SetActiveNav en MainWindow.xaml.cs)
Corte 27: Consola dejo de ser tab (overlay). Corte 30: Info del sistema dejo de ser tab; **Home**
paso a ser la ENTRADA de la app. Corte 56: Tuning Avanzado dejo de ser tab (sus 3 controles
migraron a Tweaks); Tweaks/Network/Limpieza corrieron un indice hacia abajo. Corte 66: el tab
**Optimizar clasico** (el original, indice 0) se retiro completo — era la pantalla mas antigua y
con mas superficie de toda la app, con sus 26/26 tweaks + Limpieza ya migrados a Tweaks/Network/
Limpieza desde los cortes anteriores (ver `docs/ARQUITECTURA_TWEAKS.md` 7.2). TODOS los indices
restantes corrieron un lugar hacia abajo; Home arranca ahora en `SetActiveNav(1)`.
- 0 = Herramientas
- 1 = **Home** (dashboard de entrada; ex Info del sistema). Item `navHome`, arriba de todo del sidebar.
- 2 = Arranque
- 3 = Bloatware
- 4 = Historial
- 5 = Ajustes
- 6 = Licencia
- 7 = **Tweaks** (corte 38, piloto Fase A; Scheduler CPU/HAGS/Politica termica sumados en el corte
  56, ex tab Tuning Avanzado). Grupo propio en el sidebar (`navTweaks`), separado de
  PRINCIPAL/SISTEMA. Cards generadas en codigo desde `App.Tweaks.All` (`TweakRegistry`), NO en
  XAML a mano. Universo completo de 27 tweaks (24 acá + 3 en Network) — ver
  `docs/ARQUITECTURA_TWEAKS.md`.
- 8 = **Network** (corte 47, Fase C Paso 1; DNS + DNSFlush sumados en el Paso 2, corte 48). Grupo
  propio en el sidebar (`navNetwork`), hermano de Tweaks (no anidado bajo el). Misma mecanica que
  Tweaks: cards generadas en codigo (`LoadNetworkTabAsync`, `MainWindow.xaml.cs`) desde
  `App.Tweaks.All` filtrado a `Categoria=="Red"` — comparten el mismo
  `_tweakCardRefs`/`BuildTweakCard`/`UpdateTweakCardUi` que Tweaks (`LoadTweaksTabAsync` excluye esa
  categoria). Nagle y TCP viven ahi (mudados desde Tweaks, misma definicion/Id, sin cambio de
  logica) junto con DisableIPv6. DNS (selector de 4 proveedores + revert real por-adaptador,
  `DnsPresetService.cs`) y DNSFlush (primer caso de `QuickActionRegistry.cs`, acciones de un solo
  click sin estado) son card propias hechas a mano, no generadas por `BuildTweakCard` — ninguno de
  los dos encaja en el molde `TweakDefinition`.
- 9 = **Limpieza** (corte 49, Fase C Paso 3). Grupo propio en el sidebar (`navLimpieza`), hermano
  de Tweaks/Network — cierra la reorganizacion que saca categorias del item unico "Tweaks". UNA sola
  card hecha a mano (`LoadLimpiezaTabAsync`/`RunLimpiezaAsync`, `MainWindow.xaml.cs`) con los 8
  items de limpieza ya existentes en `OptimizationService.CleanupTweaks` (subido a `internal` para
  reusarlo) + `ConfirmOptimizationDialog` (compartido con el ex-tab Optimizar clasico, retirado en
  el corte 66) antes de ejecutar. Sin revert (borrar temporales/cache/logs no es reversible) y sin
  TweakStateStore de por medio.
- Consola: ya NO es tab. Overlay modal (`consoleOverlay`) via `OpenConsoleOverlay()` (icono `navConsola`,
  badge de errores, o automatico al correr optimizacion/bloatware).
- Info del sistema: ya NO es tab. Hardware + componentes -> overlay `systemInfoOverlay`
  (`OpenSystemInfoOverlay()`, boton "System Info" del Home). El monitor en vivo alimenta los medidores
  circulares del Home; el score alimenta la malla de salud del Home.
- Tuning Avanzado: ya NO es tab (corte 56). Scheduler de CPU (Win32PrioritySeparation), HAGS y
  Politica termica migraron a la seccion **Tweaks** (categoria "Sistema y Rendimiento"), con revert
  real via `TweakStateStore` en vez del viejo mecanismo que llamaba `BackupService` directo.
- **Optimizar (clasico): ya NO es tab (corte 66).** Retirado completo — XAML (`<TabItem
  Header="Optimizar">` + `footerBar` anidado adentro) y code-behind exclusivo
  (`OnRunOptimizationAsync`, `FinishOptimizationAsync`, `ShowCompareDialog`, `ApplyPreset`,
  `AllOptCheckboxes`, `GetCurrentSel`, `SelectAll`, `UpdateDnsHint`, `UpdatePlanSummary`,
  `SaveProfile`/`LoadProfile`, `OptimizationService.BuildActionPlan`) eliminados; `FinishOptimizationDialog`
  y `CompareDialog` (clases enteras, sin otro caller) tambien. `OptimizationService.RunAsync`/
  `GetPreset` **NO se tocaron** — siguen intactos como motor exclusivo del modo `-Silent` de CLI
  (`App.RunSilentAsync`, `App.xaml.cs`), que ya llamaba a esos dos directo sin pasar por la pantalla
  ni por ningun metodo de `MainWindow.xaml.cs`. `btnExportHTML` (Consola) quedo oculto
  (`Visibility="Collapsed"`) por falta de fuente de datos; `ExportHtmlReportAsync` se elimino sin
  caller. `btnHomeOptimize` ahora navega a Tweaks (no a Optimizar). El banner de trial
  (`bannerTrial`/`lblTrialText`/`btnTrialUpgrade`, `UpdateTrialBanner`) vivia anidado en `footerBar`
  — se reubico en Home (nueva entrada de la app) en vez de perderse. El paso de seleccion de perfil
  del `OnboardingDialog` (aplicaba `ApplyPreset`) se saco del wizard, que quedo en 3 pasos.

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
