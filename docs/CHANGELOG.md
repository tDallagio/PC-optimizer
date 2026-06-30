# WinBoost — Changelog

> Historial de implementaciones en orden cronológico.
> Usar para armar release notes al lanzar.

---

## C# Procesos lazy + autorefresh ON, reorden de tabs y limpieza del sidebar

Tres cambios sobre la app C# (`src-csharp/WinBoost/`): procesos pesados con carga lazy y
auto-refresh encendido por defecto, reorden de las pestañas del sidebar, y se quita el
bloque de info de hardware del sidebar.

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml` — (1) reorden de los `<TabItem>` dentro de `mainTabs`
  al nuevo orden de indices; (2) reorden visual de los botones de navegacion del sidebar;
  (3) eliminado el bloque "Info sistema compacta" (CPU/GPU/RAM/disco) que estaba arriba de
  "Licencia"; el `Grid` del sidebar pasa de 4 a 3 filas y se renumeran `btnErrBadge` (Row 1)
  y `navLicencia` (Row 2) para que no quede hueco.
- `src-csharp/WinBoost/MainWindow.xaml.cs` — array `_navButtons`, handlers `Click`, y TODAS
  las referencias por indice (`SetActiveNav`, `mainTabs.SelectedIndex == N`) remapeadas al
  nuevo orden. Nuevo flag `_procLoaded` + `InitProcessesAsync()` (carga lazy de Herramientas:
  refresca la lista una vez y arranca el timer si el auto-refresh esta ON). `ToggleProcTimer`
  persiste la eleccion en settings; `StartProcTimer` toma el intervalo de `ProcRefreshSec`.
  `PopulateSystemInfoControls` ya no escribe en los labels eliminados del sidebar.
- `src-csharp/WinBoost/Services/AppSettings.cs` — nuevo `ProcAutoRefresh` (default `true`).
- `src-csharp/WinBoost/Services/SettingsService.cs` — carga/persistencia de `ProcAutoRefresh`.

**Detalle**

CAMBIO 1 — Procesos pesados. La lista de procesos pesados ahora se carga sola la primera vez
que se entra a Herramientas (carga lazy, mismo patron que Bloatware), no al iniciar la app.
El auto-refresh arranca ENCENDIDO por defecto (`ProcAutoRefresh = true`), refrescando cada
`ProcRefreshSec` (~3s) fuera del hilo UI via `App.Processes.GetHeavyProcessesAsync` +
`Task.Run`, sin trabar la UI. El estado del toggle se guarda en `settings.json`. En PS5.1 esto
estaba OFF porque el refresh sincrono trababa la UI; en C# (async) ya no aplica.

CAMBIO 2 — Reorden de tabs. Nuevo orden de indices (sidebar de arriba hacia abajo):
0 Optimizar · 1 Herramientas · 2 Info del sistema · 3 Arranque · 4 Bloatware · 5 Consola ·
6 Historial · 7 Ajustes. Licencia (8) y Tuning (9) quedan aparte como hasta ahora. Se movieron
las TRES cosas en sincronia: orden visual de los botones, orden de los `TabItem`, e indices que
cada boton pasa a `SetActiveNav` + toda referencia por indice (footer solo en Optimizar idx 0;
score widget abre Info idx 2; navegaciones a Consola idx 5, Historial idx 6, Bloatware idx 4;
lazy-loads de Arranque idx 3, Info idx 2, Bloatware idx 4, Historial idx 6, Tuning idx 9).

CAMBIO 3 — Sidebar mas limpio. El bloque informativo de hardware (CPU/Ryzen, GPU/RX, RAM, tipo
de disco) arriba de "Licencia" era solo display, no acoplado a funcionalidad. Se quito del XAML
y se dejaron de poblar sus labels en el code-behind. El layout del sidebar se ajusto (una fila
menos) para que no quede hueco.

**Verificacion**

`dotnet build -c Debug` correcto: 0 advertencias, 0 errores. XAML valido (`ElementTree`); orden
de `TabItem` y de botones confirmado por script. Pendiente de prueba visual del usuario: que la
lista de procesos no "salte"/parpadee de forma molesta al reordenarse en cada refresh (la lista
se reconstruye completa cada ~3s y se ordena por CPU, asi que el reordenamiento es posible —
reportar si molesta).

---

## C# Bloatware — escaneo automatico (lazy) al entrar a la pestaña

C# Bloatware: la lista se escanea sola la primera vez que se entra a la tab (carga lazy),
en vez de quedar vacia hasta apretar "Actualizar lista".

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml.cs` — nuevo flag `_bloatLoaded`; en el handler de
  cambio de tab, al seleccionar Bloatware (idx 6) por primera vez se dispara
  `ScanBloatwareAsync()`. Las siguientes entradas reusan la lista cacheada; el boton
  "Actualizar lista" sigue refrescando manualmente.

**Detalle**

El scan enumera AppX + consulta winget y tarda, por eso NO se corre en el arranque (penalizaria
el startup de toda la app) sino la primera vez que el usuario entra a la pestaña. Mientras
escanea se muestra el estado "Escaneando..." que ya existia en `ScanBloatwareAsync`, para que
no parezca colgado. Mismo patron de carga lazy que Arranque (2), Historial (5) y Tuning (9).

---

## C# Driver Store — movido a Herramientas + fix de deteccion de obsoletos (bug de localizacion)

C# Driver Store: "Limpieza del Driver Store" movida de Tuning a Herramientas; arreglada la
deteccion de drivers obsoletos, que SIEMPRE daba vacio por un bug de parseo (salida de pnputil
localizada en español que las regex en ingles nunca matcheaban).

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml` — card "LIMPIEZA DEL DRIVER STORE" movida del tab Tuning
  (CARD 5) al tab Herramientas (Row 4, ColSpan 2, con la franja de acento lateral al estilo de
  las demas cards de Herramientas). Tuning conserva Scheduler CPU, HAGS y politica termica.
- `src-csharp/WinBoost/Services/TuningService.cs` — `ParsePnpUtil`: regex de campos ahora
  matchea ingles Y español (`Published Name`/`Nombre publicado`, `Original Name`/`Nombre
  original`, `Driver Version`/`Versi(o)n del controlador`, `Driver Date`/`Fecha del
  controlador`), con `IgnoreCase` y `Versi.n` tolerante al acento (independiente de la
  codificacion de captura). `GetObsolete`: agrupa con `OrdinalIgnoreCase` y ordena por un
  ranking real (nuevo `DriverRank`: version numerica + fecha) en vez de comparar el string de
  version ordinal.

**Detalle — verificacion solicitada (bug vs sistema limpio)**

Era **BUG de parseo**, no sistema limpio. Diagnostico corriendo `pnputil /enum-drivers` en el
equipo del usuario (Windows en español):

- La salida viene localizada: `Nombre publicado:`, `Nombre original:`, `Versión del
  controlador:`, etc. Las regex originales (mirror del PS1) solo matcheaban las etiquetas en
  ingles, por lo que parseaban **0 paquetes** -> 0 grupos -> siempre "no hay obsoletos".
- Con el parser bilingüe: **48 paquetes** parseados y **6 obsoletos** detectados (amdgpio2,
  amdgpio3, amdpcidev, amdpsp, amdsdwc, smbusamd — cada uno con 2 versiones en el Driver Store).
  El sistema SI tenia duplicados; estaban ocultos por el bug.
- Nota: el mismo bug existe en el PS1 legacy (Parse-PnpUtilOutput usa las mismas etiquetas en
  ingles). Queda fuera de alcance de esta tarea (C#), pero documentado aca.

**Acoplamiento / detalle adicional**

- El campo de version de pnputil combina fecha + version en una linea ("MM/DD/YYYY V.V.V.V"),
  asi que el `Sort` ordinal original elegia mal "la mas nueva" (ej. "9..." > "10..."). El nuevo
  `DriverRank` extrae la version con puntos y la fecha con barras por separado y compara por
  (Version, DateTime), eligiendo correctamente cual conservar y cuales marcar obsoletas.
- El cableado de la card (`btnScanDrvStore`, `btnDriverBackup`, `btnDriverDelete`,
  `lblDriverStatus`, `drvListScroll`, `icDrvStore`) no cambio: se conservaron los mismos
  x:Name al mover el XAML, asi que el code-behind sigue operativo sin tocar.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# reorg visual: Info del sistema 2x2 + monitor con barra de % usado de C:

C# reorg visual: info de componentes movida de Tuning a Info del sistema; monitor reubicado
y con barra de % usado de C: ademas de la de actividad; espacio en disco integrado al monitor.

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml` — tab Info del sistema: cuadrante abajo-izquierda
  pasa a "INFORMACION DE COMPONENTES" (`icComponentsInfo`), cuadrante abajo-derecha pasa a
  "MONITOR EN TIEMPO REAL"; quitado el cuadrante "ESPACIO EN DISCO" (`diskPanel`). Monitor con
  6 barras: CPU, RAM, Disco (act.), C: (uso) [nueva, `barDiskUsageFill`/`lblDiskUsagePct`],
  CPU Temp, GPU Temp. Tab Tuning: eliminada la CARD 4 "INFORMACION DE COMPONENTES".
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `RenderTuningInfo` -> `RenderComponentsInfo`
  (rinde en `icComponentsInfo`); nuevo `LoadComponentsInfoAsync` con cache `_extendedInfo`,
  cableado en el select de la tab Info (idx 4); removidos `PopulateDiskPanel`/`BuildDriveRow`/
  `GbInt` y su llamada; `Metrics` gana `SysDiskUsagePct`, `ReadMetrics` lo calcula via
  `DriveInfo` del disco del sistema, `OnMonitorTick` pinta la barra C: (uso) por umbral
  (>90% rojo, >75% amarillo, resto acento). Quitada la carga de info de componentes de
  `LoadTuningTabAsync`.

**Detalle**

Reorganizacion puramente visual (no cambia logica de calculo). El layout de Info del sistema
queda en 2x2 parejo: equipo (arriba-izq), salud/rendimiento (arriba-der), componentes
(abajo-izq), monitor (abajo-der).

- **Componentes:** mismas filas que el PS1 (CPU nucleos/hilos, cache L3, RAM velocidad, RAM
  slots, GPU, VRAM, GPU driver, HAGS), reusando la misma fuente (`GetExtendedInfoAsync`). La
  info extendida (WMI) se lee una sola vez y se cachea; en cada entrada a la tab se re-renderiza
  desde la cache para reflejar el estado actual de HAGS.
- **HAGS — acoplamiento atendido:** solo se movio la fila INFORMATIVA de HAGS. El control de
  activar/desactivar (`lblHagsState`/`btnHagsOn`/`btnHagsOff`/`lblHagsResult`) se QUEDA intacto
  en Tuning. Como la fila informativa y el control leen el mismo `GetHagsState()`, el re-render
  desde cache al entrar a Info mantiene ambos consistentes tras togglear HAGS en Tuning.
- **Monitor:** la barra nueva "C: (uso)" NO reemplaza a "Disco (act.)" (actividad % Disk Time):
  quedan las dos, etiquetadas para distinguirlas. El % usado de C: sale de `DriveInfo` del disco
  del sistema, leido en cada tick fuera del hilo UI (Task.Run), sin costo perceptible.
- **Espacio en disco:** el cuadrante separado (discos usado/libre) se quito; su funcion la
  absorbe la barra "C: (uso)". El detalle por-disco usado/libre quedo FUERA (decision del
  usuario, no se reubico por cuenta propia).

`dotnet build`: 0 errores, 0 advertencias.

---

## C# Herramientas — removido el inventario de drivers

C# Herramientas: removido el inventario de drivers (decision de producto; sin valor
accionable). Dispositivos con problemas se conserva.

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml` — eliminada la card "INVENTARIO DE DRIVERS" (Row 4)
- `src-csharp/WinBoost/MainWindow.xaml.cs` — eliminados `ScanDriversAsync`, `PopulateDriverClassFilter`,
  `OnDriverClassChanged`, `RenderDriverInventory`, el campo `_driverList`, el alias `using DriverEntry`
  y el cableado de `btnScanDrivers`/`cboDriverClass`
- `src-csharp/WinBoost/Services/DeviceService.cs` — eliminados el record `DriverEntry`,
  `GetDriverInventoryAsync`, `GetDriverInventory` y el helper `ParseWmiDate`

**Detalle**

Para actualizar drivers ya existen GeForce Experience / Adrenalin / Windows Update, asi que el
inventario (lista de drivers con version/fecha/firma + filtro por clase) no aportaba accion.

- **Dispositivos con problemas SE CONSERVA intacto** (funcion distinta): `GetProblemDevicesAsync`
  via `Win32_PnPEntity` con `ConfigManagerErrorCode <> 0`, su boton, lista y status siguen operativos.
- **Acoplamiento:** ninguno que requiriera cuidado en el layout. Las dos cards eran filas
  full-width independientes y apiladas (`Grid.ColumnSpan="2"`, Row 3 dispositivos / Row 4 drivers),
  no compartian fila ni grid. Al quitar drivers la `RowDefinition` Auto sobrante colapsa a 0 altura,
  sin hueco. El unico cruce a nivel de codigo: ambas vivian en `DeviceService` y compartian el
  bloque de wiring "Dispositivos/Drivers (2.5)" — se separo dejando solo lo de dispositivos.

`dotnet build`: 0 errores, 0 advertencias. XAML validado con ElementTree.

---

## C# Info sistema — panel de espacio en disco: de "top 10 carpetas" a vista de discos

C# Info sistema: panel de espacio en disco cambiado de "top 10 carpetas pesadas" a vista de
discos (usado/libre por unidad, estilo Windows); removido el scan async de carpetas.

**Archivos modificados**
- `src-csharp/WinBoost/Services/SystemInfoService.cs` — eliminado `ScanTopFoldersAsync` + record `DiskFolderInfo`
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `PopulateDiskPanel` + `BuildDriveRow` reemplazan `ScanDiskSpaceAsync`/`BuildDiskRow`

**Detalle**

Decision de producto: la card "ESPACIO EN DISCO" (tab Info) deja de listar las 10 carpetas mas
pesadas de C: y pasa a mostrar los discos del equipo con su barra usado/libre, al estilo del
panel de Almacenamiento de Windows.

- `PopulateDiskPanel` enumera `DriveInfo.GetDrives()` filtrando `DriveType.Fixed` + `IsReady`.
  Por cada unidad arma una fila: titulo (`VolumeLabel (Letra:)  -  total GB`), una barra unica
  dividida (parte usada en color + parte libre en gris `#2A2A2A`, recortada con `ClipToBounds`
  para extremos redondeados) y dos labels debajo (`X GB usados` izq / `Y GB libre` der). Varios
  discos van uno debajo del otro.
- Color de la parte usada por umbral de ocupacion (coherente con la app): >90% rojo, >75%
  amarillo, resto acento `#00C8FF`.
- Tamanos en GB redondeados a entero (consistente: titulo, usados y libre).
- Se filtran particiones < 1 GB ("Reservado para el sistema" / recuperacion con letra): Windows
  tampoco las muestra y como disco de "0 GB" se veian rotas.
- DriveInfo es instantaneo: se elimino toda la maquinaria async del scan de carpetas (job,
  timer, top-10, estado "escaneando", label "N carpetas | X GB"). El refresh se dispara al
  entrar a la tab Info. Titulo de la card sin cambios ("ESPACIO EN DISCO").

`dotnet build`: 0 errores, 0 advertencias. XAML validado con ElementTree.

---

## C# Fixes — Bloatware vacio, espacio en disco, limpieza profunda + benchmark descartado

Tres funciones migradas fallaban (la app ya corre elevada, asi que NO era permisos: eran
bugs de logica/portabilidad). Diagnostico real de cada una antes de tocar codigo.

**Archivos modificados**
- `src-csharp/WinBoost/Services/BloatwareService.cs`
- `src-csharp/WinBoost/Services/MaintenanceService.cs`
- `src-csharp/WinBoost/Services/SystemInfoService.cs`
- `src-csharp/WinBoost/MainWindow.xaml.cs`
- `src-csharp/WinBoost/MainWindow.xaml`

**Bloatware: lista siempre vacia ("sistema limpio")**
- *Causa raiz:* `GetInstalledAppxMap` enumeraba AppX con `(Get-AppxPackage; Get-AppxPackage -AllUsers)`.
  El operador de agrupacion `( )` de PowerShell acepta UNA sola expresion; el `;` interno
  lo convierte en error de sintaxis ("Falta el parentesis de cierre"). El cmdlet nunca
  devolvia nada, el mapa quedaba vacio y ninguna entrada de la DB matcheaba. (No era el TFM
  ni la WinRT PackageManager: el codigo ya shelleaba a PowerShell.)
- *Fix:* cambiar a `@( ... )` (operador de sub-expresion array, que si agrupa multiples
  statements). Verificado: la enumeracion pasa de 0 a 92 paquetes, incluidas las apps Xbox.
  La DB de 55 apps y el match por substring ya estaban bien.

**Espacio en disco: panel vacio (Info del sistema)**
- *Causa raiz:* el escaneo nunca se porto a C#. El `ItemsControl` `diskPanel` existia en el
  XAML pero no se referenciaba en el code-behind ni se disparaba ningun scan.
- *Fix:* `SystemInfoService.ScanTopFoldersAsync` (mirror del job del PS1): enumera carpetas
  top-level de SystemDrive excluyendo Windows/WinSxS/Installer/SVI/$Recycle.Bin, suma tamano
  recursivo (saltando lo inaccesible), ordena desc y toma top 10. Corre en `Task.Run`. Se
  puebla `diskPanel` (fila nombre + tamano + barra proporcional) con disparo lazy al entrar
  a la tab Info (flag `_diskScanned`).

**Limpieza profunda de cache: no funcionaba**
- *Causa raiz:* `btnDeepClean` no estaba cableado en el code-behind y la logica no se habia
  portado (boton muerto).
- *Fix:* `MaintenanceService.DeepCleanAsync` (mirror del btnDeepClean del PS1): detiene
  Explorer, limpia icon/thumbcache, reportes WER, logs CBS/DISM y shader cache D3D
  (NVIDIA/AMD), reinicia Explorer (en `finally`, garantizado). Error por paso = se loguea y
  SIGUE, nunca frena todo. Corre async con callback de progreso. Cableado del boton +
  confirmacion + reporte al log y label de estado.

**Benchmark de disco: descartado**
- CrystalDiskMark ya lo cubre. No se migro. Se oculto el cuadrante completo en la tab
  Herramientas (`Visibility="Collapsed"`) y Mantenimiento Automatico ahora ocupa toda la fila
  (`Grid.ColumnSpan="2"`) para no dejar hueco. No habia codigo C# del benchmark que eliminar.

XAML validado con ElementTree. `dotnet build`: 0 errores, 0 advertencias.

---

## C# Fase 0 — app.manifest elevado a requireAdministrator

**Archivos modificados**
- `src-csharp/WinBoost/app.manifest` — `requestedExecutionLevel` de `asInvoker` a `requireAdministrator`

C# Fase 0: app.manifest elevado a requireAdministrator (igual que el PS1); resuelve los
access-denied en HKLM, Prefetch y Standby List. El manifest habia quedado en `asInvoker`
desde el POC, por lo que la app C# corria sin privilegios y fallaban todas las operaciones
que tocan HKLM, carpetas protegidas (Prefetch) o la Standby List: optimizacion, Scheduler
de CPU, HAGS, purga de RAM y limpieza profunda. El `.csproj` ya referenciaba el manifest via
`<ApplicationManifest>app.manifest</ApplicationManifest>`, asi que no hubo que agregar esa
linea. `dotnet build`: 0 errores, 0 advertencias.

---

## C# 6.2 — Sistema de diseno: tokens + acento unico + estados + transiciones

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml` — nuevo diccionario de tokens de diseno (recursos de aplicacion)
- `src-csharp/WinBoost/MainWindow.xaml` — BtnMain/BtnSec con transiciones + acento via token en todos los estilos
- `src-csharp/WinBoost/ChangelogDialog.xaml`, `CompareDialog.xaml`, `ConfirmOptimizationDialog.xaml`,
  `FinishOptimizationDialog.xaml`, `OnboardingDialog.xaml` — acento unificado al token global

**Objetivo del item (6.2)**

Establecer un sistema de diseno compartido: tokens de espaciado/tipografia, un acento unico
como fuente de verdad, estados hover/pressed/disabled consistentes y transiciones suaves.

**Tokens centrales (`App.xaml` → `Application.Resources`)**

Antes el acento `#00C8FF` estaba hardcodeado en ~60 lugares de `MainWindow.xaml` y repetido en
cada dialogo; el espaciado y los tamanos de fuente eran numeros magicos. Ahora viven como recursos
de aplicacion, disponibles para la ventana principal **y todos los dialogos** (lookup `StaticResource`
sube hasta `Application.Resources`):
- **Acento unico**: `AccentColor` (#00C8FF) + variantes `AccentHoverColor` (#33D6FF),
  `AccentPressedColor` (#0088BB), `AccentSubtleColor` (#08141A) y sus pinceles `BrushAccent`,
  `BrushAccentHover`, `BrushAccentPressed`, `BrushAccentSubtle`. Cambiar el acento de marca ahora
  es editar un solo token.
- **Estados**: `OkColor`/`WarnColor`/`ErrColor` + `BrushOk`/`BrushWarn`/`BrushErr`/`BrushInfo`.
- **Tipografia**: `FontFamilyBase` + escala `FontCaption`(10)…`FontDisplay`(24).
- **Espaciado** (escala 4px): `SpaceXs`(4)…`SpaceXl`(24) + `PadButton`/`PadCard` (Thickness).
- **Radios**: `RadiusSm`(4)/`RadiusMd`(6)/`RadiusLg`(8) (CornerRadius).
- **Transiciones**: `DurFast` (0.13s), duracion estandar de los cambios de estado.

**Acento unico aplicado**

Todas las referencias solidas (opacidad completa) a `#00C8FF` en `MainWindow.xaml` y en los 5
dialogos se reemplazaron por `{StaticResource BrushAccent}` (o `AccentColor` para `GradientStop`).
Las variantes translucidas (`#00C8FF18`, `#00C8FF40`, etc.) se dejaron intactas para no alterar el
render — su tokenizacion queda para un pase futuro.

**Estados + transiciones en los botones principales**

`BtnMain` y `BtnSec` se reconstruyeron con pinceles inline **no congelados** (animables) y
transiciones de color en hover via `ColorAnimation` en `Trigger.EnterActions`/`ExitActions`
(duracion `DurFast`):
- `BtnMain`: el fondo funde acento → acento-hover y vuelve al salir; `pressed` mantiene el
  `ScaleTransform` (0.97); `disabled` reemplaza el fondo por gris.
- `BtnSec`: el fondo y el borde funden hacia el acento en hover; mismo `pressed`/`disabled`.
- Se evito tocar `BtnNav` con transiciones porque `BtnNavActive` (BasedOn) sobreescribe `Background`
  via `TemplateBinding`; reemplazarlo por un pincel inline habria roto el realce de nav activo.

`dotnet build`: 0 errores, 0 advertencias. Los 7 XAML validados con ElementTree. App arranca y
renderiza con los tokens (smoke test).

---

## C# 6.1 — Tuning Avanzado: tab declarativo en XAML + motor en servicio

**Archivos creados**
- `src-csharp/WinBoost/Services/TuningService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Tuning` singleton
- `src-csharp/WinBoost/MainWindow.xaml` — nav button `navTuning` + TabItem "Tuning Avanzado" declarativo (5 cards)
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring del tab + carga lazy + render de info/drivers

**Objetivo del item**

El PS1 construye el tab Tuning con `Build-TuningTab` (~600 lineas de creacion programatica de controles + helpers). En C# el tab pasa a ser **XAML declarativo** (una TabItem con 5 cards), y la logica vive en `TuningService`. Esto cumple el objetivo de "achicar el Build-TuningTab".

**`TuningService` (mirror de los helpers F2.18/F2.19)**

Modelos: `ExtendedSystemInfo`, `DriverPackage`.
- `GetWin32PrioritySep` / `SetWin32PrioritySep` — Scheduler de CPU (registro `PriorityControl`). El Set hace backup (`SaveRegBackup`, creando sesion si no hay) antes de escribir.
- `GetHagsState` / `SetHagsState` — HAGS (`GraphicsDrivers\HwSchMode`, 2=on/1=off), con backup.
- `GetCoolingPolicyState` / `SetCoolingPolicy` — politica termica via `powercfg` (query/setac/setdc/setactive sobre los GUID de subgrupo/ajuste).
- `GetExtendedInfoAsync` — WMI en `Task.Run`: cores/hilos/L3, velocidad/slots de RAM, VRAM/driver de GPU.
- Driver Store: `ScanObsoleteDriversAsync` (`pnputil /enum-drivers` + `ParsePnpUtil` + `GetObsolete`: agrupa por Original Name, marca obsoleto todo lo que no sea la version mas nueva), `ExportDriverBackupAsync` (`Export-WindowsDriver -Online`), `DeleteDriverAsync` (`pnputil /delete-driver /uninstall`).

**UI declarativa (MainWindow.xaml)**

- Nuevo `navTuning` en el sidebar (icono rayo) → `SetActiveNav(9)`. `navTuning` se suma a `_navButtons` como indice 9 (el `SetActiveNav` ya lo resalta sin el caso especial que necesitaba el PS1).
- Nueva `TabItem "Tuning Avanzado"` (Visibility Collapsed en la tab-bar, se navega por sidebar) con 5 cards: Scheduler de CPU (combo + Aplicar), HAGS (estado + Activar/Desactivar), Politica termica (Activa/Pasiva), Informacion de componentes (`ItemsControl`), Limpieza del Driver Store (escanear/backup/eliminar + lista).

**Wiring (MainWindow.xaml.cs)**

- Carga lazy al entrar al tab 9 (`_tuningLoaded`): puebla el combo de prioridad (selecciona el valor actual del registro), lee HAGS, y resuelve politica termica (powercfg) + info extendida (WMI) fuera del hilo UI.
- Handlers: `ApplyPrioritySeparation`, `SetHags`, `SetCoolingPolicyAsync`, `ScanObsoleteDriversAsync`, `ExportDriverBackupAsync`, `DeleteSelectedDriversAsync` (gate: requiere backup previo). Logs y mensajes/colores identicos al PS1.
- `RenderTuningInfo` / `AddInfoRow` — mirror de `New-InfoRow`. `BuildDriverRow` — fila con checkbox + nombre + version + fecha; los checkboxes se trackean en `_driverChecks` paralelo a `_driverPackages`.
- Controles `btnScanDrvStore` / `icDrvStore` renombrados para no colisionar con el `btnScanDrivers`/inventario de drivers del tab Info.

**Nota de paridad**: el scan del Driver Store usa `Task.Run` async (reemplaza el `Start-Job` + `DispatcherTimer` del PS1) sin congelar la UI. El parseo de `pnputil` matchea los rotulos en ingles, igual que el PS1.

`dotnet build`: 0 errores, 0 advertencias. XAML validado con ElementTree.

---

## C# 5.3 — Auto-updater: Check / Download / Apply (FASE 5 completa)

**Archivos creados**
- `src-csharp/WinBoost/Services/UpdateService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Updater` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — labels de version + wiring del badge/check + flujo descarga/verificacion/apply

**`UpdateService`**

Equivalente al modulo 14 del PS1 (`Check-ForUpdates` / `Start-UpdateDownload` / `Apply-Update`). La UI del changelog la aporta `ChangelogDialog` (5.2).

**Modelo nuevo**
- `UpdateMeta(Version, Changelog, ReleaseUrl, DownloadUrl, Sha256)` — mirror de `$script:updateMeta`.

**`CheckAsync()`** — mirror de `Check-ForUpdates`: `HttpClient.GetStringAsync` del `version.json` (timeout 5s), deserializa con `System.Text.Json` (case-insensitive), compara versiones via `TryParseVersion` (limpia `[^0-9.]` y castea a `Version`, igual que `[version]` del PS1). Devuelve la meta si la remota es mayor, o null (sin conexion incluido, silencioso). Cachea en `Latest`.

**`DownloadAsync(meta, progress, ct)`** — mirror de `Start-UpdateDownload`: descarga el instalador a `%TEMP%\OptimizarPC_update` con `HttpCompletionOption.ResponseHeadersRead` + streaming por buffer de 80 KB, reportando progreso 0–100 via `IProgress<int>` (reemplaza el `WebClient.DownloadProgressChanged` + `DispatcherTimer` del PS1 por async nativo, sin bloquear el hilo UI). Devuelve la ruta o null.

**`VerifySha256(file, expected)`** — mirror de la comprobacion `Get-FileHash SHA256`: `Convert.ToHexString` del hash, comparacion case-insensitive.

**`ApplyUpdate(installerFile)`** — mirror de `Apply-Update`: escribe el helper `do_update.ps1` (identico al PS1: espera hasta 30s el cierre del proceso, corre el instalador con `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL`, relanza la app) y lo lanza con `powershell -WindowStyle Hidden`. El instalador hereda la elevacion del proceso. Devuelve false en modo desarrollo (`IsRunningAsExe`: la ruta no termina en `.exe` o corre bajo el host `dotnet`), igual que el chequeo `$isExe` del PS1.

**Wiring en MainWindow**

- Setea `Title`, `lblVersion` y `lblVersionAbout` con `v{App.Version}` (cierra el `$lblVersion.Text` del `Add_ContentRendered` del PS1).
- `CheckForUpdatesAsync(manual)` — chequeo en background al arrancar + manual desde `btnCheckUpdatesSettings`. Muestra `badgeUpdate` con `"v{n} disponible"` si hay update; en chequeo manual avisa por MessageBox cuando ya esta actualizado (o abre el changelog si hay update).
- `OnUpdateBadgeClick()` — mirror del `badgeUpdate` click: abre `ChangelogDialog` y procesa el `Result` (GitHub → abre el release; Download → descarga).
- `DownloadAndApplyAsync(meta)` — navega a Optimizar para mostrar la progressBar, descarga con progreso, y replica la cascada de verificacion del PS1: archivo ausente (posible cuarentena) → aviso + release; hash faltante → aviso + release; hash no coincide → error y aborta; OK → `ApplyUpdate`. En modo desarrollo abre el release; al aplicar, cierra la ventana tras 1s via `DispatcherTimer` (mirror del `applyTimer`). Guard `_updating` para no relanzar.
- `OpenUrl` — `Process.Start(UseShellExecute=true)` para los release URLs.

**Nota de paridad**: el PS1 distingue el error de lectura del archivo (antivirus) del mismatch de hash con mensajes separados; en C# `VerifySha256` captura el error de lectura y lo trata como verificacion fallida (un solo mensaje). El resto de la cascada es identica.

`dotnet build`: 0 errores, 0 advertencias.

**FASE 5 COMPLETA** (5.1–5.3): licencias + trial + gate Pro, first-run + onboarding + changelog, auto-updater.

---

## C# 5.2 — Primer uso + onboarding wizard + dialogo de changelog

**Archivos creados**
- `src-csharp/WinBoost/OnboardingDialog.xaml` + `.xaml.cs`
- `src-csharp/WinBoost/ChangelogDialog.xaml` + `.xaml.cs`

**Archivos modificados**
- `src-csharp/WinBoost/Services/AppSettings.cs` — agrega `FirstRunCompleted`
- `src-csharp/WinBoost/Services/SettingsService.cs` — `Load` copia `FirstRunCompleted`
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `MaybeShowOnboarding` + disparo tras el primer score

**Primer uso (modulo 15A)**

Reemplaza `Test-FirstRun` / `Set-FirstRunComplete`. En vez de un campo `firstRun` en `profile.json` (que en C# esta separado en `opt_profile.json` solo para checkboxes), el estado vive en `settings.json` como `FirstRunCompleted` (default `false` = primer uso). Se marca `true` solo al completar el wizard, de modo que un cierre antes de terminar lo vuelve a mostrar.

**`OnboardingDialog` (modulo 15B)**

Mirror de `Show-OnboardingDialog`. Wizard modal de 4 pasos (mismo XAML/colores que el PS1): hardware detectado, score de salud, seleccion de perfil, listo.
- Constructor recibe `cpuName, gpuName, ramGb, diskType, isLaptop, score, recommendedPreset`.
- `UpdateStep` (mirror de `obdUpdateStep`): visibilidad de paneles, dots progresivos, titulos/subtitulos por paso, "Anterior" deshabilitado en paso 0, boton "Siguiente"/"Empezar".
- `UpdateCards` (mirror de `obdUpdateCards`): highlight del borde de la tarjeta elegida + resumen en el paso 3.
- Paso 1: color/label del score por umbral (>=80 verde / >=60 amarillo / resto rojo), identico al PS1.
- Paso 2: badge "Recomendado" sobre el preset sugerido; tarjetas clickeables (Gaming/Productividad/Conservador).
- Bloquea el cierre con X hasta completar (override `OnClosing` con `e.Cancel`), igual que el `Add_Closing` del PS1.
- Expone `ChosenPreset` ("Gaming"/"Prod"/"Safe"); el caller aplica el preset y marca el primer uso.

**Disparo en MainWindow**
- `MaybeShowOnboarding()` se llama al final de `RunAndDisplayScoreAsync` (primer score listo → hardware + score ya poblados, mismo timing que el `Add_ContentRendered` del PS1). Guard `_onboardingChecked` para una sola vez por sesion.
- Preset recomendado con el mismo criterio del PS1: laptop → Prod, RAM >= 8 GB → Gaming, resto → Safe.
- Al completar: `ApplyPreset(preset)` + `FirstRunCompleted = true` + `Settings.Save()`.

**`ChangelogDialog` (dialogo de actualizacion, modulo 14)**

Mirror de `Show-ChangelogDialog`: ventana con el changelog de la version disponible (version nueva, version actual, texto de cambios scrolleable) y 3 acciones. Constructor `(newVersion, currentVersion, changelog, downloadAvailable)`; si no hay descarga, deshabilita el boton y muestra "Descarga no disponible". Expone `Result` (`ChangelogResult.Later/GitHub/Download`). UI desacoplada del motor de updater — la FASE 5.3 la cableara al `Check/Download/Apply` real.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 5.1 — Licencias: RSA-2048 + trial de 14 dias + gate Pro + badge

**Archivos creados**
- `src-csharp/WinBoost/Services/LicenseService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.License` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring del tab Licencia + banner trial + aplica los 5 gates Pro

**`LicenseService`**

Equivalente a los modulos 12A/12B del PS1 (motor de hardware ID, licencia y trial). Reusa el XAML del tab Licencia (badges, HWID, activacion) y el banner trial del footer.

**Modelos nuevos**
- `LicenseTier` (enum: Free/Pro/Tech)
- `LicenseStatus(IsActivated, HardwareId, Tier)` — record de estado

**Estado en memoria** (reemplaza `$script:IS_PRO` / `IS_TECH` / `IS_TRIAL` / `TRIAL_DAYS_LEFT`): props `IsPro`, `IsTech`, `IsTrial`, `TrialDaysLeft`.

**`GetHardwareId()`** — mirror de `Get-HardwareID`: `Win32_Processor.ProcessorId` + `Win32_BIOS.SerialNumber` via WMI, SHA256, primeros 16 hex en mayusculas. Fallback `MachineName + OS SerialNumber` si los seriales estan vacios (VMs). Cacheado.

**Verificacion de firma** — clave publica RSA-2048 embebida (identica al PS1; la privada la tiene solo `Gen-License.ps1`). `TestSignature` usa `RSACryptoServiceProvider.FromXmlString` + `VerifyHash(hash, "SHA256", sig)`.
- `TestLicenseKey` — mirror de `Test-LicenseKey`: firma Base64 sobre `WINBOOST-PRO-<HWID>` (hardware-bound).
- `TestTechLicenseKey` — mirror de `Test-TechLicenseKey`: `TECH-<Base64>`, firma sobre `WINBOOST-TECH` (multi-PC, sin HWID).

**`GetStatus()`** — mirror de `Get-LicenseStatus`: comprueba `tech_license.key` (mas permisivo) y luego `license.key` (hardware-bound). Paths en `~/.OptimizarPC/`.

**`EvaluateTrial()`** — mirror de `Test-TrialStatus`: trial de 14 dias. Si hay licencia activa -> Pro. Si no hay `TrialStartDate` -> la setea (primer uso, 14 dias). Si vencio (`elapsed > 14`) -> marca `TrialExpired` y bloquea. Persiste via `App.Settings.Save()` cuando cambia.

**`ActivatePro` / `ActivateTech`** — validan, persisten la clave (`license.key` / `tech_license.key`, UTF-8 sin BOM) y actualizan el estado en memoria.

**Wiring en MainWindow (modulo 12C)**

- `InitLicenseAsync()` — corre `RefreshFromStored` + `EvaluateTrial` en `Task.Run` (HWID via WMI fuera del hilo UI), luego setea `lblHardwareID`, badge y banner. Llamado en OnLoaded.
- `LockProFeature(name)` — mirror de `Lock-ProFeature`: `MessageBox` y retorna `true` (bloquea) si no hay Pro ni trial; mensaje distinto si el trial vencio.
- `UpdateLicenseBadge()` — mirror de `Update-LicenseBadge`: badge Free/Pro + texto de estado (Tecnico / Pro / trial con dias / gratuita / vencido), colores por estado.
- `UpdateTrialBanner()` — mirror de `Update-TrialBanner`: banner amarillo (trial activo, texto especial para 1 dia) / rojo (vencido) / oculto.
- `CopyHardwareId()` — copia el HWID, "Copiado" por 1.5s via `DispatcherTimer`.
- `ActivateLicense()` — mirror del `btnActivateLicense`: detecta `TECH-` -> `ActivateTech`, si no -> `ActivatePro`. Refresca badge + banner. Mensajes de resultado identicos al PS1.
- `GetLicense()` — `LICENSE_BUY_URL` vacio -> aviso de contacto a soporte.
- Brushes congelados nuevos: `BrushLicFree` (#888888) + fondos del banner (`BrushTrialBg/Bd`, `BrushExpBg/Bd`).

**Gates Pro aplicados** (cierran las "Notas de paridad" de C# 3.1/4.1/4.3/4.6/4.7):
- `OnRunOptimizationAsync` — "Tweaks de registro y servicios"
- `InvokeRemoveBloatAsync` — "Desinstalar bloatware"
- `InvokeRevertSessionAsync` — "Revertir sesion"
- `ToggleMaintenanceAsync` + `RunMaintenanceNowAsync` — "Mantenimiento automatico"
- `ExportHtmlReportAsync` — "Exportar reporte HTML"

El modo silencioso CLI (`-Silent`) no se gatea, igual que el PS1 (bypassa el handler de `btnRun`).

**Nota**: el XAML reusado no tiene fila de nombre de tecnico (`techNameRow`); el PS1 ya la referenciaba defensivamente con try/catch, por lo que se omite sin perdida de paridad.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.8 — Dialogo de comparacion: snapshots antes/despues + reiniciar

**Archivos creados**
- `src-csharp/WinBoost/CompareDialog.xaml`
- `src-csharp/WinBoost/CompareDialog.xaml.cs`

**Archivos modificados**
- `src-csharp/WinBoost/FinishOptimizationDialog.xaml` — agrega boton "Ver comparativa" (Collapsed por defecto)
- `src-csharp/WinBoost/FinishOptimizationDialog.xaml.cs` — flag `ShowCompare` + parametro `canCompare`
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `ShowCompareDialog` + integracion en `FinishOptimizationAsync`

**`CompareDialog`**

Equivalente al modulo 11B del PS1 (`Show-CompareDialog`). Ventana modal con la comparativa del sistema antes/despues.

- Constructor recibe `IReadOnlyList<CompareRow>` (de `SnapshotService.CompareSnapshots`) + `freedMb`.
- `BuildRows` — mirror del scriptblock `$mkRow` del PS1: header de columnas (Metrica/Antes/Despues/Delta) + una fila por metrica (dot de estado, label, antes, despues, delta con signo). Formatea valores con sufijo "MB" o "%" segun el label. Filas alternadas (zebra). Agrega fila extra "MB liberados".
- Colores por estado: better verde / worse rojo / neutral gris. Mismas columnas que el PS1 (16 | * | 90 | 90 | 80).
- 3 botones: "Ver log" → `Result="log"`, "Reiniciar despues" → `Result="later"`, "Reiniciar ahora" → `Result="restart"`.

**Integracion (sin cascada de modales)**

En vez de mostrar dos modales seguidos, el `CompareDialog` se abre desde el `FinishOptimizationDialog` (3.4) via un boton "Ver comparativa", visible solo si hay ambos snapshots (`canCompare`). Patron identico al `GoToHistory` existente:
- `FinishOptimizationDialog` expone `ShowCompare` y recibe `canCompare`.
- `FinishOptimizationAsync` pasa `canCompare = SnapshotBefore != null && _snapshotAfter != null`. Si el usuario pulsa "Ver comparativa", llama `ShowCompareDialog(res.FreedMb)`.
- `ShowCompareDialog` calcula `CompareSnapshots(before, after)`, muestra el dialogo y procesa el resultado: `restart` → `shutdown /r /t 0`, `log` → navega a la consola, `later` → no hace nada.

`dotnet build`: 0 errores, 0 advertencias.

**FASE 4 COMPLETA** (4.1–4.8): bloatware, startup, mantenimiento, game focus, purga RAM, historial, reporte HTML, comparativa.

---

## C# 4.7 — Reporte HTML: exportar reporte standalone

**Archivos creados**
- `src-csharp/WinBoost/Services/ReportService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Report` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — captura de estado post-optimizacion + wiring de `btnExportHTML`

**`ReportService`**

Equivalente al modulo 10 del PS1 (exportar reporte HTML).

**Modelo nuevo**
- `ReportData(Sys, SysDrive, ScoreBefore, ScoreAfter, Before, After, FreedMb, Actions, TechnicianName)` — reune el estado en memoria necesario para el reporte (equivalente a las variables `$script:*` del PS1).

**`BuildHtml(ReportData)`** — mirror de `Build-HTMLReport`: genera el HTML standalone con CSS inline usando un raw string interpolado de C# (`$$"""..."""`, donde `{` del CSS son literales y `{{...}}` son interpolacion). Secciones:
- Header con version + timestamp + tipo de equipo + drive.
- **Resultados medibles** (4 cards): Score antes→ahora + delta, RAM disponible antes→ahora + delta, Procesos activos antes→ahora + delta, Tiempo de arranque. Colores por umbral/signo identicos al PS1.
- Informacion del sistema (CPU/GPU/RAM/almacenamiento + fila de tecnico opcional).
- Resumen de sesion (MB liberados / acciones / pts de mejora).
- Lista de acciones aplicadas.
- Todos los strings de usuario pasan por `WebUtility.HtmlEncode`.

**`ExportAsync(ReportData)`** — mirror de `Export-HTMLReport`: construye el HTML en `Task.Run`, lo guarda en `Documentos\OptimizarPC_Reporte_<fecha>.html` (UTF-8 sin BOM), lo abre en el navegador. Devuelve la ruta o null.

**Wiring en MainWindow**
- Campos nuevos `_lastFreedMb`, `_snapshotAfter`, `_lastReportActions` capturan el estado de la ultima optimizacion:
  - `OnRunOptimizationAsync` guarda las acciones del plan confirmado (`{Category}: {Label}`).
  - `FinishOptimizationAsync` guarda `FreedMb` y toma el snapshot posterior (`TakeSnapshotAsync(scoreAfter)`) — esto tambien cierra el hueco de `snapshotAfter` que faltaba en la migracion.
- `ExportHtmlReportAsync()` — arma `ReportData` desde el estado actual (system info, scores, snapshots before/after, freed, acciones, nombre de tecnico) y llama `ExportAsync`. Si no hubo optimizacion aun, los campos van en N/D / 0 (igual que el PS1).

**Nota de paridad**: el gate Pro (`Lock-ProFeature "Exportar reporte HTML"`) del PS1 aun no se aplica — el sistema de licencias se migra en fase 5.1.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.6 — Historial enriquecido: sesiones, stats, score chart + revert

**Archivos creados**
- `src-csharp/WinBoost/Services/HistoryService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.History` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring completo del tab Historial + reset de carga lazy en FinishOptimization

**`HistoryService`**

Equivalente al modulo 8A del PS1 (motor de historial enriquecido). Construye sobre `BackupService.GetBackupSessions`.

**Modelos nuevos**
- `SessionHistoryEntry(Timestamp, Date?, Preset, FreedMb, ActionCount, ScoreBefore, ScoreAfter, ScoreImprovement, SessionPath)`
- `HistoryStats(TotalSessions, TotalFreedMb, AvgImprovement, TotalImprovement, FirstSession?, DaysSince)`

**`GetSessionHistoryAsync()`** — mirror de `Get-SessionHistory`: corre en `Task.Run`, filtra sesiones con metadata, parsea `Timestamp` (formato `yyyy-MM-dd HH:mm:ss`, fallback parse general), calcula `ScoreImprovement`. Orden descendente (igual que GetBackupSessions).

**`GetHistoryStatsAsync()`** — mirror de `Get-HistoryStats`: agrega TotalFreedMb, TotalImprovement, AvgImprovement, y `DaysSince` (desde la sesion mas antigua = ultimo elemento). null si no hay sesiones.

**Wiring en MainWindow (modulos 1C + 8B)**

- `RefreshHistoryAsync()` — refresca lista de sesiones + 4 cards de stats + mini grafico, en off-UI-thread.
- `RenderHistoryItems(sessions)` — mirror de `Render-HistoryItems`: grid 6 cols (Fecha/150 | Preset-badge/90 | Acciones/70 | MB/75 | Estado/Star | Revertir/110). Resalta la sesion mas reciente, badge "Completo"/"Sin metadata", boton Revertir por fila. Colores de preset identicos al PS1.
- `UpdateHistoryStats(stats)` — mirror de `Update-HistoryStats`: rellena los 4 cards (sesiones, MB total, mejora promedio con signo, dias activo).
- `RenderScoreHistory(history)` — mirror de `Render-ScoreHistory`: mini grafico de barras en el `Canvas icScoreHistory` (8 ultimas, de mas antigua a reciente), altura proporcional al `ScoreAfter`, color por umbral (verde/amarillo/rojo), centrado segun ancho real del canvas.
- `OpenBackupFolder()` — abre `BackupRoot` en el explorador.
- `RevertLastSessionAsync()` — revierte la sesion mas reciente (mirror de `btnRevertLast`).
- `InvokeRevertSessionAsync(path)` — mirror de `Invoke-RevertSession`: confirmacion → `RestoreSession` en `Task.Run` con callback de log marshalado al hilo UI via `Dispatcher.Invoke` → MessageBox de resultado. Deshabilita botones durante la restauracion.
- `WriteRestoreLog(msg, type)` — mirror de `Write-RestoreLog`: escribe al `RichTextBox rtbRestoreLog` con color por tipo (ok/err/skip/head/info), actualiza `lblRestoreLog` y el fondo de `badgeRestoreStatus`.
- **Carga lazy**: `OnMainTabsSelectionChanged` dispara `RefreshHistoryAsync` la primera vez que se entra al tab Historial (index 5), via flag `_historyLoaded`. `FinishOptimizationAsync` resetea el flag tras `SaveSessionMetadata` para que la nueva sesion aparezca al volver al tab (cierra el TODO "SaveSessionMetadata no llama Render-HistoryItems" de C# 1.3).

**Nota de paridad**: el gate Pro (`Lock-ProFeature "Revertir sesion"`) del PS1 aun no se aplica — el sistema de licencias se migra en fase 5.1.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.5 — Liberador de RAM: Working Set + purga de Standby List

**Archivos creados**
- `src-csharp/WinBoost/Services/RamService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Ram` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring de `btnFreeRAM` + refresh post-purga

**`RamService`**

Equivalente al modulo "LIBERADOR DE RAM" del PS1. Reusa el P/Invoke ya consolidado en `NativeMethods` (`EmptyWorkingSet`, `EnablePrivilege`, `PurgeStandbyList`).

**Modelos nuevos**
- `RamInfo(TotalGb, UsedGb, FreeGb)` — snapshot de memoria
- `FreeRamResult(WorkingSetFreedMb, StandbyFreedMb, StandbyPurged, ProcessCount)` — resultado de la purga

**`GetRamInfoAsync()`** — mirror de `Update-RAMDisplay`: WMI `Win32_OperatingSystem` (TotalVisibleMemorySize / FreePhysicalMemory) → total/usado/libre en GB.

**`FreeRamAsync()`** — mirror del `Add_Click` de `btnFreeRAM`:
1. Mide RAM libre (WMI) antes.
2. `EmptyWorkingSet` en todos los procesos accesibles (cuenta los exitosos; cada `Process` se dispone).
3. Mide Working Set liberado (delta de FreePhysicalMemory / 1024 = MB).
4. Purga de Standby List: mide `PerformanceCounter("Memory", "Free & Zero Page List Bytes")` antes (espera 150ms), `EnablePrivilege("SeProfileSingleProcessPrivilege")` + `PurgeStandbyList`, mide despues (espera 1s). Delta clampeado a >= 0.
- Trabajo pesado en `Task.Run`; las esperas son `Task.Delay` no bloqueantes (el hilo UI no se congela — reemplaza el `Start-Sleep` del PS1).
- `StandbyPurged` distingue "purga omitida (requiere admin)" de "0 MB liberados".

**Wiring en MainWindow**
- `btnFreeRAM.Click` → `FreeRamAsync`: deshabilita el boton, ejecuta la purga, loguea Working Set + Standby (o "omitida (requiere admin)"), actualiza `lblRAMFreeStatus` con el desglose, refresca los labels de RAM.
- **Nota**: los labels `lblRAMTotal/Used/Free` ya los mantiene el monitor en tiempo real (1s); `UpdateRamDisplayAsync` solo se invoca tras la purga para feedback inmediato sin esperar al proximo tick.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.4 — Game Focus Mode: deteccion fullscreen + prioridad + afinidad CPU

**Archivos creados**
- `src-csharp/WinBoost/Services/GameFocusService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.GameFocus` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — timer de deteccion + handler + cleanup en OnClosed

**`GameFocusService`**

Equivalente a los modulos 9A/9B/9C del PS1. Reusa el P/Invoke de user32 ya consolidado en `NativeMethods` (no se agrego ningun DllImport nuevo).

**Deteccion (modulo 9A)**
- `KnownGames` — lista estatica de ~38 procesos de juegos (mirror exacto de `$script:knownGames`).
- `GetFullscreenProcess()` — mirror de `Test-FullscreenProcess`: `GetForegroundWindow` → excluye desktop/shell → `GetWindowRect` vs `GetMonitorInfo(MonitorFromWindow)`. Fullscreen = rect de ventana identico al rect del monitor fisico. Devuelve el `Process` o null.
- `IsKnownGame(proc)` — mirror de `Test-KnownGame`: el nombre del proceso contiene un juego conocido.

**Afinidad (modulo 9B, F2.20)**
- `GetPhysicalCoreMask()` — WMI `Win32_Processor`: si `logical > physical`, mascara = `(1 << physical) - 1`; si no hay SMT/HT util, -1.

**Apply / Restore (modulo 9B)**
- `Apply(proc)` — mirror de `Apply-GameFocusMode`: guarda estado previo (prioridad, ToastEnabled, afinidad), eleva `PriorityClass` a High, escribe `ToastEnabled=0` en `HKCU\...\PushNotifications`, y aplica afinidad a nucleos fisicos si `Settings.GameAffinityEnabled`. Logs identicos al PS1 (incluye mascara en hex).
- `Restore()` — mirror de `Restore-GameFocusMode`: restaura prioridad, ToastEnabled y afinidad al valor guardado (si el proceso sigue corriendo).
- `ActiveProcessExited()` / `MarkInactive()` — soporte para el chequeo `HasExited` del timer.

**Wiring en MainWindow (modulo 9C)**
- `_gamingTimer` — DispatcherTimer de 5s, arrancado en OnLoaded.
- `OnGamingTick` — mirror del `Add_Tick`: detecta juego fullscreen, activa/desactiva focus mode y muestra/oculta `badgeGamingMode`. Si el proceso activo termino, limpia el badge sin restaurar.
- `OnClosed` — detiene `_gamingTimer` y restaura focus mode si la app se cierra con un juego activo.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.3 — Mantenimiento automatico: tarea programada + ciclo de limpieza

**Archivos creados**
- `src-csharp/WinBoost/Services/MaintenanceService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Maintenance` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring de la seccion de mantenimiento (tab Herramientas)

**`MaintenanceService`**

Equivalente al modulo 7A del PS1. Nombre de tarea `OptimizarPC_Maintenance` (mismo que el PS1, para compatibilidad de migracion). Paths en `~/.OptimizarPC/`: `maintenance_log.json`, `maintenance.ps1`.

**Modelos nuevos**
- `MaintenanceResult(Timestamp, Actions, FreedMb, Errors)` — resultado de un ciclo
- `MaintenanceTaskInfo(Exists, Enabled, State, LastRun?, NextRun?)` — estado de la tarea

**`RunCycleAsync(temp, recycle, dns, trim, hasSsd)`** — corre en `Task.Run`. Mirror de `Invoke-MaintenanceCycle`:
- Temp usuario: suma tamano + borra `%TEMP%` (nativo C#)
- Papelera: `NativeMethods.EmptyRecycleBin()`
- DNS flush: `ipconfig /flushdns`
- TRIM (solo si `hasSsd`): `Optimize-Volume -DriveLetter X -ReTrim -NormalPriority` via PowerShell
- Persiste el resultado en `maintenance_log.json` (max 30 entradas, FIFO)
- **Mejora vs PS1**: respeta los 4 checkboxes de la UI en "Ejecutar ahora" (el PS1 siempre limpiaba todo). El script standalone de la tarea programada sigue limpiando todo.

**`GetTaskAsync()`** — mirror de `Get-MaintenanceTask`. Ejecuta PowerShell (`Get-ScheduledTask` + `Get-ScheduledTaskInfo`) con salida delimitada `EXISTS|enabled|state|lastRun|nextRun` (fechas en formato round-trip `o`), parseo robusto independiente de localizacion.

**`CreateTaskAsync(frequency, hour)`** — mirror de `New-MaintenanceTask`:
1. Escribe el script standalone `maintenance.ps1` (here-string identico al PS1, sin WPF, limpia todo headless).
2. Registra la tarea escribiendo un `_register_task.ps1` temporal y ejecutandolo con `-File` (evita el infierno de escaping de comillas en `-Command`). Triggers: Daily / Weekly (domingo) / AtLogOn. Principal `RunLevel Highest`, settings `ExecutionTimeLimit 1h` + `StartWhenAvailable` + `MultipleInstances IgnoreNew`. Borra el script de registro al terminar.

**`RemoveTaskAsync()`** — mirror de `Remove-MaintenanceTask`. `Unregister-ScheduledTask` via PowerShell + borra `maintenance.ps1`.

**Wiring en MainWindow**

- Pobla `cboMaintHour` (00:00–23:00, default 10) en OnLoaded.
- `cboMaintFreq.SelectionChanged` deshabilita la hora si la frecuencia es "Al iniciar Windows" (index 2).
- `UpdateMaintUIAsync()` — mirror de `Update-MaintUI`: lee el estado, sincroniza el toggle (Activar/Desactivar + colores), `lblMaintStatus`, `lblLastMaint`, `lblNextMaint`. Deshabilita `chkMaintTRIM` si no hay SSD.
- `ToggleMaintenanceAsync()` — crea o elimina la tarea segun estado; avisa por MessageBox si el registro falla (requiere admin).
- `RunMaintenanceNowAsync()` — ejecuta el ciclo respetando los checkboxes, actualiza status y dispara toast.
- Brushes de toggle congelados (`BrushMaintOnBg`, `BrushMaintOffBg`, `BrushMaintFg`).

**Nota de paridad**: el registro/consulta/borrado de la tarea usa PowerShell (cmdlets `*-ScheduledTask`) en vez de la API COM, para maxima paridad con el PS1 y robustez frente a localizacion. El ciclo de limpieza "Ejecutar ahora" es nativo C#.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.2 — Startup manager: gestor de programas de arranque

**Archivos creados**
- `src-csharp/WinBoost/Services/StartupService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.StartupMgr` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring de la tab Arranque (carga lazy + render + toggle)

**`StartupService`**

Equivalente al modulo "GESTOR DE ARRANQUE" del PS1.

**Modelo nuevo**
- `StartupItem { Name, Path, Source, Enabled, ApprPath, FileName }` — item de arranque (clase mutable: `Enabled` se actualiza al togglear).

**`GetStartupItemsAsync()`** — corre en `Task.Run`. Mirror de `Load-StartupItems`. Recolecta de 4 fuentes:
- `HKCU\...\Run` (Source "HKCU")
- `HKLM\...\Run` (Source "HKLM")
- Carpeta `Startup` del usuario (`SpecialFolder.Startup`, Source "Startup", excluye `.ini`)
- Carpeta `CommonStartup` (Source "Startup All", siempre Enabled)

Cada item lee su estado via `GetApprState` (mirror de `Get-ApprState`): primer byte del valor binario en `StartupApproved\Run` / `StartupApproved\StartupFolder` — `0x03`/`0x08` = deshabilitado, resto/ausente = habilitado.

**`ToggleAsync(item)`** — corre en `Task.Run`. Mirror de `Toggle-StartupItem`. Escribe el valor binario de 12 bytes en la clave `StartupApproved` bajo HKCU: habilitado `0x02...`, deshabilitado `0x03...`. Devuelve el nuevo estado y actualiza `item.Enabled`.

**Wiring en MainWindow**

- `RefreshStartupAsync()` — deshabilita boton, llama `GetStartupItemsAsync`, cachea en `_startupItems`, renderiza.
- `RenderStartupItems(items)` — construye filas en codigo: grid 5 cols (Estado-badge/80 | Nombre/180 | Origen-badge/75 | Ruta/Star | Toggle/95). Colores y estilos `BtnToggleOn`/`BtnToggleOff` identicos al PS1. Footer: "N total | M activos | K deshabilitados".
- `ToggleStartupItemAsync(item)` — llama `ToggleAsync`, actualiza status, re-renderiza desde cache.
- **Carga lazy**: `OnMainTabsSelectionChanged` reestructurado para disparar `RefreshStartupAsync` la primera vez que se entra al tab Arranque (index 2), via flag `_startupLoaded`. El handler ahora cubre tab 2 (Arranque) y tab 4 (Info/score) con un solo metodo.
- Evento `btnRefreshStartup.Click` wired en OnLoaded.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 4.1 — Bloatware: deteccion AppX + winget + desinstalacion

**Archivos creados**
- `src-csharp/WinBoost/Services/BloatwareService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Bloatware` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring completo de la tab Bloatware

**`BloatwareService`**

Equivalente a los modulos 4A/4B/4C del PS1.

**Modelos nuevos**
- `BloatwareDbEntry(Name, PackageId, WingetId, Category, Method, Risk, EstimateMB)` — entrada en la DB
- `DetectedApp(Name, Category, Method, Risk, EstimateMB, PackageFN, WingetId)` — app detectada
- `BloatwareSummary(Count, TotalMB, SafeCount, CautionCount)` — resumen de escaneo
- `RemoveResult(Name, Ok, Method, Message)` — resultado de desinstalacion

**Database (mirror de `$script:bloatwareDb` del PS1)**
55 entradas en 5 categorias: Juegos (11), Comunicacion (8), Telemetria (14), OEM (10), Utilidades (12).
Metodos: `"appx"` / `"winget"` / `"appx+winget"`.

**`GetBloatwareListAsync()`** — corre en `Task.Run`. Mirror de `Get-BloatwareList`:
- `GetInstalledAppxMap()`: ejecuta PowerShell `-NoProfile -NonInteractive` con `Get-AppxPackage` (usuario actual + AllUsers), indexa por `PackageFamilyName.ToLower()`.
- `IsWingetAvailableCore()`: ejecuta `winget --version` con timeout de 5s.
- `GetWingetInstalledMap()`: ejecuta `winget list --accept-source-agreements` con timeout de 10s, parsea IDs de la salida columnar.
- Matching: `actualName.Contains(needle) || needle.Contains(actualName)` (equivalente al `-like "*x*"` del PS1).
- Retorna lista ordenada por Category, Name.

**`GetSummary(list)`** — calcula Count, TotalMB, SafeCount, CautionCount.

**`RemoveAppAsync(app, ct)`** — corre en `Task.Run`. Mirror de `Remove-BloatItem`:
- AppX: PowerShell `Get-AppxPackage -Name '*fragment*' | Remove-AppxPackage` + `Remove-AppxProvisionedPackage -Online`. Timeout 60s.
- Winget: `winget uninstall --id "..." --silent --accept-source-agreements --disable-interactivity`. Timeout 60s.
- Fallback automatico: si AppX falla y el metodo es `appx+winget`, intenta winget.

**`SaveBloatBackup(sessionPath, apps)`** — serializa la lista de apps eliminadas a `bloatware_removed.json` en la sesion de backup activa.

**Wiring en MainWindow (mirror del modulo 4B del PS1)**

- `ScanBloatwareAsync()` — deshabilita botones, llama `GetBloatwareListAsync`, actualiza las 4 stats cards, muestra estado de winget, renderiza lista filtrada.
- `RenderBloatItems(list, filter)` — construye filas en codigo: grid 6 cols (Checkbox/32 | Nombre/Star | Categoria-badge/100 | Metodo-badge/70 | MB/75 | Riesgo-badge/80). Colores por categoria y riesgo identicos al PS1. Checkbox pre-marcado si `Risk == "safe"`.
- `UpdateBloatStats()` — recalcula `lblBloatSelected` y habilita/deshabilita `btnRemoveBloat`.
- `BloatSelectSafe()` — marca solo los "safe" visibles (mirror de `btnBloatSelAll` del PS1).
- `BloatSelectNone()` — desmarca todos.
- `OnBloatFilterChanged` — re-renderiza desde cache sin re-escanear.
- `InvokeRemoveBloatAsync()` — recopila seleccionados, muestra confirmacion con detalle de safe/precaucion, guarda `bloatware_removed.json`, ejecuta en `App.Worker.RunAsync`, navega a consola durante la operacion, re-escanea al terminar, muestra resultado final.

**Eventos wired en OnLoaded**
`btnScanBloat`, `btnRemoveBloat`, `btnBloatSelAll`, `btnBloatSelNone`, `cboBloatFilter.SelectionChanged`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 3.5 — Modo silencioso CLI (-Silent -Preset)

**Archivos creados**
- `src-csharp/WinBoost/CliArgs.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml` — `StartupUri` reemplazado por `ShutdownMode="OnExplicitShutdown"`
- `src-csharp/WinBoost/App.xaml.cs` — `OnStartup` + `RunSilentAsync`

**`CliArgs`**

Record `(Silent, Preset, DnsIndex, ShowHelp)`. `CliArgs.Parse(string[] args)` acepta prefijos `-`, `--`, `/`.

- `-Silent` / `--silent` — activa modo sin ventana
- `-Preset Gaming|Prod|Safe` — normaliza a "Gaming", "Prod" o "Safe" (default: "Safe")
- `-DNS 0-3` — indice del proveedor DNS (0=Cloudflare, 1=Google, 2=Quad9, 3=AdGuard; default: 0)
- `-Help` / `-h` / `-?` — muestra cuadro de dialogo con la ayuda y sale

**`App.OnStartup`**

Reemplaza `StartupUri` con logica explicita:
- `ShowHelp` → `MessageBox` con `UsageText`, `Shutdown(0)`
- `Silent` → `RunSilentAsync`, `await Task.Delay(6000)` (ventana para el toast), `Shutdown(0)`
- Normal → `ShutdownMode = OnMainWindowClose`, `Settings.Load()`, `new MainWindow().Show()`

**`RunSilentAsync(CliArgs)`**

Modo headless completo (sin ventana, sin dialogos):
1. Crea directorio `~/.OptimizarPC/`.
2. `Settings.Load()` + `Backup.NewBackupSession()`.
3. Obtiene preset via `OptimizationService.GetPreset(args.Preset)`.
4. `SystemInfo.GetSystemInfoAsync()` para `HasSsd`, `IsLaptop`, `TotalRamGb`.
5. `Worker.RunAsync(svc.RunAsync(...))` — `App.Logger` y `App.Progress` son null en este modo; los `?.` en `OptimizationService` los silencian sin crash.
6. Si OK: `Backup.SaveSessionMetadata(...)`, append a `silent_run.log`, `ToastService.Show(...)`.
7. Si cancelado/error: escribe linea de error en el log, toast con mensaje de error.

**Formato de `silent_run.log`**
```
[2026-06-26 03:45:12] OK | Preset:Gaming | Applied:28 | Skipped:3 | Freed:512.0 MB
[2026-06-26 03:46:30] ERROR | Access denied
```

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 3.4 — Invoke-OptimizeFinish: resumen de resultado + score delta + toast

**Archivos creados**
- `src-csharp/WinBoost/FinishOptimizationDialog.xaml`
- `src-csharp/WinBoost/FinishOptimizationDialog.xaml.cs`

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `FinishOptimizationAsync` + llamada desde `OnRunOptimizationAsync`

**`FinishOptimizationDialog`**

Dialogo modal dark que aparece al completar la optimizacion. Recibe `OptResult`, `scoreBefore`, `scoreAfter`, `needsReboot`.

- 3 tarjetas en fila: **N aplicadas** (verde) · **M omitidas** (gris) · **X MB liberados** (cyan)
- Panel `panelScore` (Collapsed si ambos scores son 0): muestra `scoreBefore → scoreAfter` y badge `+N` si mejoro.
- Panel `panelReboot` (Collapsed si no aplica): advertencia amarilla sobre PageFile requiriendo reinicio.
- Boton "Ver historial" → cierra y llama `SetActiveNav(5)` via `GoToHistory = true`.
- Boton "Cerrar" → cierra sin navegar.
- Draggable por title bar, × cierra.

**`FinishOptimizationAsync(OptResult res, sel)`**

Mirror de `Invoke-OptimizeFinish` del PS1. Se llama desde `OnRunOptimizationAsync` tras `await RecalcScoreAsync()`:

1. Calcula `delta = scoreAfter - scoreBefore`.
2. Si `delta > 0`: muestra `scoreDeltaBadge` con `lblScoreDelta = "+N"` en el widget del sidebar.
3. `App.Backup.SaveSessionMetadata(freedMb, scoreBefore, scoreAfter, preset: "Manual")` — escribe `session.json`.
4. `ToastService.Show("WinBoost", "N acciones aplicadas · X MB liberados · score +N")` en background.
5. Muestra `FinishOptimizationDialog`. Si `GoToHistory == true` → navega a tab 5.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 3.3 — Dialogo de confirmacion / analisis

**Archivos creados**
- `src-csharp/WinBoost/ConfirmOptimizationDialog.xaml`
- `src-csharp/WinBoost/ConfirmOptimizationDialog.xaml.cs`

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `OnRunOptimizationAsync` ahora muestra el dialogo antes de ejecutar

**`ConfirmOptimizationDialog`**

- Constructor recibe `IReadOnlyList<PlanAction>` de `BuildActionPlan`.
- `lblActionCount`: "Se aplicaran N acciones en tu sistema." 
- `panelHighImpact` (Collapsed si no hay): lista las acciones con `Impact == "high"` en amarillo.
- `spActions`: lista de acciones agrupadas por categoria (Seguridad > Limpieza > Rendimiento > Privacidad > Red > Servicios).
  Cada fila: dot · Label (170px) · Detail (star, wrap).
  Labels de impacto alto en naranja/negrita, resto en gris claro.
- `panelRestorePoint` (Collapsed si no aplica): nota verde sobre el punto de restauracion.
- Botones: "Cancelar" (DlgBtnSec, `DialogResult = false`) + "Ejecutar optimizacion" (DlgBtnMain, `DialogResult = true`).
- Title bar draggable via `MouseLeftButtonDown -> DragMove()`. Boton × cierra con `DialogResult = false`.
- `WindowStyle="None"`, `AllowsTransparency="True"`, fondo #0D0D0D + `DropShadowEffect`.
- Estilos `DlgBtnMain` / `DlgBtnSec` definidos inline (no dependen de recursos de MainWindow).

**Integracion en `OnRunOptimizationAsync`**
- `dnsIdx` se calcula antes del dialogo para pasarlo a `BuildActionPlan`.
- Si `ShowDialog() != true` → retorno inmediato (sin backup ni ejecucion).
- Si el usuario confirma → flujo original (NewBackupSession, TakeSnapshotAsync, RunAsync, RecalcScore).

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 3.2 — Build-ActionPlan: resumen de plan en vivo en el footer

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml` — agrega fila `lblPlanSummary` + `lblPlanWarning` en el footer
- `src-csharp/WinBoost/MainWindow.xaml.cs` — `UpdatePlanSummary()` + wiring de los 35 checkboxes

**Que agrega**

- `UpdatePlanSummary()` — llama `OptimizationService.BuildActionPlan(sel, dnsIdx)` y actualiza:
  - `lblPlanSummary`: "N acciones · Cat1 · Cat2 · ..." (azul) o "Nada seleccionado" (gris)
  - `lblPlanWarning`: advertencia visible si hay acciones de impacto alto (EventLogs, PageFile); oculto si no
- Todos los 35 checkboxes y `cboDNSProvider` ahora llaman `UpdatePlanSummary()` al cambiar.
- `ApplyPreset`, `SelectAll` y `LoadProfile` también invocan `UpdatePlanSummary()`.
- `UpdatePlanSummary` internamente llama `UpdateDnsHint()` para mantener el hint de DNS sincronizado.
- Estado inicial correcto: `LoadProfile()` aplica preset Safe y dispara el resumen en `OnLoaded`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 3.1 — OptimizationService: motor de optimizacion completo

**Archivos creados**
- `src-csharp/WinBoost/Services/OptimizationService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/NativeMethods.cs` — agrega `SHEmptyRecycleBin` (shell32) + helper `EmptyRecycleBin()`
- `src-csharp/WinBoost/GlobalUsings.cs` — agrega `CheckBox = System.Windows.Controls.CheckBox`
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Optimizer` singleton
- `src-csharp/WinBoost/MainWindow.xaml` — agrega `btnCancelOpt` (BtnDanger, Collapsed por defecto)
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring de UI de optimizacion + cache de system info

**Models**
- `DnsProvider(Name, Primary, Secondary)` — proveedor DNS
- `PlanAction(Category, Label, Detail, Impact)` — accion del plan (para 3.2/3.3)
- `OptResult(Applied, Skipped, FreedMb)` — resultado de la optimizacion

**`OptimizationService`**

- `GetPreset(name)` — devuelve diccionario `{key: bool}` para Gaming / Prod / Safe.
  Mirror exacto de `$presetGaming`, `$presetProd`, `$presetSafe` del PS1.
- `DnsProviders` — lista estatica de 4 proveedores (Cloudflare, Google, Quad9, AdGuard).
- `BuildActionPlan(sel, dnsIndex)` — construye lista de `PlanAction` ordenada segun seleccion.
  Mirror de `Build-ActionPlan` del PS1 (para usar en dialogo de confirmacion, 3.3).
- `RunAsync(sel, hasSsd, isLaptop, totalRamGb, sysDrive, dnsIndex, altDrive, moveToAlt, ct)` — orquestador.
  Fases en orden: RestorePoint → Cleanup → PowerPlan → HPET → Registry → Network → Services →
  FastStartup → PageFile → TrimDesfrag → Visual.
  `ct.ThrowIfCancellationRequested()` entre fases criticas.

**Fases internas (mirror de PS1)**
- `CleanupTweaks` — TempUser, TempSys, Prefetch (SSD-only), WinUpdate, Browsers (5 navegadores),
  Thumbnails, Recycle (`NativeMethods.EmptyRecycleBin()`), EventLogs (excluye Security).
- `RegistryTweaks` — GPUPrio (DXGI), PowerThrottlingOff, MouseAccel, GameDVR/GameMode,
  Telemetry, Cortana, Notif, Tasks (5 tareas via schtasks).
- `NetworkTweaks` — Nagle OFF (por adaptador via `DHCP​IPAddress`), TCP/IP (netsh 4 comandos),
  DNS WMI (`Win32_NetworkAdapterConfiguration.SetDNSServerSearchOrder`), DNSFlush, DisableIPv6 (0x20).
- `ServiceTweaks` — Xbox (3 svcs), DiagTrack, WerSvc, SysMain (SSD-only), Maps+lfsvc, Fax+RemoteRegistry, WSearch (SSD-only).
- `PowerPlanTweaks` — Ultimate Performance GUID `e9a42b02-...`, fallback SCHEME_MIN; laptop: siempre SCHEME_MIN.
- `HpetTweaks` — bcdedit: `useplatformtick yes` + `disabledynamictick yes`.
- `FastStartupTweaks` — HiberbootEnabled=0 + `powercfg /hibernate off`.
- `PageFileTweaks` — Win32_ComputerSystem.AutomaticManagedPagefile=false + Win32_PageFileSetting; rollback si falla.
- `TrimTweaksAsync` (async) — fsutil TRIM, schtasks ScheduledDefrag, Optimize-Volume ReTrim via PowerShell
  con loop de progreso cada 1s (ct-cancelable).
- `VisualTweaks` — VisualFXSetting=2, FontSmoothing=2, EnableTransparency=0 si RAM<=8GB.

**Helpers privados**
- `SetReg` — llama `App.Backup.SaveRegBackup` (PS-format path), luego `OpenOrCreateKey().SetValue`.
- `DisableSvc` — llama `App.Backup.SaveSvcBackup`, Stop+WaitForStatus 10s, registry Start=4 (Disabled).
- `RemoveDir`, `GetFolderMb`, `ClearEventLogs`, `GetSsdDriveLetters` (MSFT_PhysicalDisk MediaType=4, fallback fixed drives).
- `OpenOrCreateKey` — parsea `HKLM:\...` / `HKCU:\...` → `Registry.LocalMachine/CurrentUser.CreateSubKey`.
- `RunProcess` / `RunProcessCapture` — timeout 30s, no shell, no ventana.

**Wiring en MainWindow**

- `ApplyPreset(name)` — aplica diccionario de preset a todos los checkboxes + `UpdateDnsHint`.
- `AllOptCheckboxes()` — diccionario `{key → CheckBox}` para los 35 controles de optimizacion.
- `GetCurrentSel()` — snapshot del estado actual de checkboxes como `IReadOnlyDictionary<string, bool>`.
- `SelectAll(value)` — marca/desmarca todos; EventLogs siempre queda en false en seleccionar-todo.
- `UpdateDnsHint()` — actualiza `lblDNSHint` con Primary/Secondary del proveedor seleccionado.
- `SaveProfile() / LoadProfile()` — persiste estado de checkboxes en `~/.OptimizarPC/opt_profile.json`.
  `LoadProfile` se llama en OnLoaded; aplica "Safe" si no hay perfil guardado.
- `OnRunOptimizationAsync()` — valida seleccion, `NewBackupSession`, toma snapshot, deshabilita UI,
  llama `App.Worker.RunAsync(new OptimizationService().RunAsync(...))`,
  restaura UI, actualiza `lblSpaceFreed`, `App.Progress.Set(100)`, `RecalcScoreAsync()`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 2.5 — DeviceService: dispositivos con problemas + inventario de drivers

**Archivos creados**
- `src-csharp/WinBoost/Services/DeviceService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Devices` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — ScanDevicesAsync, ScanDriversAsync, renders, filtro de clase

**Que reemplaza**
Equivalente a los módulos F1.7/F1.8 del PS1:
`Get-ProblemDevices`, `Update-DeviceBadge`, `Render-ProblemDevices`, `Scan-DeviceProblems`,
`Render-DriverInventory`, `Populate-DriverClassFilter`, `Scan-DriverInventory`.

**`DeviceService`**

- `GetProblemDevicesAsync()` — corre en `Task.Run`. WMI `Win32_PnPEntity WHERE ConfigManagerErrorCode <> 0`.
  Equivalente a `Get-PnpDevice | Where-Object { $_.Status -ne "OK" }` del PS1.
  Retorna `ProblemDevice { FriendlyName, Status, ErrorCode }` ordenado por nombre.

- `GetDriverInventoryAsync()` — corre en `Task.Run`. WMI `Win32_PnPSignedDriver`.
  Filtra registros sin `DeviceName`. Parsea `DriverDate` con `ManagementDateTimeConverter`.
  Retorna `DriverEntry { DeviceName, DeviceClass, DriverVersion, DriverDate, IsSigned }` ordenado por nombre.

**Wiring en MainWindow**

- `ScanDevicesAsync()` — deshabilita botón, llama `GetProblemDevicesAsync`, actualiza
  `badgeDeviceProblems` (Visible si n>0), `lblDeviceProblemsStatus`, re-habilita botón.

- `RenderProblemDevices(IReadOnlyList<ProblemDevice>)` — grid 3 cols (Nombre/Star | Badge/120 | Código/80).
  Colores: "Error" → fondo #2A0A0A + rojo; otros → fondo #2A1A00 + amarillo. Mirror exacto del PS1.

- `ScanDriversAsync()` — llama `GetDriverInventoryAsync`, llama `PopulateDriverClassFilter`,
  render completo, status: "$n drivers | $unsigned sin firma".

- `PopulateDriverClassFilter(drivers)` — desconecta SelectionChanged, reconstruye ítems de
  `cboDriverClass` con clases únicas ordenadas + "Todas las clases" al inicio.

- `OnDriverClassChanged` — filtra `_driverList` por clase seleccionada y llama `RenderDriverInventory`.
  `_driverList` guardado como campo para reusar sin re-escanear.

- `RenderDriverInventory(IReadOnlyList<DriverEntry>)` — grid 4 cols (Nombre/Star | Versión/120 | Fecha/110 | Firmado/80).
  Fondo #1A0000 si no firmado, #1A1000 si fecha >2 años. Fecha amarilla si >2 años.
  Firmado: verde "Si" / rojo "No".

- `btnOpenDevMgmt.Click` → `Process.Start("devmgmt.msc", UseShellExecute=true)`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 2.4 — ProcessService: procesos pesados async sin Sleep en hilo UI

**Archivos creados**
- `src-csharp/WinBoost/Services/ProcessService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Processes` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — RefreshProcessListAsync, RenderProcessList, timer, kill

**Que reemplaza**
Equivalente a los modulos 5A/5B del PS1:
`$script:systemProcessNames`, `Test-SystemProcess`, `Get-ProcessDetails`,
`Get-HeavyProcesses`, `Render-ProcessList`, `Refresh-ProcessList`,
`Start-ProcTimer`, `Stop-ProcTimer`, `Stop-ManagedProcess`.

**`ProcessService`**

- `SystemProcessNames` — HashSet<string> OrdinalIgnoreCase con ~40 procesos del sistema.
  Mirror exacto de la lista del PS1 (kernel, shell, seguridad, drivers, update, store).

- `GetHeavyProcessesAsync(topN=15, includeSystem=false)` — corre en `Task.Run`.
  Snapshot de `TotalProcessorTime` en ms por PID. Delta con snapshot anterior cacheado
  en `_sample1` / `_sampleTime1`: `CpuPct = delta / elapsed / cpuCount * 100`.
  Primera llamada: elapsed=1ms → CPU=0 (sin baseline, igual que PS1 F2.8).
  Combina Top-N por CPU + Top-N por RAM, deduplicados por PID, ordenados por
  `CpuPct*1.5 + RamMb/100`. Retorna hasta `topN*2` entradas.

- `IsSystemProcess(Process)` — mirror de `Test-SystemProcess` del PS1: nombre en lista,
  PID<=4, path en System32/SysWOW64/SystemApps, o sin path (kernel). Conservador: si
  falla la lectura, retorna true.

- `StopProcessAsync(int pid)` — doble validacion de seguridad via `IsSystemProcess`.
  Llama `proc.Kill()`. Retorna `StopResult { Ok, Message }`.

**Wiring en MainWindow**

- `RefreshProcessListAsync()` — guard `_procRefreshing` para no lanzar dos refreshes
  simultaneos. Llama `GetHeavyProcessesAsync`, actualiza `lblProcsCpuTotal`,
  `lblProcsCount`, `lblProcsStatus` con timestamp.

- `RenderProcessList(IReadOnlyList<ProcessEntry>)` — construye filas en codigo igual que
  PS1: Border + Grid 6 columnas (Name/Desc | PID | CPU%+barra | RAM | Company | Accion).
  CPU color: rojo>=50% / amarillo>=20% / azul. RAM color: rojo>=1GB / amarillo>=300MB / verde.
  Procesos sistema: fondo #0A0A0F + badge "Sistema". Procesos normales: boton Terminar.

- `StartProcTimer()` / `StopProcTimer()` — DispatcherTimer a 3s. Actualiza contenido y
  color de `btnToggleProcTimer` (azul=ON, gris=OFF). `ToggleProcTimer()` como dispatcher.

- `OnKillProcessAsync(pid, name)` — MessageBox de confirmacion → `StopProcessAsync` →
  log "ok" y refresh, o log "err" + MessageBox de error.

- Eventos wired en OnLoaded: `btnRefreshProcs.Click`, `btnToggleProcTimer.Click`,
  `chkShowSysProcs.Click`.

- `OnClosed` detiene `_procTimer` junto con `_monitorTimer`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 2.3 — ThermalService: temperaturas CPU/GPU integradas en el monitor

**Archivos creados**
- `src-csharp/WinBoost/Services/ThermalService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Thermal` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — ticker de 5 ticks, UpdateThermalDisplay, BrushGray

**Que reemplaza**
Equivalente al modulo 6A del PS1:
`Get-CPUTemperature`, `Get-GPUTemperature`, `Get-ThermalStatus`, `Update-ThermalDisplay`.

**`ThermalService`**

- `GetThermalStatusAsync()` — corre en `Task.Run`. Llama CPU y GPU en secuencia
  (igual que PS1), retorna `ThermalStatus { Cpu, Gpu, OverallStatus }`.

- `GetCpuThermal()` — consulta `MSAcpi_ThermalZoneTemperature` en `root\wmi`.
  Conversion: `(raw - 2732) / 10.0` (decimos de Kelvin a Celsius).
  Filtra valores fuera de rango (0-120°C). Calcula promedio y maximo.
  Thresholds: normal <70 | warning 70-85 | critical >85.

- `GetGpuThermal()` — dos intentos en orden:
  1. `root\LibreHardwareMonitor` → clase `Sensor`, filtra SensorType=Temperature y Name~GPU.
  2. `root\OpenHardwareMonitor` → mismo esquema.
  Source reportado como `"lhm"` o `"ohm"`. Si ambos fallan: Available=false.

**Wiring en MainWindow**

- `_thermalTick` / `_thermalReading` — ticker de 5 ticks (= ~5s por tick 1s del timer)
  con guard de concurrencia para no lanzar dos lecturas WMI simultaneas.
- `UpdateThermalDisplay(ThermalStatus)` — mirror de `Update-ThermalDisplay` del PS1:
  barras de altura `Max(2, Round(110 * Min(100, tempC) / 100))`, colores reactivos
  (`TempBrush`: verde/amarillo/rojo), `N/D + BrushGray` cuando no disponible.
  `lblGPUTempSource.Visibility` Collapsed/Visible segun disponibilidad GPU.
- `BrushGray` (#555555) — brush estatico congelado para estado N/D.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 2.2 — SnapshotService: captura de estado + comparativa

**Archivos creados**
- `src-csharp/WinBoost/Services/SnapshotService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Snapshots`, `App.SnapshotBefore`
- `src-csharp/WinBoost/MainWindow.xaml.cs` — snapshot de arranque async + log a consola

**Que reemplaza**
Equivalente a los modulos 11A/11B del PS1:
`Get-BootTimeSec`, `Get-IdleRAMMB`, `Get-ProcessCount`, `Get-SystemSnapshot`,
`Compare-Snapshots`. La UI del dialogo de comparacion viene en FASE 3.

**`StateSnapshot`** (record inmutable):
`Timestamp, CpuIdle (%), RamFreeMb, SvcCount, Score, ProcCount, DiskFreeMb, BootTimeSec`

**`SnapshotService.TakeSnapshotAsync(score=-1)`**
Corre en `Task.Run`. Recolecta en paralelo conceptual (secuencia en background):
- `GetCpuIdle`: `Win32_Processor.LoadPercentage` → `100 - avg`
- `GetRamFreeMb`: `Win32_OperatingSystem.FreePhysicalMemory / 1024`
- `GetRunningServiceCount`: `ServiceController.GetServices().Count(Running)`
- `GetProcessCount`: `Process.GetProcesses().Length`
- `GetBootTimeSec`: EventLogReader en `Microsoft-Windows-Diagnostics-Performance/Operational`
  → EventID=100 → campo `BootTime` via XDocument parse → ms / 1000. Retorna -1 si no disponible.
- `GetDiskFreeMb`: `DriveInfo(SystemDrive).AvailableFreeSpace / 1MB`

**`SnapshotService.CompareSnapshots(before, after)`**
Mirror exacto de `Compare-Snapshots` PS1. Retorna `IReadOnlyList<CompareRow>` con:
`Label, Before, After, Delta, HigherBetter, Status ("better"/"neutral"/"worse")`.
Las 7 metricas: Score, CPU libre, RAM disponible, Disco libre, Servicios activos,
Procesos activos, Tiempo de arranque.

**Wiring MainWindow**
Al arrancar la app (dentro de `LoadSystemInfoAsync` ya en background), se toma un
`TakeSnapshotAsync` y el resultado se guarda en `App.SnapshotBefore`. Se loguea a
la consola: `"Snapshot inicial: Boot Xs | RAM libre NNN MB | N procesos"`.
Esto valida que la operacion corre off-UI-thread sin congelar la ventana.

`App.SnapshotBefore` es el punto de escritura de FASE 3 (justo antes de optimizar)
y lectura de FASE 4+ (reporte HTML, dialogo de comparacion).

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 2.1 — SystemInfoService: system info + score + auditoria

**Archivos creados**
- `src-csharp/WinBoost/Services/SystemInfoService.cs`

**Archivos modificados**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.SystemInfo` singleton
- `src-csharp/WinBoost/MainWindow.xaml.cs` — wiring de controles info/score

**Que reemplaza**
Equivalente a los modulos 3A y 3B del PS1:
`$IS_LAPTOP / $HAS_SSD / $cpuName / $gpuName / $totalRAM / $osCaption` (info del sistema),
`$script:auditItems`, `Get-SystemScore`, `Update-ScoreWidget`, `Update-ScorePanel`,
`Animate-BarWidth`, `Animate-ScoreCount`.

**SystemInfoService**

- `GetSystemInfoAsync()` — recolecta CPU/GPU/RAM/OS/chassis/disco en `Task.Run`.
  Retorna `SystemSnapshot` (record inmutable).
- `RunAuditAsync()` — ejecuta los 17 checks async y calcula score 0-100 contra
  la suma de pesos de los items (equivalente a `maxPoints = $auditItems | Measure-Object Weight -Sum`).
  Retorna `AuditResult` con Items, ByCategory, OkCount/FailCount.

**Checks implementados (mirror exacto de $script:auditItems)**
- Rendimiento (26 pts): HPET (bcdedit), GPUPrio (reg), PowerThrot (reg),
  MouseAccel (reg), FastStartup (reg), Visual (reg)
- Privacidad (26 pts): Telemetry (reg), GameDVR (reg), Cortana (reg),
  Tasks (schtasks x3 — disabled si >= 2 de 3)
- Red (18 pts): DNS (NetworkInterface — conocidos Cloudflare/Google/Quad9/AdGuard),
  Nagle (reg Interfaces), TCPTuning (netsh RSS)
- Servicios (22 pts): SvcDiag (DiagTrack), SvcXbox (>= 2 de 3 Xbox svcs),
  SvcFax (Fax OR RemoteRegistry), SvcWER (WerSvc)

**Wiring en MainWindow.xaml.cs**

- `LoadSystemInfoAsync()`: llama `GetSystemInfoAsync` → `PopulateSystemInfoControls`
  → encola `RunAndDisplayScoreAsync` en `DispatcherPriority.Background`
  (mismo patron que `BeginInvoke Loaded` del PS1).
- `PopulateSystemInfoControls`: rellena `lblCPU/GPU/RAM/Disk/OS`, `infoCPU/GPU/RAM/Disk/OS`,
  `infoType`, `badgeLaptop`.
- `UpdateScoreWidget`: actualiza `lblScoreValue`, `scoreBar`, `scoreWidget.BorderBrush`,
  `lblScoreTooltipTitle/Detail`.
- `UpdateScorePanel`: actualiza `lblScorePanelValue/Label` y las 4 barras de categoria
  con `AnimateCategoryBar` (DoubleAnimation 500ms sobre Width).
- `RecalcScoreAsync`: handler de `btnRecalcScore` — recalcula async, anima numero con
  `AnimateScoreCount` (DispatcherTimer 20 pasos, cubic ease out).
- `OnMainTabsSelectionChanged`: al entrar al tab Info (index 4), re-dibuja las barras
  de categoria con `DispatcherPriority.Loaded` (ActualWidth disponible post-render).

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 1.3 — Validacion BackupService vs PS1: 5 bugs corregidos

**Archivo modificado**
- `src-csharp/WinBoost/Services/BackupService.cs`

Revision sistematica funcion-por-funcion contra el PS1 original. Diferencias encontradas y corregidas:

**Bug 1 — `IsRegFileValid`: char literal BOM**
El `'﻿'` en `.TrimStart()` es U+FEFF embebido como literal invisible en el codigo fuente.
Funciona en runtime pero es ilegible. Confirmado correcto; sin cambio de comportamiento.

**Bug 2 — `RestoreServicesFromSession`: `modeMap` incompleto**
PS1 incluia `"Boot"` y `"System"` en el mapa de startup modes. El C# inicial los omitia,
haciendo que servicios Boot/System caigan al default Manual en vez de preservar su tipo.
Fix: agregados `["Boot"] = ServiceStartMode.Boot` y `["System"] = ServiceStartMode.System`.

**Bug 3 — `RestoreServicesFromSession`: `startValue` switch incompleto**
Boot y System caian al `_ => 3` (Manual). Los valores DWORD correctos son Boot=0, System=1.
Fix: agregados los dos casos al switch antes del default.

**Bug 4 — `RestoreNetworkFromSession`: DNS DHCP reset**
`SetDNSServerSearchOrder([new string[0]])` pasa un array vacio que WMI NO interpreta como
"reset a DHCP" — requiere `null` como valor del array. Equivalente a `-ResetServerAddresses` del PS1.
Fix: `new object[] { null }` con `#pragma warning disable CS8625`.

**Bug 5 — `RestorePageFileFromSession`: `ManagementObject cs` sin disposal en rama de excepcion**
`cs.Dispose()` estaba al final del bloque `try`. Si una excepcion ocurria antes (ej. en el
bloque `else`), `cs` quedaba sin liberar. Fix: envuelto en `try/finally { cs?.Dispose(); }`.

**Diferencias aceptadas (no bugs):**
- `RestoreNetworkFromSession` usa el `IfIndex` guardado para buscar el adaptador en WMI,
  mientras el PS1 busca por nombre y usa el IfIndex ACTUAL. En la practica los indices
  no cambian entre backup y restore para adaptadores fisicos persistentes.
- `SaveSessionMetadata` no llama `Render-HistoryItems` (no existe aun en C# — se cablea en Fase 4.6).
- `RestorePageFileFromSession` usa `ManagementObject.Put()` (DCOM WMI) en vez de `Set-CimInstance`
  (WSMAN). Funcionalmente equivalente para Win10+.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 1.2 — BackupService: motor de restauracion + sesiones

**Archivos modificados**
- `src-csharp/WinBoost/Services/BackupModels.cs` — agrega `RestoreResult` y `BackupSessionInfo`
- `src-csharp/WinBoost/Services/BackupService.cs` — agrega restore functions, GetBackupSessions y CleanupOldBackups

**Que reemplaza**
Equivalente a: `Get-BackupSessions`, `Cleanup-OldBackups`, `Test-RegFileValid`,
`Restore-RegFromSession`, `Restore-ServicesFromSession`, `Restore-NetworkFromSession`,
`Restore-HpetFromSession`, `Restore-PageFileFromSession`, `Restore-NetshFromSession`,
`Restore-Session` (orquestador principal).

**Modelos nuevos**

`RestoreResult` — replica `@{ ok=N; failed=N; skipped=N; invalidFiles=@() }` del PS1.
`BackupSessionInfo` — replica el PSCustomObject de `Get-BackupSessions` (path, timestamp, freedMb, etc.)

**`GetBackupSessions()`** — enumera carpetas de BackupRoot descendente, deserializa session.json si existe, retorna `List<BackupSessionInfo>`. Equivalente a `Get-BackupSessions`.

**`CleanupOldBackups(int keepDays=30)`** — elimina carpetas con LastWriteTime anterior al cutoff. Equivalente a `Cleanup-OldBackups`.

**`RestoreSession(sessionPath, logFn?)`** — orquestador principal (equivalente a `Restore-Session`). Secuencia: registro → servicios → red → HPET/bcdedit → plan de energia → PageFile → TCP global (netsh). Acepta `Action<string,string>?` como callback de log (null = `App.Logger.Log`).

**Sub-funciones privadas:**

- `IsRegFileValid(path)` — detecta BOM UTF-16 LE (FF FE) o ANSI; valida cabecera `.reg` + presencia de `[HKEY_`.
- `RestoreRegFromSession(sessionPath)` — importa archivos `reg_*.reg` via `reg.exe import`. Archivos < 5 bytes = clave no existia, se omiten (Skipped). Archivos invalidos se registran en `InvalidFiles`.
- `RestoreServicesFromSession(meta)` — restablece startup type via registro (`HKLM\...\Services\{name}\Start`, valores 2/3/4). Restaura `DelayedAutoStart=1` si aplica. Intenta `svc.Start()` si `WasRunning`.
- `RestoreNetworkFromSession(meta)` — DNS via `Win32_NetworkAdapterConfiguration.SetDNSServerSearchOrder()`; IPv6 binding via `MSFT_NetAdapterBindingSettingData.Enable()/Disable()` en ROOT\StandardCimv2; flush DNS al terminar.
- `RestoreHpetFromSession()` — `bcdedit /deletevalue` para los tres valores de timer.
- `RestorePageFileFromSession(sessionPath, log)` — si AutomaticManaged=true: `cs.Put()` con `AutomaticManagedPagefile=true`. Si false: borrar `Win32_PageFileSetting` actuales y recrear desde backup via `ManagementClass.CreateInstance()`.
- `RestoreNetshFromSession(sessionPath, log)` — parsea netsh_backup.txt con Regex, restaura autotuninglevel/chimney/rss/fastopen.

**Nota de implementacion — startup type sin SetService**
`ServiceController` en .NET no expone setter de StartupType. Se escribe directo a registro (`HKLM\...\Services\{name}\Start`) con los valores DWORD estandar (Automatic=2, Manual=3, Disabled=4), que es lo que `Set-Service` hace internamente.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 1.1 — BackupService: motor de backup de sesion

**Archivos creados**
- `src-csharp/WinBoost/Services/BackupModels.cs` — POCOs para session.json: `BackupAction`, `SvcEntry`, `NetEntry`, `PageFileEntry`, `PageFileBackup`, `SessionMetadata`
- `src-csharp/WinBoost/Services/BackupService.cs` — servicio con todos los metodos Save-*

**Archivos modificados**
- `src-csharp/WinBoost/WinBoost.csproj` — agrega `System.Management 7.0.0` (WMI) y `System.ServiceProcess.ServiceController 7.0.0`
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Backup` (singleton) y `App.Version = "4.1"`

**Paquetes NuGet agregados**
- `System.Management 7.0.0` — para WMI (`ManagementObjectSearcher`): Win32_ComputerSystem, Win32_PageFileSetting, MSFT_NetAdapterBindingSettingData
- `System.ServiceProcess.ServiceController 7.0.0` — para `ServiceController` (Get-Service)

**Que reemplaza**
Equivalente exacto al bloque de backup del PS1 (lineas ~648-1145):
`New-BackupSession`, `Save-RegBackup`, `Save-SvcBackup`, `Save-NetBackup`,
`Save-PowerPlanBackup`, `Save-PageFileBackup`, `Save-NetshBackup`, `Save-SessionMetadata`.

**`NewBackupSession()`** — crea carpeta `<BackupRoot>/<yyyy-MM-dd_HH-mm-ss>`, resetea listas internas.

**`SaveRegBackup(regPath, label)`** — convierte ruta PS (`HKLM:\...`) a nativa (`HKLM\...`), llama `reg export` via `Process`, guarda accion con flag `Existed`.

**`SaveSvcBackup(svcName)`** — usa `ServiceController` para `Status` + `StartType`; detecta `AutoDelayed` via `HKLM\...\Services\<name>\DelayedAutoStart`; guarda entrada en `_svcs` y accion en `_actions`.

**`SaveNetBackup()`** — obtiene adaptadores activos via `NetworkInterface.GetAllNetworkInterfaces()`; DNS IPv4 via `GetIPProperties().DnsAddresses`; estado de binding `ms_tcpip6` via WMI `MSFT_NetAdapterBindingSettingData` (ROOT\StandardCimv2).

**`SavePowerPlanBackup()`** — corre `powercfg /getactivescheme`, extrae GUID con Regex; lee `HibernateEnabled` del registro.

**`SavePageFileBackup()`** — consulta `Win32_ComputerSystem.AutomaticManagedPagefile` y `Win32_PageFileSetting`; serializa a `pagefile_backup.json`.

**`SaveNetshBackup()`** — corre `netsh int tcp show global`; guarda salida en `netsh_backup.txt`.

**`SaveSessionMetadata()`** — serializa `SessionMetadata` (version, timestamp, path, preset, MB liberados, scores, acciones, servicios, red) a `session.json`. Llamar al final de cada optimizacion.

**Nota de origen NuGet**: el entorno no tenia fuente NuGet configurada. Se agrego `https://api.nuget.org/v3/index.json` via `dotnet nuget add source`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 0.5 — Patron async base: WorkRunner

**Archivo creado**
- `src-csharp/WinBoost/Services/WorkRunner.cs`

**Archivo modificado**
- `src-csharp/WinBoost/App.xaml.cs` — agrega `App.Worker` como singleton estatico

**Que reemplaza**
El PS1 corre todo en el hilo UI y llama `Flush-UI` para dejar que WPF procese mensajes
pendientes entre pasos. Para trabajo largo usa `Start-Job + DispatcherTimer` para pollear
el resultado. En C# ninguno de esos patrones es necesario: `async/await` devuelve el hilo
UI entre pasos, y `Task.Run` mueve trabajo pesado a un thread pool.

**`WorkRunner`** — servicio que gestiona el ciclo de vida de operaciones async:
- `RunAsync(Func<CancellationToken, Task>)`: ejecuta la lambda; gestiona `CancellationTokenSource`,
  `IsRunning`, y el log de inicio/fin/cancel/error. Retorna `true` si completo con exito.
- `Cancel()`: cancela el token de la operacion en curso (no-op si no hay ninguna).
- `App.Worker`: singleton en `App`, accesible desde cualquier punto del codigo.

**Patron de uso** (fase 3 en adelante):
```csharp
await App.Worker.RunAsync(async ct => {
    App.Progress.Set(10, "Limpiando temporales...");
    await Task.Run(() => CleanTempFiles(), ct);    // off UI thread
    ct.ThrowIfCancellationRequested();
    App.Progress.Set(50, "Tweaks de registro...");
    await Task.Run(() => ApplyRegistryTweaks(), ct); // off UI thread
    App.Progress.Set(100, "Completado");
}, startMsg: "Iniciando optimizacion", doneMsg: "Optimizacion completada");
```

La lambda arranca en el hilo UI (progress/log directo, sin Dispatcher extra).
Despues de cada `await Task.Run` la ejecucion vuelve al hilo UI automaticamente.

**Meta de cierre Fase 0 verificada:**
- App abre: si (MainWindow + XAML compilado)
- Sidebar navega: si (SetActiveNav cableado)
- Settings cargan: si (App.Settings.Load/Apply en OnLoaded)

`dotnet build`: 0 errores, 0 advertencias.

---

## C# 0.4 — Infraestructura base: logging, progreso, toasts, settings, theme

**Archivos creados**
- `src-csharp/WinBoost/GlobalUsings.cs` — desambigua colisiones WPF/WinForms + repone System.IO
- `src-csharp/WinBoost/Services/AppSettings.cs` — modelo POCO con mismos defaults que el PS1
- `src-csharp/WinBoost/Services/SettingsService.cs` — Load/Save (System.Text.Json) + ApplyTheme + Apply
- `src-csharp/WinBoost/Services/AppLogger.cs` — equivalente a Write-Log: colores por tipo, badge de errores
- `src-csharp/WinBoost/Services/ProgressService.cs` — equivalente a Set-Progress
- `src-csharp/WinBoost/Services/ToastService.cs` — NotifyIcon balloon con DispatcherTimer de limpieza

**Archivos modificados**
- `src-csharp/WinBoost/WinBoost.csproj` — agrega `<UseWindowsForms>true</UseWindowsForms>` (para NotifyIcon)
- `src-csharp/WinBoost/App.xaml.cs` — expone `App.Settings`, `App.Logger`, `App.Progress` como singletons estaticos
- `src-csharp/WinBoost/MainWindow.xaml.cs` — cablea servicios en OnLoaded; log inicial "WinBoost iniciado"

**AppSettings** — replica `$script:settings` del PS1:
`Theme/Language/CloseAction/ShowSplash/ProcRefreshSec/RunAtStartup/BackupRoot/BackupRetainDays/TrialStartDate/TrialExpired/TechnicianName/GameAffinityEnabled`

**SettingsService**
- `Load()`: merge seguro desde JSON (null-safe, defaults intactos si falta un campo)
- `Save()`: WriteIndented a `%USERPROFILE%\.OptimizarPC\settings.json`
- `ApplyTheme(window)`: actualiza los 11 DynamicResource brushes (BrushAppBg..BrushFgDim) con las mismas paletas dark/light del PS1; modo "auto" lee `AppsUseLightTheme` del registro
- `Apply(window)`: ApplyTheme + RunAtStartup en `HKCU\...\Run`

**AppLogger** — replica `Write-Log`:
- Tipos: ok (#22C55E) / err (#EF4444) / skip (#666666) / head (#00C8FF) / info (#F59E0B)
- Labels: `"  OK   "` / `"  !!   "` / `"  --   "` / `" ====  "` / `"  >>   "`
- Formato: `"HH:mm:ss<label><mensaje>"`; siempre via `Dispatcher.BeginInvoke`
- Errores: actualiza `btnErrBadge` (Visible) y `lblErrCount` ("N error/es")

**ProgressService** — replica `Set-Progress`:
- Actualiza `progressBar.Value`, `lblProgress.Text`, `lblPct.Text` via `Dispatcher.BeginInvoke`

**ToastService** — replica `Show-ToastNotification` (path NotifyIcon del PS1):
- `NotifyIcon.ShowBalloonTip(5000ms)` + `DispatcherTimer` a 6s para `Dispose`
- Siempre via `Dispatcher.BeginInvoke` (safe desde background threads)

**GlobalUsings.cs** — necesario porque `UseWindowsForms=true` cambia el implicit usings set:
quita `System.IO` y agrega `System.Drawing` + `System.Windows.Forms`. El archivo repone
`System.IO` y fija aliases WPF para `Application/Button/RichTextBox/ProgressBar/Color/ColorConverter`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# Fase 0: NativeMethods — P/Invoke consolidado en clase dedicada

**Archivo creado**
- `src-csharp/WinBoost/NativeMethods.cs`

**Archivo modificado**
- `src-csharp/WinBoost/MainWindow.xaml.cs` — P/Invoke inline migrado a NativeMethods

**Contenido de NativeMethods**

Consolida los dos bloques `Add-Type` del PS1 mas el P/Invoke inline del monitor:

- **kernel32**: `GetSystemTimes`, `GlobalMemoryStatusEx`, `GetCurrentProcess`, `CloseHandle`
- **psapi**: `EmptyWorkingSet` (purga de Working Set / RAM)
- **ntdll**: `NtSetSystemInformation` (purga de Standby List)
- **advapi32**: `OpenProcessToken`, `LookupPrivilegeValue`, `AdjustTokenPrivileges` (elevacion de privilegios)
- **user32**: `GetForegroundWindow`, `GetWindowRect`, `MonitorFromWindow`, `GetMonitorInfo`, `GetWindowThreadProcessId`, `GetDesktopWindow`, `GetShellWindow` (deteccion fullscreen / Game Focus Mode)
- **Structs**: `FILETIME`, `MEMORYSTATUSEX`, `LUID`, `TOKEN_PRIVILEGES`, `RECT`, `MONITORINFO`
- **Helpers**: `FileTimeToLong`, `EnablePrivilege`, `PurgeStandbyList`, `MemoryStatusExSize`

`MainWindow.xaml.cs` ya no contiene ningun `[DllImport]` ni struct P/Invoke — todo pasa por `NativeMethods.*`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# monitor: barra de disco corregida a actividad real (PhysicalDisk % Disk Time) + color por umbral

**Archivo modificado**
- `src-csharp/WinBoost/MainWindow.xaml.cs`

**Problema**
La barra de Disco del monitor en tiempo real mostraba un valor fijo (~espacio usado del disco via `DriveInfo`), que casi no cambia. En un monitor en tiempo real eso es incorrecto: no refleja si el disco esta trabajando o idle.

**Fix**
- `_diskCounter` (`PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total")`): creado una sola vez en `OnLoaded`, antes de arrancar el timer. Reusado en cada tick.
- `ReadMetrics()`: reemplaza el bloque `DriveInfo` por `_diskCounter?.NextValue()`. El valor se clampea a 0-100 (el contador puede superar 100 en picos de I/O). El primer tick devuelve 0 (comportamiento normal del contador: necesita dos muestras).
- Lectura en `Task.Run` (fuera del hilo UI), igual que CPU y RAM.
- `_diskCounter?.Dispose()` en `OnClosed`.

**Color por umbral (aplicado a las tres barras)**
- `ThresholdBrush(pct, high, mid, okBrush)`: helper estatico que devuelve uno de tres brushes congelados.
- Disco / CPU: > 85% rojo, > 60% amarillo, resto verde (`#22C55E`).
- RAM: > 85% rojo, > 70% amarillo, resto azul (`#00C8FF`).
- Brushes estaticos congelados: `BrushGreen`, `BrushYellow`, `BrushRed`, `BrushBlue`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# Fase 0: navegacion del sidebar cableada (SetActiveNav, estilos activo/inactivo, footer condicional)

`SetActiveNav(int index)` implementado en `MainWindow.xaml.cs`:
- `mainTabs.SelectedIndex = index`
- Aplica estilo `BtnNavActive` al boton seleccionado y `BtnNav` al resto via `FindResource`.
- `footerBar`: `Visible` + `Height=Auto` en index 0; `Collapsed` + `Height=0` en el resto.
- Animacion de opacidad 0→1 (150ms) sobre `mainTabs.SelectedContent` al cambiar de tab.
- Botones cableados: navOptimizar(0)…navLicencia(8). `navTuning` no existe como `x:Name`
  en el XAML actual (el tab de Tuning Avanzado no tiene boton de nav propio aun).
- `SetActiveNav(0)` llamado en el evento `Loaded` para arrancar en Optimizar.

`dotnet build`: 0 errores, 0 advertencias.

---

## Inicio migracion C# — POC: shell WPF cargando el XAML existente + monitor de sistema async

Shell C#/WPF (.NET 8) en `src-csharp/WinBoost/` que reutiliza `OptimizarPC_UI.xaml` sin
modificaciones de contenido (solo se agrego `x:Class="WinBoost.MainWindow"` en el elemento
raiz). Valida tres puntos clave de la migracion:

- **Reuso de XAML**: el mismo .xaml compila tanto en PS1 como en C# sin cambios de estructura.
- **Campos tipados**: los `x:Name` del XAML se generan como campos del partial class;
  no se necesita `Get-Ctrl` ni `FindName`.
- **Patron async sin congelamiento de UI**: un `DispatcherTimer` tickea cada 1 segundo;
  la lectura de CPU% (via `GetSystemTimes`), RAM (via `GlobalMemoryStatusEx`) y disco
  (`DriveInfo`) corre en `Task.Run` fuera del hilo UI. Las barras del monitor se animan
  con `DoubleAnimation` de 200ms. La ventana se puede arrastrar y redimensionar sin
  tironeos mientras el monitor actualiza — el contraste central con PS5.1.

**Archivos creados**
- `src-csharp/WinBoost/WinBoost.csproj` — net8.0-windows, UseWPF, Nullable=enable, manifest asInvoker
- `src-csharp/WinBoost/app.manifest` — requestedExecutionLevel=asInvoker
- `src-csharp/WinBoost/MainWindow.xaml` — copia del XAML real + x:Class
- `src-csharp/WinBoost/MainWindow.xaml.cs` — monitor async (CPU/RAM/disco + animaciones)
- `src-csharp/WinBoost/App.xaml` / `App.xaml.cs` — generados por plantilla WPF

**Brushes faltantes**: ninguno. Todos los `DynamicResource` del XAML (BrushAppBg, BrushSidebar,
BrushCard, BrushDeep, BrushElev, BrushCtrl, BrushBorder, BrushFg1, BrushFg2, BrushFgMuted,
BrushFgDim) estan definidos dentro del propio XAML en `Window.Resources`.

`dotnet build`: 0 errores, 0 advertencias.

---

## Auto-updater v4.1 — Camino B (instalador silencioso) + verificacion de integridad

**Archivos modificados**
- `OptimizarPC_App.ps1` — `$UPDATE_CHECK_URL`, `Start-UpdateDownload`, `Apply-Update`,
  inyeccion de version en la GUI
- `OptimizarPC_UI.xaml` — Title de la ventana, `lblVersion`, `lblVersionAbout`
- `installer/WinBoost.iss` — seccion [Run] y [Setup]
- `version.json` — version, downloadUrl, sha256

**Repo y URLs**
- `$UPDATE_CHECK_URL` y `releaseUrl` apuntaban al repo viejo `OptimizarPC`; corregidos
  a `PC-optimizer` (el repo real del release).
- `downloadUrl` apuntaba a la pagina del tag (`/releases/tag/v4.0`), que devuelve HTML,
  no el binario; corregido al asset directo (`/releases/download/v4.1/WinBoost_Setup_4.1.exe`).

**Modelo de actualizacion: portable -> instalador**
- El modelo anterior copiaba un exe portable encima del exe en ejecucion, incompatible
  con la distribucion por instalador Inno Setup.
- `Apply-Update` reescrito: un helper (`do_update.ps1` en `%TEMP%\OptimizarPC_update`)
  espera a que cierre el proceso, ejecuta el instalador con
  `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL`, chequea ExitCode y relanza la app.
  El instalador actualiza exe + XAML + accesos directos de forma atomica (mata el bug de
  XAML desincronizado del modelo portable). El instalador hereda la elevacion del proceso
  (sin segundo UAC).
- Guard de modo desarrollo: si no corre como exe compilado, no ejecuta el instalador;
  abre la pagina del release en el navegador.

**Verificacion de integridad (hardening)**
- Se elimino el bypass donde un `sha256` vacio salteaba la verificacion (`if ($expectedHash)`):
  ahora un hash ausente ABORTA la instalacion en vez de saltearla.
- `Start-UpdateDownload` valida que el archivo descargado exista (Test-Path) y calcula el
  hash en try/catch. Ante archivo ausente/ilegible (cuarentena de antivirus) o mismatch de
  hash, no instala y avisa; en el caso de cuarentena hace fallback a la pagina del release.

**Fix error 740 en el instalador (`WinBoost.iss`)**
- La entrada [Run] postinstall lanzaba `WinBoost.exe` (manifest requireAdmin) via
  CreateProcess, que no puede elevar -> error 740. Solucion: flags `shellexec`
  (usa ShellExecute, respeta la elevacion) y `skipifsilent` (no autolanzar en el update
  silencioso, donde el relanzamiento lo hace el helper).
- [Setup]: `CloseApplications=yes`, `RestartApplications=no`, `UsePreviousAppDir=yes`.

**Version en la GUI derivada de `$VERSION`**
- El Title de la ventana y los labels `lblVersion` (sidebar) y `lblVersionAbout` (About)
  tenian "v4.0" hardcodeado en el XAML. Se vaciaron en el XAML y ahora se inyectan en
  runtime desde `$VERSION` en `Add_ContentRendered` (y `lblVersionAbout` tambien en
  `Render-SettingsUI`, que es lazy). Fuente unica de version: `$VERSION`.

**version.json**
- `version: "4.1"`, `downloadUrl` al asset v4.1, `sha256` real del instalador.

---

## F2.3 — Proteccion de licencia con firma asimetrica RSA-2048

**Archivos modificados**
- `OptimizarPC_App.ps1` — Modulo 12A reemplazado, handler de activacion actualizado
- `OptimizarPC_UI.xaml` — label y TextBox del tab Licencia actualizados
- `.gitignore` — excluye `_private_key.xml`

**Archivos nuevos**
- `Gen-License.ps1` — herramienta interna para emitir licencias con la clave privada

**Problema**
`$script:LICENSE_SALT = "OptPC40_LicSalt_v1"` y `$script:TECH_LICENSE_SALT = "OptPC40_TechLic_v1"` estaban embebidos como strings legibles en el PS1. Cualquiera que extrajera el codigo del exe podia computar `SHA256(HWID + salt)` y generar claves validas para cualquier equipo.

**Solucion**
- Se genera un par de claves RSA-2048 con `RSACryptoServiceProvider`.
- La **clave publica** queda embebida en `$script:LICENSE_PUBLIC_KEY_XML` (en el exe).
- La **clave privada** vive unicamente en `_private_key.xml` (fuera del repo, `.gitignore`).
- `Gen-License.ps1` lee la clave privada y firma el mensaje correspondiente al tier.

**Mensajes firmados**
- Pro: `"WINBOOST-PRO-<HWID>"` — firma distinta para cada hardware
- Tecnico: `"WINBOOST-TECH"` — firma fija, multi-PC

**Funciones reemplazadas**
- `Get-ExpectedKey` → eliminada (era para el emisor, ahora esta en Gen-License.ps1)
- `Get-ExpectedTechKey` → eliminada (idem)
- `Test-LicenseKey` → ahora llama `Test-LicenseSignature` con RSA
- `Test-TechLicenseKey` → ahora llama `Test-LicenseSignature` con RSA
- Nueva: `Test-LicenseSignature` — `RSACryptoServiceProvider.VerifyHash` con SHA256

**Formato de clave**
- Antes: `XXXX-XXXX-XXXX-XXXX` (19 chars, SHA256 truncado)
- Ahora Pro: Base64 de 256 bytes (firma RSA-2048, ~344 chars, pegar desde email)
- Ahora Tech: `TECH-<Base64>` (~349 chars)

**XAML**
- Label actualizado: "Pega tu clave de activacion (la recibiras por email al comprar)"
- `CharacterCasing="Upper"` removido del TextBox (Base64 es case-sensitive)
- `MaxLength="19"` removido (firma es mucho mas larga)
- `FontSize` del TextBox reducido de 13 a 11 para que quepa la firma

**Gen-License.ps1**
```powershell
# Generar licencia Pro
.\Gen-License.ps1 -HardwareID "A1B2C3D4E5F60718"

# Generar licencia Tecnico
.\Gen-License.ps1 -Tech

# Rotar el par de claves RSA
.\Gen-License.ps1 -GenerateKeys
```

---

## F2.20 — Afinidad de CPU automatica en Game Focus Mode

**Archivo modificado**
- `OptimizarPC_App.ps1` — settings, helper, Apply/Restore modificados, card UI en Ajustes, Render-SettingsUI

**Setting persistido**
- `$script:settings.GameAffinityEnabled` (bool, default `$false`)
- Cargado en `Load-Settings`, reseteado a `$false` en el bloque de reset

**`Get-PhysicalCoreMask`** (nueva funcion, modulo 9B)
- Lee `Win32_Processor`: NumberOfCores (fisicos) y NumberOfLogicalProcessors
- Si `logical <= physical`: retorna -1 (sin SMT/HT, sin efecto util)
- Si SMT activo: mascara = `2^N - 1` (primeros N bits, donde N = nucleos fisicos)
- Ejemplo: 6C/12T → mascara 0x3F; 8C/16T → mascara 0xFF

**`Apply-GameFocusMode` modificado**
- `$script:gameFocusState` ahora incluye `PreviousAffinity = -1`
- Si `GameAffinityEnabled` y `Get-PhysicalCoreMask > 0`: guarda `ProcessorAffinity` actual y aplica la mascara fisica
- Si sin SMT o opcion desactivada: comportamiento previo sin cambio de afinidad

**`Restore-GameFocusMode` modificado**
- Si `PreviousAffinity >= 0`: restaura `ProcessorAffinity` del proceso (si aun corre)
- Mensaje de log actualizado: "prioridad, notificaciones y afinidad CPU restauradas"

**Card UI en tab Ajustes** (construida dinamicamente en `Add_ContentRendered`)
- Seccion "GAME FOCUS MODE" con borde verde (`#22C55E`), acento neutro
- CheckBox `$script:chkGameAffinity` — guarda a settings y llama `Save-Settings` en `Add_Click`
- Texto informativo detecta la CPU en tiempo real: muestra nucleos fisicos/logicos y la mascara que se aplicaria
- Si la CPU no tiene SMT/HT: checkbox deshabilitado con mensaje explicativo
- Insertado en posicion 0 o 1 del StackPanel de Ajustes (despues del card Tecnico si aplica)
- `Render-SettingsUI` actualiza el estado del checkbox al cargar o resetear settings

---

## F2.19 — Limpieza del Driver Store

**Archivo modificado**
- `OptimizarPC_App.ps1` — Card 5 dentro de `Build-TuningTab` (tab Tuning Avanzado, indice 9)

**Flujo de uso**
1. **Escanear drivers** — corre `pnputil /enum-drivers` via `Start-Job` + `DispatcherTimer` (no bloquea UI). Parsea la salida y agrupa por `OriginalName`; solo muestra paquetes con versiones mas nuevas presentes (verdaderos duplicados obsoletos).
2. **Exportar backup** — llama `Export-WindowsDriver -Online -Destination <BACKUP_ROOT>\DriverStore_<timestamp>`. Habilita el boton de eliminacion una vez completado.
3. **Eliminar seleccionados** — requiere backup previo. Llama `pnputil /delete-driver <oem.inf> /uninstall` por cada item marcado. Informa cuantos se eliminaron y cuantos fallaron.

**Funciones internas (definidas dentro de `Build-TuningTab`)**
- `Parse-PnpUtilOutput` — parsea la salida de texto de pnputil en objetos PS con PublishedName, OriginalName, ProviderName, DriverVersion, DriverDate, SignerName
- `Get-ObsoleteDriverPackages` — agrupa por OriginalName, descarta los unicos, retorna solo los de version menor dentro de cada grupo (los mas nuevos se conservan)

**Seguridad**
- Backup obligatorio antes de habilitar eliminacion (`$script:driverBackupDone` flag)
- `pnputil /delete-driver /uninstall` rechaza drivers en uso — el error se captura y se loguea sin crashear
- El flag de backup se resetea despues de cada eliminacion (para forzar nuevo backup si se vuelve a escanear)

---

## F2.18 — Tab Tuning Avanzado

**Archivos modificados**
- `OptimizarPC_App.ps1` — funciones helper, `Build-TuningTab`, modificacion de `Set-ActiveNav`, llamada en `Add_ContentRendered`

**Tab agregada dinamicamente (sin modificar XAML)**
- `Build-TuningTab` crea un `TabItem` con `Visibility = Collapsed` (oculto de la barra de tabs) y lo agrega a `$mainTabs.Items` en el indice 9
- Nav button `$script:navTuning` (icono ⚡ U+26A1) agregado al StackPanel de la barra lateral via `$navAjustes.Parent.Children.Add()`
- `Set-ActiveNav` extendido: detecta index 9 y aplica `BtnNavActive` / `BtnNav` a `$script:navTuning` (mismo patron que navLicencia, fuera del loop de `$script:navButtons`)

**Card 1 — Scheduler de CPU (Win32PrioritySeparation)**
- 3 opciones en ComboBox: default (0x26=38), consistencia (0x16=22), responsividad (0x24=36)
- Solo valores honestos per auditoria Fable: sin el folklore de 0x26 "disfrazado de gaming" ni 0x28 con efecto placebo
- Descripcion actualizada al cambiar seleccion; status muestra valor hex+decimal actual y post-aplicacion
- Nota de honestidad: "el efecto medible es minimo en hardware moderno"
- `Set-Win32PrioritySep` usa `Save-RegBackup` + `Set-Reg` para backup automatico

**Card 2 — HAGS (Hardware-Accelerated GPU Scheduling)**
- Lee `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode` (2=activo, 1=inactivo)
- Botones Activar/Desactivar actualizan el estado visualmente y registran el cambio
- Alerta de reinicio requerido post-cambio
- `Set-HagsState` usa `Save-RegBackup` + `Set-Reg`

**Card 3 — Politica Termica (Cooling Policy)**
- Lee el indice AC via `powercfg /query SCHEME_CURRENT <subgroup-guid> <setting-guid>`
- Botones Activa / Pasiva: llaman `powercfg /setacvalueindex` + `/setdcvalueindex` + `/setactive`
- Subgroup GUID: `54533251-82be-4824-96c1-47b60b740d00` | Setting GUID: `94d3a615-a899-4ac5-ae2b-e4d8f634367f`
- Manejo de error si el plan personalizado no expone el setting

**Card 4 — Informacion de Componentes**
- CPU: nucleos fisicos, hilos logicos, cache L3 en MB
- RAM: velocidad en MHz, slots usados / total
- GPU: nombre, VRAM en MB/GB, version de driver
- HAGS: estado actual (repetido aqui para referencia rapida)
- Todos via `Get-CimInstance` (Win32_Processor, Win32_PhysicalMemory, Win32_PhysicalMemoryArray, Win32_VideoController)

---

## F2.17 — Detector de optimizadores previos

**Archivo modificado**
- `OptimizarPC_App.ps1` — 2 funciones nuevas + llamada en `Add_ContentRendered`

**`Get-PreviousOptimizers`**
- Escanea 3 paths de registro de desinstalacion (HKLM 64-bit, HKLM 32-bit, HKCU)
- Lista de 15 patrones conocidos: CCleaner, IObit, Advanced SystemCare, Wise (3 variantes), AVG TuneUp (2 variantes), PC SpeedUp, SlimCleaner, Glary Utilities, Auslogics, RegClean Pro, System Mechanic, CleanMyPC
- Retorna `List[string]` con nombres canonicos, sin duplicados

**`Show-OptimizerBanner`**
- Solo se ejecuta si `Get-PreviousOptimizers` retorna al menos 1 elemento
- Construye un `Border` de aviso amarillo (`#F59E0B` / fondo `#1C1400`) e inserta en posicion 0 del StackPanel del tab Optimizar
- Icono Unicode `⚠` (U+26A0) + titulo + lista de apps + descripcion explicativa
- Boton X (U+2715) para descartar: colapsa el banner con `Visibility = Collapsed`
- No bloquea la UI: llamado via `BeginInvoke` con prioridad `ApplicationIdle`
- Logea en consola: "F2.17: N optimizador(es) de terceros detectados: ..."

**Comportamiento**
- No desinstala nada — solo informativo
- No persiste el descarte (reaparece en cada inicio si la app sigue instalada)
- Sin errores si el escaneo falla (try/catch completo)

---

## F2.16 — Licencia Tecnico multi-PC

**Archivo modificado**
- `OptimizarPC_App.ps1` — nuevas vars, funciones, handlers actualizados, campo en Ajustes

**Nuevo tier: Tecnico**
- Precio objetivo: $45 USD (Pro + CLI + multi-PC)
- Clave con prefijo `TECH-XXXX-XXXX-XXXX-XXXX` (16 hex chars en 4 grupos)
- NO atada a hardware — misma clave valida en cualquier equipo
- Almacenada en `%USERPROFILE%\.OptimizarPC\tech_license.key` (separada de `license.key`)

**Funciones nuevas**
- `Get-ExpectedTechKey`: SHA256 de `$script:TECH_LICENSE_SALT` (solo salt, sin HardwareID); retorna primeros 16 hex chars en formato `XXXX-XXXX-XXXX-XXXX`
- `Test-TechLicenseKey`: valida formato regex + compara con `Get-ExpectedTechKey`

**`Get-LicenseStatus` actualizada**
- Retorna `Tier` en el PSCustomObject (`"free"` / `"pro"` / `"tech"`)
- Chequea Tech primero (mas permisivo), luego Pro (hardware-bound)
- `$script:IS_TECH = ($script:_initLic.Tier -eq "tech")`

**`Update-LicenseBadge` actualizada**
- Muestra `"WinBoost TECNICO activado — multi-PC"` con badge Pro cuando `$script:IS_TECH`

**`$btnActivateLicense.Add_Click` actualizado**
- Detecta prefijo `TECH-` y desvía al flujo Tech
- Valida, guarda en `tech_license.key`, activa `$script:IS_TECH`, muestra `$script:techNameRow`

**`Build-HTMLReport` actualizado**
- Si `$script:IS_TECH` y `TechnicianName` no está vacío, inserta fila "Tecnico: [nombre]" en la sección "Informacion del sistema" del HTML

**`$script:settings.TechnicianName`**
- Nuevo campo en defaults, Load-Settings y Reset block
- TextBox en tab Ajustes (card "PERFIL DE TECNICO"), botón "Guardar" llama a `Save-Settings`
- Sección visible solo cuando `$script:IS_TECH` (`Visibility = Collapsed` por defecto)

---

## F2.15 — Modo silencioso / CLI

**Archivo modificado**
- `OptimizarPC_App.ps1` — bloque `param()` al inicio + funcion `Invoke-SilentMode` + bifurcacion al final

**Uso**
```
powershell -ExecutionPolicy Bypass -File OptimizarPC_App.ps1 -Silent [-Preset Safe|Gaming|Prod]
```
O desde el exe compilado:
```
WinBoost.exe -Silent -Preset Gaming
```

**Mecanismo**

`param([switch]$Silent, [string]$Preset = "Safe")` en la primera linea del script (antes de `#Requires`).

Al final del script, bifurcacion:
```
if($Silent){ Invoke-SilentMode -SilentPreset $Preset }
else { Load-Settings; Show-SplashScreen; $window.ShowDialog() }
```

**`Invoke-SilentMode`** (definida antes del bloque final):
- Crea `%USERPROFILE%\.OptimizarPC\logs\silent_YYYYMMDD_HHmmss.log`
- Redefine `script:Write-Log`, `script:Set-Progress`, `script:Flush-UI` con scope qualifier `script:` para que las funciones `Invoke-*Tweaks` (que buscan `Write-Log` en el scope chain) usen la version de log a archivo en lugar de la de WPF
- Selecciona el preset via los hashtables ya existentes (`$presetGaming`, `$presetSafe`, `$presetProd`)
- Ejecuta la misma secuencia que el modo UI: Restore Point, CleanupTweaks, RegistryTweaks, NetworkTweaks, ServiceTweaks, FastStartup, PageFile
- **TRIM sincrono**: en modo silencioso no hay DispatcherTimer disponible (sin message loop WPF), por lo que `Optimize-Volume` se llama directamente (bloqueante) en lugar de via Start-Job + timer
- Backup functions (`Save-RegBackup`, `Save-SvcBackup`, `Save-PageFileBackup`, `Save-NetBackup`) retornan early por `$script:activeSession = $null` — no se aplican backups en modo silencioso (comportamiento intencionado: el tecnico debe gestionar backups)
- Toast via `System.Windows.Forms.NotifyIcon.ShowBalloonTip(8000)` — funciona sin window WPF ni modulos externos
- `exit 0` si ok, `exit 1` si error critico

**Presets disponibles**
- `Safe` (default): limpieza + DNS, sin tweaks agresivos
- `Gaming`: todos los tweaks incluyendo servicios, GPU priority, HPET, Nagle
- `Prod`: limpieza + DNS + telemetria, sin tweaks de latencia

---

## F2.14 — Analisis de espacio en disco

**Archivo modificado**
- `OptimizarPC_App.ps1` — 2 bloques: init de vars + bloque en `Add_ContentRendered`

**Componentes**

**Card construida dinamicamente en PS1** (sin modificar XAML):
- En `Add_ContentRendered`, se navega al Grid de la tab Herramientas via `$mainTabs.Items[3].Content.Content`
- Se agrega un `RowDefinition Height="Auto"` al Grid y se construye toda la card como jerarquia WPF en PS
- Accent strip color `#F97316` (naranja, distinto de las otras cards)
- Variables `$script:btnDiskSpace`, `$script:lblDiskSpaceStatus`, `$script:icDiskFolders` al nivel de script para acceso desde closures

**Escaneo async via Start-Job + DispatcherTimer** (mismo patron que TRIM):
- Click: deshabilita boton, inicia `Start-Job` que enumera directorios de `$SYSDRIVE`
- El job usa `[System.IO.Directory]::EnumerateFiles` con `SearchOption.AllDirectories` para mayor velocidad que `Get-ChildItem -Recurse`
- Exclusiones: `Windows\WinSxS`, `Windows\Installer`, `System Volume Information`, `$Recycle.Bin`; toda `C:\Windows` es omitida (el usuario no puede limpiarla)
- Timer de 3s polla el job; muestra contador "Escaneando... Xs" mientras corre
- Al terminar: popula `$script:icDiskFolders` con las 10 carpetas mas pesadas

**Visualizacion de resultados**:
- Cada fila: nombre de carpeta + tamano en GB/MB (derecha) + barra proporcional de 4px de alto
- Barra proporcional via Grid con columnas `Star`: carpeta mas grande = 100%, resto proporcional
- Paleta de 10 colores degradando de rojo (mayor) a azul (menor)
- Footer: "N carpetas | X GB escaneados"

---

## F2.13 — Modo solo lectura / Analisis del sistema

**Archivo modificado**
- `OptimizarPC_App.ps1` — 2 bloques nuevos

**Componentes**

**`Show-AnalysisReport`** — funcion definida en la seccion `# ANALISIS` (entre `Show-ConfirmDialog` y `# EJECUTAR`):
- Deshabilita el boton mientras analiza, llama `Get-SystemScore`, rehabilita al terminar
- Calcula `$failing` = items donde `Ok = $false`, `$potGain` (suma de pesos), `$newScore` (score potencial exacto)
- Abre un `Window` WPF construido via here-string + `XamlReader::Load`:
  - Header: score actual con color segun umbral (`#22C55E` >= 75 / `#F59E0B` >= 45 / `#EF4444` < 45)
  - Hero card derecha: "+N pts potencial" y score potencial
  - Lista scrollable (`ItemsControl icAnalysis`): items fallidos agrupados por categoria con header de color y badge amarillo "+N pts" por item
  - Footer: nota informativa + botones "Cerrar" / "Seleccionar recomendadas (N)"
- "Seleccionar recomendadas": itera `$capturedFailing`, setea `$checks[$fi.Id].IsChecked = $true` para cada item, cierra el dialog, navega a tab 0, muestra log informativo
- Si no hay mejoras: badge deshabilitado, mensaje "Todo optimizado"

**`$btnAnalyze`** — boton creado dinamicamente en PS1 (sin tocar XAML):
- `New-Object Windows.Controls.Button`, estilo `BtnSec`, insertado antes de `$btnSelAll` en el footer StackPanel via `($btnSelAll.Parent).Children.Insert(...)`
- Click handler: `Show-AnalysisReport`
- Orden resultante en footer: Analizar | Sel. todo | Desel. | Detener | Optimizar

**Categorias de color en la lista**
- Rendimiento: `#00C8FF` | Privacidad: `#A855F7` | Red: `#22C55E` | Servicios: `#F59E0B`

---

## F2.12 — Boton Detener para cancelar optimizacion en curso [AUDIT U2]

**Archivo modificado**
- `OptimizarPC_App.ps1` — 8 cambios

**Mecanismo**
- `$script:_cancelOptimize = $false` — flag de cancelacion inicializado junto a los otros `$script:_opt*`
- Boton `$btnCancelOpt` creado **dinamicamente en PS1** (sin tocar XAML): `New-Object Windows.Controls.Button`,
  estilo `BtnDanger`, insertado en el StackPanel del footer inmediatamente antes de `$btnRun` via
  `($btnRun.Parent).Children.Insert(...)`.
- Click handler: setea `$script:_cancelOptimize = $true`, deshabilita el boton, muestra "Deteniendo...",
  llama `Write-Log` + `Flush-UI`. La cancelacion no es inmediata — el sistema termina la fase actual.

**Flujo de optimizacion (checkpoints)**
El flag se chequea entre cada fase principal (sin interrumpir dentro de una fase):
1. Despues de `Invoke-CleanupTweaks`
2. Despues de `Invoke-RegistryTweaks`
3. Despues de `Invoke-ServiceTweaks`
4. En el `Add_Tick` del timer de TRIM async — si cancela durante TRIM, detiene el job y llama `Invoke-OptimizeFinish`

En cada checkpoint si el flag es true: `Write-Log "cancelado" "skip"` + `Invoke-OptimizeFinish -sel $sel` + `return`.

**Inicio y fin de optimizacion**
- Al iniciar (`btnRun.Add_Click` post-confirmacion): muestra `btnCancelOpt` (Visible) + resetea flag
- `Invoke-OptimizeFinish`: detecta `$wasCancelled` antes de resetear el flag; muestra "Detenido" o
  "Completado" segun corresponda en `Set-Progress` y `$lblLogStatus`; oculta `btnCancelOpt`;
  resetea `$script:_cancelOptimize = $false`

Los cambios ya aplicados al sistema antes de la cancelacion permanecen activos (el undo se hace
desde el tab Historial como con cualquier sesion completa).

---

## F2.11 — PageFile: pregunta de disco secundario movida al modal de confirmacion [AUDIT U1]

**Archivo modificado**
- `OptimizarPC_App.ps1` — 4 cambios

**Problema**
Al ejecutar la optimizacion con PageFile seleccionado y un disco secundario presente,
la app mostraba un `MessageBox YesNo` a mitad del proceso (al 91% de progreso).
Esto interrumpia el flujo de optimizacion ya en marcha y sorprendia al usuario.

**Fix**
- `Build-ActionPlan`: cuando `$sel["PageFile"]` es true, detecta el disco secundario
  con `Get-PSDrive`. Guarda la ruta en `$script:_altDriveForPageFile` y resetea
  `$script:_pageFileMoveToAlt = $false`. Actualiza el detail de la accion para mencionar
  el disco detectado si lo hay.
- `Show-ConfirmDialog`: si `$script:_altDriveForPageFile` no esta vacio, agrega al pie
  del `icPlan` un `Border` azulado con un `CheckBox` "Mover PageFile al disco secundario (X:)".
  La referencia queda en `$script:_pageFileCbx`.
- `btnConfirm.Add_Click`: antes de cerrar el dialog, lee `$script:_pageFileCbx.IsChecked`
  y guarda en `$script:_pageFileMoveToAlt`.
- Bloque PageFile en `btnRun`: elimina el `MessageBox YesNo` + deteccion de drive duplicada.
  Ahora simplemente: si `$script:_altDriveForPageFile != ""` y `$script:_pageFileMoveToAlt`,
  usa el disco secundario; de lo contrario usa `$SYSDRIVE`.

**Variables nuevas (inicializadas junto a `$script:_optApplied`)**
- `$script:_altDriveForPageFile` — ruta del disco secundario (ej. "D:"), "" si no hay
- `$script:_pageFileMoveToAlt`   — decision del usuario ($true = mover, $false = no mover)
- `$script:_pageFileCbx`         — referencia al CheckBox del modal (usado en el click handler)

---

## F2.10 — Pulidos menores: Apply-Update, labels de error, URL placeholder, .Owner [AUDIT B-varios]

**Archivo modificado**
- `OptimizarPC_App.ps1` — 7 cambios puntuales

**(a) Apply-Update: notificacion si Copy-Item falla**
El script helper `do_update.ps1` generado por `Apply-Update` tenia `catch {}` silencioso.
Si `Copy-Item` fallaba (permisos, archivo en uso), el usuario no recibia ninguna señal.
Fix: el bloque catch ahora muestra un WinForms MessageBox con el mensaje de error antes de salir con `exit 1`.

**(b) Labels UI con `"Error: $_"` crudo**
5 labels mostraban el objeto de excepcion de PowerShell directamente al usuario:
`$lblBenchStatus`, `$lblStartupStatus`, `$lblRAMFreeStatus`, `$lblBloatStatus`, `$lblProcsStatus`.
Fix: cada catch ahora hace `Write-Log "Error en <contexto>: $_" "err"` (envía al badge de errores del sidebar)
y muestra `"Error — ver consola"` en el label. El detalle tecnico queda en la consola de log, no en la UI.

**(c) URL de actualizaciones: placeholder `TU_USUARIO` reemplazado**
`$UPDATE_CHECK_URL` apuntaba a `TU_USUARIO` en lugar del repo real.
Fix: cambiado a `tDallagio` (usuario real del proyecto, consistente con `releaseUrl` en `version.json`).

**(d) .Owner en modales — ya estaba completo**
Auditoria verifico los 5 dialogos WPF con `ShowDialog`:
`Show-ErrorSummary`, `Show-ConfirmDialog`, `Show-CompareDialog`, `Show-ChangelogDialog`, `Show-OnboardingDialog`.
Todos tienen `.Owner = $window` antes de `ShowDialog` — no se requirieron cambios.

---

## F2.9 — Delayed-start correcto en backup/restore de servicios [AUDIT A2]

**Archivo modificado**
- `OptimizarPC_App.ps1` — `Save-SvcBackup` + `Restore-ServicesFromSession`

**Problema**
`Get-Service` y `Win32_Service.StartMode` reportan `"Auto"` tanto para servicios con inicio
automatico normal como para los de inicio automatico retardado (Automatic Delayed Start).
La unica fuente de verdad es `HKLM:\SYSTEM\CurrentControlSet\Services\<name>\DelayedAutoStart = 1`.
Al revertir una sesion, `Restore-ServicesFromSession` aplicaba `Set-Service -StartupType Automatic`
sin restaurar el flag de delayed-start, cambiando permanentemente el comportamiento del servicio.

**Fix**
- `Save-SvcBackup`: despues de leer `CIM.StartMode`, consulta `DelayedAutoStart` en registro.
  Si el servicio era `"Auto"` con `DelayedAutoStart=1`, guarda `startMode = "AutoDelayed"`.
- `Restore-ServicesFromSession`:
  - Agrega `"AutoDelayed" = "Automatic"` al mapa (para que `Set-Service` use el tipo correcto).
  - Tras restaurar con `Set-Service -StartupType Automatic`, si `startMode -eq "AutoDelayed"`,
    escribe `DelayedAutoStart = 1` de vuelta en el registro.
- Score checks (`$script:auditItems`): sin cambios — solo verifican `StartType -eq "Disabled"`,
  que `Get-Service` expone correctamente en todos los casos.

---

## F2.8 — Eliminar Start-Sleep 600ms de Get-HeavyProcesses [AUDIT M5]

**Archivo modificado**
- `OptimizarPC_App.ps1` — funcion Get-HeavyProcesses reescrita, 2 vars nuevas

**Problema**
`Get-HeavyProcesses` calculaba CPU% con la tecnica "dos muestras + pausa":
1. Snapshot de TotalProcessorTime
2. `Start-Sleep -Milliseconds 600` — bloqueaba el hilo UI durante 600ms en cada refresh
3. Segunda snapshot + delta

Con auto-refresh activo (intervalo 3s) el hilo UI se congelaba 600ms de cada 3 segundos. Visible como lag en la UI al cambiar tabs o mover la ventana.

**Fix: muestra cacheada entre llamadas**
- `$script:_procSample1` y `$script:_procSampleTime1`: guardan la snapshot del tick anterior
- En cada llamada a `Get-HeavyProcesses`: snapshot actual + delta contra el cache
- Primera llamada: CPU%=0 para todos (sin baseline disponible). A partir del segundo refresh: CPU% basado en el intervalo real del timer (3s por defecto), lo cual es MAS preciso que 600ms.
- `Get-Process` llamado una sola vez por refresh (antes se llamaba dos veces)
- `Start-Sleep` eliminado completamente

**Sin Start-Job, sin threading** — todo sigue en el hilo UI, cumple el stack constraint de PS5.1.

---

## F2.7 — DisableIPv6: 0xFF → 0x20, eliminar Disable-NetAdapterBinding [AUDIT M3]

**Archivos modificados**
- `OptimizarPC_App.ps1` — bloque DisableIPv6 en Invoke-NetworkTweaks + Build-ActionPlan
- `OptimizarPC_UI.xaml` — Content y ToolTip de chkDisableIPv6

**Problema**
`DisabledComponents=0xFF` deshabilita todos los componentes IPv6 del sistema. En redes IPv6-nativas (ISPs modernos, Teredo, servicios cloud) esto cortaba la conectividad. Adicionalmente, `Disable-NetAdapterBinding` deshabilitaba IPv6 a nivel de adaptador, lo cual es dificil de revertir para el usuario promedio.

**Fix**
- Registro: `0xFF` → `0x20` (bit 5 = "preferir IPv4 en prefijos de direcciones"). IPv6 sigue funcionando; Windows simplemente elige IPv4 cuando ambos estan disponibles.
- Eliminada la llamada a `Disable-NetAdapterBinding` — innecesaria con `0x20` y demasiado agresiva.
- `Build-ActionPlan`: label "Deshabilitar IPv6" → "Preferir IPv4 sobre IPv6", detail actualizado, impacto "high" → "low".
- XAML: Content "Deshabilitar IPv6" → "Preferir IPv4"; ToolTip explica que IPv6 sigue activo y menciona la excepcion Teredo/IPv6-only.

---

## F2.6 — Resumen post-optimizacion: cambios aplicados / condiciones no cumplidas

**Archivo modificado**
- `OptimizarPC_App.ps1` — contadores + log de resumen

**Diseño**
- `$script:_optApplied` y `$script:_optSkipped` inicializados a 0 al comenzar cada optimizacion
- Cada opcion seleccionada que se ejecuta incrementa `$script:_optApplied`
- Opciones seleccionadas pero bloqueadas por hardware (Prefetch en HDD, SvcSysMain en HDD, SvcWSearch en HDD) incrementan `$script:_optSkipped` y emiten un log "skip" explicito
- Al final de `Invoke-OptimizeFinish`: `Write-Log "RESUMEN: N cambios aplicados[, M condiciones no cumplidas]" "head"` — visible en la consola como linea destacada
- Toast notification actualizada: incluye el conteo ("23 cambios aplicados")

**Contadores por seccion**
- Cleanup: TempUser/TempSys/Prefetch/WinUpdate/Browsers/Thumb/Recycle/EventLogs (8 posibles)
- Registry: GPUPrio/PowerThrot/MouseAccel/GameDVR/GameMode/Telemetry/Cortana/Notif/Tasks (9 posibles)
- Network: Nagle/TCP/DNS/DNSFlush/DisableIPv6 (5 posibles)
- Services: SvcXbox/SvcDiag/SvcWER/SvcSysMain/SvcMaps/SvcFax/SvcWSearch (7 posibles, 2 con condicion SSD)
- Inline: Power/HPET/FastStartup/PageFile/TRIM/Visual (6 posibles)

---

## F2.5 — Refactor funciones gigantes: btnRun + Show-ConfirmDialog [AUDIT M2]

**Archivo modificado**
- `OptimizarPC_App.ps1` — 5 funciones extraidas + 1 helper

**Funciones nuevas**
- `New-ActionRow`: construye el Border de una sola accion para el modal de confirmacion. Extrae ~65 lineas del foreach de `Show-ConfirmDialog`.
- `Invoke-CleanupTweaks`: toda la limpieza de archivos (TempUser/TempSys/Prefetch/WinUpdate/Browsers/Thumb/Recycle/EventLogs).
- `Invoke-RegistryTweaks`: tweaks de registro (GPUPrio/PowerThrot/MouseAccel/GameDVR/GameMode/Telemetry/Cortana/Notif/Tasks).
- `Invoke-NetworkTweaks`: red (Nagle/TCP/DNS/DNSFlush/DisableIPv6). No-op si ninguna opcion de red esta seleccionada.
- `Invoke-ServiceTweaks`: servicios (SvcXbox/SvcDiag/SvcWER/SvcSysMain/SvcMaps/SvcFax/SvcWSearch). No-op si ninguno esta seleccionado.

**Resultado**
- `btnRun.Add_Click`: ~340 lineas → ~80 lineas (restore point + Power + HPET + 4 llamadas + FastStartup + PageFile + TRIM)
- `Show-ConfirmDialog`: ~257 lineas → ~180 lineas (foreach simplificado a llamada `New-ActionRow`)
- Las 4 funciones Invoke-* estan listas para recibir tracking de resultados en F2.6

---

## F2.4 — Fusionar handlers duplicados de SelectionChanged [AUDIT A1]

**Archivo modificado**
- `OptimizarPC_App.ps1` — handler duplicado eliminado

**Problema**
WPF acumula todos los delegates pasados a `Add_SelectionChanged`. Con dos handlers registrados, ambos ejecutaban en cada cambio de tab, duplicando trabajo innecesariamente.

**Fix**
- Handler 1 (Herramientas: proc timer + device scan) ampliado con la logica del handler 2
- Handler 2 (Info del sistema + Historial: Update-ScorePanel / Render-ScoreHistory) eliminado y reemplazado por comentario
- Handler unico resultante cubre los tres tabs con un solo `if/else` claro

---

## F2.2 — Race condition monitor timer vs Dispose [AUDIT A3]

**Archivo modificado**
- `OptimizarPC_App.ps1` — 4 cambios

**Problema**
DispatcherTimer envia su tick via `Dispatcher.BeginInvoke()`. Si el intervalo elapsa justo antes del cierre, el tick queda encolado en el Dispatcher y puede ejecutarse DESPUES de que `Dispose()` fue llamado en los PerformanceCounters. Resultado: `ObjectDisposedException` en `NextValue()` (silenciado por try/catch pero bug real).

**Fix**
- Flag `$script:shuttingDown = $false` inicializado junto al timer (~linea 2891)
- En `Add_Closing`: `$script:shuttingDown = $true` ANTES de `Stop()` (~linea 2940)
- Ambos handlers de `Add_Tick` (monitor principal y thermal) comienzan con: `if ($script:shuttingDown) { return }`

Garantiza que un tick ya encolado en el Dispatcher salga inmediatamente sin tocar counters ya liberados.

---

## F2.1 — EventLogs: advertencia proporcional + exclusion de Security log

**Archivos modificados**
- `OptimizarPC_App.ps1` — 3 cambios
- `OptimizarPC_UI.xaml` — tooltip actualizado

**Cambios**
- `Build-ActionPlan`: impacto cambiado de `"medium"` a `"high"`, descripcion explicita: "Borra logs Aplicacion/Sistema/etc. Log de Seguridad NO se toca. Elimina registros forenses."
- `btnSelAll.Add_Click`: ya no activa `chkEventLogs` — el checkbox queda en su estado previo al hacer "Seleccionar todo". Solo puede activarse manualmente.
- Ejecucion: `Get-WinEvent -ListLog * | Where-Object{ $_.LogName -ne "Security" }` — el log de Seguridad (registros de login, accesos, auditorias) queda intacto. Log del resultado actualizado a "Logs de eventos limpiados (Security excluido)".
- Tooltip en XAML: Foreground="#EF4444" (rojo), texto "IMPACTO ALTO: borra logs de Aplicacion, Sistema y otros canales. El log de Seguridad NO se toca. Elimina registros forenses del sistema. No se activa con Seleccionar todo."

---

## F1.7 / F1.8 — Drivers tab: Dispositivos con problemas + Inventario de drivers

**Archivos modificados**
- `OptimizarPC_UI.xaml` — dos nuevas secciones en tab Herramientas (Row 3 y Row 4), badge dot en navHerramientas
- `OptimizarPC_App.ps1` — modulo F1.7/F1.8 completo (~170 lineas)

**F1.7 — Dispositivos con problemas**
- `Get-ProblemDevices`: `Get-PnpDevice | Where-Object { $_.Status -ne "OK" }`, retorna array con FriendlyName/Status/ConfigManagerErrorCode
- `Render-ProblemDevices`: tabla dinamica con columnas Dispositivo / Estado / Codigo. Estado con badge coloreado (#EF4444 Error, #F59E0B resto). Empty state si no hay problemas
- `Scan-DeviceProblems`: deshabilita boton durante escaneo, actualiza status label
- `Update-DeviceBadge`: muestra/oculta dot badge amarillo `#F59E0B` en `navHerramientas` si hay dispositivos con problemas
- Badge dot inline en StackPanel del boton navHerramientas (Visibility=Collapsed por defecto)
- Boton "Administrador de dispositivos" lanza `devmgmt.msc`
- El escaneo se dispara automaticamente al entrar al tab Herramientas por primera vez (via `$script:devicesScanned` flag en SelectionChanged)

**F1.8 — Inventario de drivers**
- `Get-DriverInventory` (inline en Scan-DriverInventory): `Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -ne $null }`, ordenado por DeviceName
- `Render-DriverInventory`: tabla con columnas Dispositivo / Version / Fecha / Firmado. Filas con fondo `#1A0000` si IsSigned=$false, `#1A1000` si DriverDate > 2 anos, transparente si OK. "Si"/"No" con colores #22C55E/#EF4444
- `Populate-DriverClassFilter`: llena cboDriverClass con clases unicas y lo habilita tras el scan
- `Scan-DriverInventory`: escaneo manual; cachea resultado en `$script:_driverList`
- `cboDriverClass.Add_SelectionChanged`: filtra desde el cache sin re-consultar CIM
- Estado inicial: empty state "Haz clic en Escanear drivers" (sin auto-scan — spec F1.8)
- ComboBox deshabilitado hasta primer scan; se habilita en `Populate-DriverClassFilter`

**Variables globales nuevas**
- `$script:_driverList` — cache de Win32_PnPSignedDriver
- `$script:devicesScanned` — flag de primer escaneo de dispositivos

---

## F1.6 — Icono WinBoost.ico (16/32/48/256 px)

**Archivos creados**
- `WinBoost.ico` — icono multi-resolución en la raíz del proyecto (5.5 KB).
- `Create-Icon.ps1` — script que genera el .ico; permite regenerarlo si se cambia el diseño.

**Diseño**
- Fondo: cuadrado redondeado (radius ~18%) en `#0D0D0D`, esquinas transparentes.
- Símbolo: rayo (polígono de 6 vértices) en `#00C8FF` (acento WinBoost).
- Anti-aliasing + InterpolationMode HighQualityBicubic en todas las resoluciones.

**Formato ICO**
- Container ICO manual (BinaryWriter): ICONDIR (6 bytes) + 4×ICONDIRENTRY (16 bytes cada uno) + 4 chunks PNG.
- PNG dentro del ICO (formato Vista+): compatible con Windows 10/11 en todas las superficies (taskbar, file explorer, título, ALT+TAB).
- El `Build.ps1` ya detecta `WinBoost.ico` vía `if (Test-Path $ICO)` y lo pasa a ps2exe como parámetro `iconFile`.

**Verificación**
- Header binario: `00 00 01 00 04 00` (reserved=0, type=ICO, count=4). Correcto.

---

## Bugfix — Pipeline Pollution PS5.1 en New-Brush (crash #FF1A1A1A)

**Sintoma**
- `InvalidOperationException: '#FF1A1A1A' no es un valor valido para la propiedad 'Background'`
  lanzado durante `$window.ShowDialog()` al pasar el mouse sobre cualquier elemento con ToolTip.

**Causa raiz**
En PS5.1, la linea `$b.Color = [Windows.Media.ColorConverter]::ConvertFromString($hex)` dentro
de `New-Brush` causaba "pipeline pollution": el `Color` struct retornado por el metodo estatico
escapaba al pipeline de salida de la funcion en lugar de ser consumido silenciosamente por la
asignacion de propiedad WPF. Resultado: `New-Brush "#1A1A1A"` retornaba el array
`@(Color{#FF1A1A1A}, SolidColorBrush)` en lugar de solo el brush.

Al hacer `$window.Resources["BrushElev"] = New-Brush "#1A1A1A"`, el ResourceDictionary
almacenaba ese array. Cuando el DispatcherTimer del servicio de ToolTips se disparaba y WPF
evaluaba `{DynamicResource BrushElev}` para la propiedad `Background` del ToolTip, obtenia el
`Color` struct, llamaba `.ToString()` obteniendo `"#FF1A1A1A"` e intentaba asignarlo como
`Brush` — crash.

Stack trace clave:
```
DispatcherTimer.FireTick
→ PopupControlService.ShowToolTip
→ ToolTip.OnIsOpenChanged / Popup.CreateWindow
→ TreeWalkHelper.InvalidateResourceReferences
→ ResourceReferenceExpression.InvalidateExpressionValue
→ DependencyObject.EvaluateExpression → InvalidOperationException
```

**Solucion**
Reemplazado `ColorConverter` + asignacion de propiedad `.Color` por `BrushConverter.ConvertFromString`,
que construye el `SolidColorBrush` internamente sin exponer el `Color` struct al pipeline:

```powershell
# ANTES (buggy — pipeline pollution)
$b = New-Object Windows.Media.SolidColorBrush
$b.Color = [Windows.Media.ColorConverter]::ConvertFromString($hex)
$b.Freeze()
return $b

# DESPUES (correcto)
$conv = New-Object Windows.Media.BrushConverter
$b    = $conv.ConvertFromString($hex)
[void]$b.Freeze()
return $b
```

**Regla derivada**
En PS5.1, nunca usar `$obj.DependencyProp = [Class]::StaticMethod(args)` dentro de funciones
que retornan valores. Usar variable intermedia: `$val = [Class]::StaticMethod($args)` y luego
`[void]$obj.SetValue($dp, $val)`. Ver regla en CLAUDE.md seccion NUNCA.

---

## v4.2 — F1.5: Eliminacion de tweaks placebo

**F1.5 — Win32PrioritySeparation y DisablePagingExecutive eliminados**

Eliminados dos tweaks sin evidencia de beneficio real que los reviewers tecnicos usan para desacreditar optimizadores:

- **`chkScheduler` / `Win32PrioritySeparation=26`**: empeora la responsividad del escritorio; el valor default del sistema (2) ya esta afinado por Microsoft para workstations. Eliminado de XAML, `$checks`, `$script:auditItems` (Weight=4), `$presetGaming`, `Build-ActionPlan` y `btnRun`.

- **`chkMemory` / `LargeSystemCache=0` + `DisablePagingExecutive=1`**: `LargeSystemCache=0` es el valor default en workstations (no cambia nada); `DisablePagingExecutive=1` es contraproducente en sistemas con poca RAM (fuerza codigo del kernel a RAM fisica). Eliminado de XAML, `$checks`, `$script:auditItems` (Weight=4), los tres presets, `Build-ActionPlan` y `btnRun`.

Impacto en score: la categoria Rendimiento pasa de 34 pts a 26 pts. El total del sistema queda en 92 pts maximos; `Get-SystemScore` lo normaliza dinamicamente con `$maxPoints = auditItems.Weight.Sum`, por lo que el score 0-100 sigue siendo valido y honesto. Comentario de categoria actualizado de "(34 pts)" a "(26 pts)".

---

## v4.2 — F1.4: Auditoria New-Brush (ya completa)

**F1.4 — ColorConverter reemplazado por New-Brush — verificado completo**
- Auditoria exhaustiva del PS1: 0 instancias de `New-Object Windows.Media.SolidColorBrush`, 0 instancias de `ColorConverter::ConvertFromString` fuera de la propia funcion `New-Brush`
- 110 llamadas a `New-Brush` + tablas de brushes pre-congelados (`$brMon`, `$brProc`, `$script:brMaint*`, `$script:brLic*`) cubren el 100% de las asignaciones de color en codigo PS
- El refactor del crash #FF1A1A1A (jun 2026) ya habia migrado todos los usos directos; el conteo ~157 de la auditoria correspondia a una version anterior del archivo
- `$window.Resources[$key] = New-Brush $palette[$key]` en `Apply-Theme` sigue el patron correcto

---

## v4.2 — F1.3-fix: Write-Log de timeout en winget

**F1.3-fix — Log visible cuando Get-WingetInstalledMap alcanza el timeout**
- En el bloque `if(-not $completed)` de `Get-WingetInstalledMap`, antes del `return $map`, agregada la linea: `Write-Log "winget: timeout de 8s, continuando sin datos de winget" "info"`
- El timeout ya funcionaba correctamente (Stop-Job + Remove-Job + return mapa vacio); ahora queda trazable en la consola de log en lugar de silencioso

---

## v4.2 — F0.12 + F0.11 + F0.10: Bugs criticos cerrados — FASE 0 COMPLETA

**F0.12 — TRIM y Checkpoint no bloquean la UI**

- `Checkpoint-Computer`: mensaje de progreso actualizado a "Creando punto de restauracion (puede tardar 30-60 s)..." para que el usuario sepa que la UI puede parecer congelada brevemente — es la unica llamada bloqueante que no es asincronizable de forma segura
- `Optimize-Volume -ReTrim`: extraido del hilo UI a un `Start-Job` background; el job recibe la lista de letras de unidad SSD como argumento serializable y retorna objetos `@{DriveLetter; OK}` por cada volumen
- `$script:trimTimer` (`DispatcherTimer` de 1 s): pollea el estado del job; mientras corre muestra "TRIM en progreso... N s" en la barra de progreso; al terminar: detiene el timer, loggea resultados via `Receive-Job`, elimina el job y llama `Invoke-OptimizeFinish`
- `Invoke-OptimizeFinish`: nueva funcion en scope de script que encapsula el tramo final de la optimizacion (efectos visuales, Set-Progress 100, habilitacion de botones, score, snapshot, modal comparativa y toast). Llamada de dos formas: por el timer tick cuando TRIM termina async (ruta SSD), o directo al final del handler cuando no hay TRIM async (ruta HDD, SSD sin volumenes, o TrimDesfrag no seleccionado)
- `$window.Add_Closing` extendido: `$script:trimTimer.Stop()` agregado para no dejar el timer activo si el usuario cierra la app durante el TRIM — el job queda huerfano pero `Get-Job | Remove-Job -Force` ya existia para limpiarlo
- Variables `$script:trimJob`, `$script:trimTimer`, `$script:trimSel`, `$script:trimJobStart` inicializadas antes del handler

---

## v4.2 — F0.11 + F0.10: Bugs criticos de seguridad

**F0.11 — Stop-Process explorer con reinicio garantizado**
- Bloque de limpieza Explorer en `btnDeepClean` convertido de `try/catch` a `try/catch/finally`
- `Start-Process explorer` movido al bloque `finally` con guard `if(-not (Get-Process explorer -EA SilentlyContinue))`: el finally corre incluso ante excepcion no capturada (ThreadAbort si el usuario cierra la app durante el sleep de 1.5s), garantizando que el escritorio nunca queda sin barra de tareas
- Guard identico agregado al `$window.Add_Closing` principal como segunda linea de defensa: si el proceso de WinBoost cierra antes de que el finally pueda ejecutar, el evento Closing reinicia Explorer si no esta corriendo

---

## v4.2 — F0.10: Cerrar 4 brechas criticas de undo (PageFile, Plan de energia, Nagle, TCP global)

**F0.10(a) — Backup y restore de PageFile**
- Nueva funcion `Save-PageFileBackup`: captura `Win32_ComputerSystem.AutomaticManagedPagefile` + todos los `Win32_PageFileSetting` (Name/InitialSize/MaximumSize) en `pagefile_backup.json` dentro de la sesion activa; registra accion `type="pagefile"` en `$script:sessionActions`
- Nueva funcion `Restore-PageFileFromSession`: si `AutomaticManaged` era true, re-activa la gestion automatica; si era false, recrea los pagefiles originales
- `Save-PageFileBackup` llamado al inicio del bloque `$sel["PageFile"]` ANTES de cualquier modificacion
- Orden destructivo invertido: ahora se crea el nuevo PageFile primero, se verifica con `Get-CimInstance Win32_PageFileSetting`, y solo si la verificacion pasa se eliminan los anteriores
- Rollback en el `catch`: si algo falla, `Set-CimInstance @{AutomaticManagedPagefile=$true}` garantiza que el sistema nunca queda sin pagefile
- Calculo de tamano mejorado: `$pfMin = Max(4096, Min(RAM_MB, 8192))`, `$pfMax = Max(8192, Min(RAM_MB*2, 16384))`

**F0.10(b) — Backup y restore exacto del plan de energia**
- Nueva funcion `Save-PowerPlanBackup`: captura el GUID del plan activo via `powercfg /getactivescheme` y el estado de hibernacion via `HibernateEnabled` en registro; guarda como accion `type="powerplan"` con campos `prevGUID` y `prevHibernate`
- `Save-PowerPlanBackup` llamado al inicio del bloque `$sel["Power"]` antes de cambiar el plan
- `Restore-Session` actualizado: busca por `type="powerplan"` (antes buscaba por label), restaura el GUID exacto guardado (no Balanced hardcodeado), y si `prevHibernate=true` ejecuta `powercfg /hibernate on`

**F0.10(c) — Nagle enrutado por Set-Reg (backup automatico)**
- Bloque Nagle reescrito: reemplaza `Set-ItemProperty` por `Set-Reg $_.PSPath "TcpAckFrequency" DWord 1` y `Set-Reg $_.PSPath "TCPNoDelay" DWord 1`
- `Set-Reg` llama `Save-RegBackup` internamente, lo que activa el respaldo de cada clave de interfaz automaticamente — el undo de Nagle ahora funciona sin codigo adicional
- Contador renombrado a `$nagleCount` para evitar colision con el parametro `$n` de `Set-Reg`

**F0.10(d) — Backup y restore de TCP global (netsh)**
- Nueva funcion `Save-NetshBackup`: ejecuta `netsh int tcp show global`, guarda la salida en `netsh_backup.txt` dentro de la sesion activa; registra accion `type="netsh"`
- `Save-NetshBackup` llamado en la seccion de red cuando `$sel["TCP"]` es true, antes de los comandos `netsh int tcp set global`
- Nueva funcion `Restore-NetshFromSession`: parsea `netsh_backup.txt` con regex para extraer autotuninglevel, chimney, rss y fastopen; los restaura via `netsh int tcp set global`
- `Restore-Session` actualizado: busca acciones `type="pagefile"` y `type="netsh"` y llama a las nuevas funciones de restore (bloques 6 y 7 del orquestador)

---

## v4.1 — Fase 0: Prerequisitos para lanzamiento

**F0.1 — Windows Restore Point incondicional**
- `Checkpoint-Computer -Description "WinBoost pre-optimizacion"` se ejecuta siempre al inicio de `btnRun_Click`, antes de cualquier cambio al sistema
- `Enable-ComputerRestore` llamado previamente para asegurar que la proteccion del sistema esta activa en `$SYSDRIVE`
- Envuelto en try/catch: si falla (sistema con restauracion deshabilitada), loggea con tipo `skip` y continua sin bloquear
- Eliminado el bloque condicional `if($sel["Startup"])` (el restore point ya no depende del checkbox)
- Footer de `Show-ConfirmDialog` actualizado: "Se creara un Punto de Restauracion de Windows antes de aplicar los cambios."

**F0.2 — Trial de 14 dias**
- `$script:settings` ampliado con `TrialStartDate` (string ISO) y `TrialExpired` (bool), persistidos en `settings.json`
- `Test-TrialStatus`: evalua estado del trial al arrancar; si `TrialStartDate` vacio inicia trial guardando fecha actual; si han pasado >14 dias setea `TrialExpired=$true`; mientras trial activo setea `$script:IS_PRO=$true` y `$script:IS_TRIAL=$true` con dias restantes en `$script:TRIAL_DAYS_LEFT`; maneja fecha corrupta reiniciando el trial
- `Update-TrialBanner`: muestra banner ambar en footer de tab Optimizar durante trial activo (X dias restantes), banner rojo al vencer, colapsado si licencia Pro real activa
- `Update-LicenseBadge` ampliado: tres estados — Pro real, trial activo (muestra "TRIAL Xd"), Free/expirado
- `Lock-ProFeature` actualizado: cuando el trial ha vencido muestra mensaje "periodo de prueba ha vencido" en lugar del generico
- Boton `btnTrialUpgrade` en el banner navega al tab Licencia (index 8)
- `bannerTrial` agregado al footer de tab Optimizar en XAML (sobre la fila de botones existente), estilo ambar/rojo segun estado
- `Test-TrialStatus`, `Update-TrialBanner`, `Update-LicenseBadge` llamados en `Add_ContentRendered` tras `Load-Settings`/`Apply-Settings`

**F0.3 — Metricas externas verificables**
- `Get-BootTimeSec`: lee Event ID 100 del log `Microsoft-Windows-Diagnostics-Performance/Operational`, devuelve tiempo de arranque en segundos; retorna -1 si el log no esta disponible
- `Get-IdleRAMMB`: RAM libre en MB via `Win32_OperatingSystem.FreePhysicalMemory`
- `Get-ProcessCount`: conteo de `Get-Process`
- `Get-SystemSnapshot` ampliado: nuevo campo `BootTimeSec` en el objeto devuelto; `ProcCount` y `RAMFreeMB` ahora delegados a las funciones standalone
- `Compare-Snapshots` ampliado: nueva fila "Tiempo de arranque (s)" (HigherBetter=$false)
- `Build-HTMLReport` ampliado: nueva seccion "Metricas medibles" con tabla de 4 columnas (Metrica/Antes/Despues/Delta) para Tiempo de arranque, RAM disponible en reposo y Procesos activos; nota al pie sobre reboot para ver mejora de arranque; delta con clases CSS `delta-pos`/`delta-neg`/`delta-neu`

**F0.4 — Audit de memory leaks**
- `$window.Add_Closing` principal ampliado: ahora detiene `$script:gamingTimer` y `$script:applyTimer` ademas de `monitorTimer` y `procTimer`
- Agrega `Get-Job | Remove-Job -Force` para cancelar cualquier `Start-Job` pendiente al cerrar
- `Stop-ProcTimer` ya reseteaba `$script:procTimerRunning = $false` — confirmado correcto
- Todos los recursos de `PerformanceCounter` (`$script:pcCPU`, `$script:pcRAMFree`, `$script:pcDisk`) se liberan con `.Dispose()` en el mismo handler

**F0.5 — Auto-refresh de procesos: default OFF**
- Al entrar al tab Herramientas ya no se llama `Start-ProcTimer` automaticamente; solo se ejecuta `Refresh-ProcessList` (un fetch unico, sin timer)
- `$script:procTimerRunning` arranca en `$false` — el usuario activa el timer manualmente con el boton
- `Start-ProcTimer`: color del boton cambiado a `#00C8FF` (acento) en lugar de `#22C55E`
- `Stop-ProcTimer`: etiqueta "Auto-refresh OFF" con color `#555555` — sin cambios
- Al salir del tab el timer se detiene igual que antes (si estaba activo)

**F0.6 — Fix barra de disco en Espacio en disco**
- Reemplazado el patron `add_SizeChanged` (buggy por closure) por `Grid` con dos `ColumnDefinition` de tipo `Star`
- Col0 = `GridLength($pct, Star)` con `Border` de color calculado; Col1 = `GridLength(100-$pct, Star)` transparente
- `Border` exterior con `ClipToBounds=$true` y `CornerRadius=3` para el recorte del borde redondeado
- Ambas columnas tienen minimo de 1 Star para evitar columnas de ancho cero
- El color se calcula igual que antes: `#EF4444` si >85%, `#F59E0B` si >70%, `#00C8FF` si normal

**F0.7 — Rediseno completo tab "Info del sistema" en layout 2x2**
- Tab reemplazado de `ScrollViewer > StackPanel` vertical a `Grid` de 2 columnas x 2 filas (cuadrantes) sin scroll — todo entra en pantalla
- Cuadrante 1 (col=0, row=0): "INFORMACION DEL EQUIPO" — 6 items en grid 2×3, cada item con icono Segoe MDL2 Assets (`&#xE7F4;` Sistema, `&#xE950;` Procesador, `&#xE7F8;` Graficos, `&#xE964;` Memoria, `&#xEDA2;` Almacenamiento, `&#xE782;` Windows), label SemiBold y valor con TextWrapping. Fondo `#1E1E1E` por item. Layout interno con Grid 2 columnas (icon 28px + StackPanel) para que TextWrapping funcione correctamente
- Cuadrante 2 (col=2, row=0): "SALUD DEL SISTEMA" — mismos controles `lblScorePanelValue`, `lblScorePanelLabel`, `btnRecalcScore`, barras `barCatRendimiento/Privacidad/Red/Servicios`. Titulo movido al interior del Border
- Cuadrante 3 (col=0, row=2): "MONITOR EN TIEMPO REAL" — 5 barras verticales en grid 5 columnas (CPU, RAM, Disco, CPU Temp, GPU Temp), contenedor 36x110px cada una. `pbGPUTemp` (ProgressBar) eliminado y reemplazado por `barGPUTempFill` (Border vertical igual que los demas)
- Cuadrante 4 (col=2, row=2): "ESPACIO EN DISCO" — mismo `diskPanel` ItemsControl, titulo al interior
- PS1: `$pbGPUTemp = Get-Ctrl "pbGPUTemp"` → `$barGPUTempFill = Get-Ctrl "barGPUTempFill"`
- PS1: altura de barras actualizada de 80 a 110px en `monitorTimer.Add_Tick` (CPU/RAM/Disco) y en `Update-ThermalDisplay` (CPU Temp/GPU Temp)
- PS1: seccion GPU en `Update-ThermalDisplay` actualizada a `$barGPUTempFill.Height` y `.Background` en lugar de `$pbGPUTemp.Value` y `.Foreground`

**F0.9 — Footer colapsado completamente en tabs distintos al Optimizar**
- XAML: agregado `MinHeight="0"` al `Border x:Name="footerBar"` para garantizar que `Collapsed` lo lleva a altura cero real (sin espacio residual)
- App.ps1: en `Set-ActiveNav`, linea siguiente a la de Visibility, se agrega `$footerBar.Height = if($index -eq 0){ [double]::NaN } else { 0 }` — `NaN` equivale a "Auto" en WPF, permitiendo que el border recupere su altura natural al volver al tab Optimizar
- El `RowDefinition Height="Auto"` del Row 3 ya estaba correcto

**F0.8 — Temperatura CPU/GPU: N/D silencioso en PCs sin sensores**
- `Get-CPUTemperature`: agrega propiedad `Available=$false` al objeto de resultado; se setea `$true` solo cuando al menos un zona termica devuelve datos validos; todo el bloque CIM ya estaba envuelto en try/catch + `EA SilentlyContinue`
- `Get-GPUTemperature`: agrega propiedad `Available=$false`; se setea `$true` cuando LHM u OHM devuelven un sensor GPU; eliminado el bloque "Intento 1" de GPUPerformanceCounters que no aportaba temperatura y podia generar I/O innecesario
- `Update-ThermalDisplay`: reemplaza checks `$thermal.CPU.TempC -ge 0` por `$thermal.CPU.Available -eq $true` (y equivalente para GPU) — verificacion explicita de disponibilidad de sensor; comportamiento N/D: `barCPUTempFill.Height=0`, `lblCPUTemp.Text="N/D"`, foreground gris `$script:brGray`; sin `Write-Host`, `Write-Error` ni ventanas CMD

## v4.1 — Fase 1: Para el lanzamiento

**F1.2 — Reporte HTML mejorado: seccion "Resultados medibles" destacada**
- Seccion hero "Resultados medibles" movida al primer bloque del reporte (despues del header), antes de "Informacion del sistema"
- 4 cards en grid 4 columnas con numeros grandes: Score de salud (antes/ahora + delta en pts), RAM disponible (antes/ahora + delta en MB), Procesos activos (antes/ahora + delta), Tiempo de arranque (valor actual + nota de reinicio)
- Fondo verde oscuro (`#0D1A0D`, borde `#1E3A1E`) para que el bloque sea visualmente distinguible y screenshot-friendly
- Colores de delta calculados directamente como hex: `#22C55E` (mejora), `#EF4444` (empeoramiento), `#888888` (neutro)
- Nuevas variables `$rptRAMColor`, `$rptProcColor`, `$rptDeltaColor`, `$rptRAMDeltaDisp`, `$rptProcDeltaDisp` para el hero
- Eliminadas las secciones separadas "Score de salud" y "Metricas medibles" (fusionadas en el hero)
- CSS limpiado: removidas clases `.sw`, `.sb`, `.sn`, `.ss`, `.arr`, `.delta`, `.mrow`, `.mlbl`, `.mval`, `.mdelta`, `.mnote` que ya no se usan

**F1.1 — Toast de notificacion al terminar optimizacion**
- Nueva funcion `Show-ToastNotification -Title -Message`: intenta WinRT toast via `Windows.UI.Notifications` (cargado con `[void][... ContentType=WindowsRuntime]`); si falla, fallback a `System.Windows.Forms.NotifyIcon` con `ShowBalloonTip`; ambos paths en try/catch silencioso
- Para el fallback `NotifyIcon`, un `DispatcherTimer` de 6s libera el icono con `.Dispose()` automaticamente
- Llamada en `btnRun` handler: dentro del `BeginInvoke` de recalculo de score, tras `Save-SessionMetadata`, mensaje "Optimizacion completada. Score: X/100 (+N pts)"
- Llamada en `Invoke-MaintenanceCycle`: reemplaza el bloque BurntToast anterior, mensaje "Mantenimiento completado. X MB liberados."
- Ningun caracter non-ASCII en los strings del mensaje

**F1.3 — Verificacion timeout winget (verificado + fix pendiente)**
- `Get-WingetInstalledMap` confirmado con mecanismo completo: `Start-Job` + `Wait-Job -Timeout 8` + `Stop-Job` + `Remove-Job -EA SilentlyContinue` en rama de timeout
- Devuelve hashtable vacia `@{}` (no null) tanto en timeout como en cualquier excepcion — comportamiento correcto verificado en codigo
- Pendiente: agregar `Write-Log "winget: timeout de 8s, continuando sin datos de winget" "info"` en el bloque de timeout (item F1.3-fix)

---

## v4.0 — Base y Roadmap principal

### Fase 1 — Confianza y seguridad

**Módulo 1A — Infraestructura de backup**
- `New-BackupSession` — crea carpeta `backups/<timestamp>/` por cada ejecución
- `Save-RegBackup` — exporta claves de registro a `.reg` antes de modificarlas (integrado en `Set-Reg`)
- `Save-SvcBackup` — guarda estado previo de servicios (integrado en `Disable-Svc`)
- `Save-NetBackup` — captura DNS y estado IPv6 antes de cambios de red
- `Save-SessionMetadata` — escribe `session.json` con resumen completo al finalizar
- `Get-BackupSessions` — lista sesiones guardadas ordenadas por fecha
- `Cleanup-OldBackups` — elimina sesiones más viejas de N días (configurable)

**Módulo 1B — Motor de restauración**
- `Restore-RegFromSession` — importa `.reg` con `reg.exe import`
- `Restore-ServicesFromSession` — restaura `StartupType` original de cada servicio
- `Restore-NetworkFromSession` — restaura DNS por adaptador y binding IPv6
- `Restore-HpetFromSession` — revierte cambios de `bcdedit` (timers del sistema)
- `Restore-Session` — orquesta todo el proceso de undo, acepta `$logFn` para UI en tiempo real

**Módulo 1C — UI Historial**
- Nueva pestaña "Historial" con tabla de sesiones
- `Render-HistoryItems` — construye filas dinámicas con badge de preset por color
- `Invoke-RevertSession` — confirmación + restauración con log en tiempo real
- `Write-RestoreLog` — logger dedicado con colores en `rtbRestoreLog`
- Botones: Actualizar, Abrir carpeta, Revertir última sesión, Revertir por fila

**Módulo 2 — Modal de confirmación pre-ejecución**
- `Build-ActionPlan` — analiza `$sel` y construye lista tipada de acciones con impacto
- `Show-ConfirmDialog` — ventana WPF secundaria con stats (total/alto/medio/bajo) y lista scrolleable por categoría
- Validación de selección vacía antes de mostrar el modal
- Fallback silencioso si el dialog falla por cualquier razón

**Módulo 3A — Motor de score de salud**
- 19 checks en 4 categorías: Rendimiento (34pts), Privacidad (26pts), Red (18pts), Servicios (22pts)
- `Get-SystemScore` — ejecuta todos los checks y devuelve score 0-100 + desglose
- Score capturado antes y después de cada optimización
- Integración con `Save-SessionMetadata` para historial de scores

**Módulo 3B — UI del score animada**
- Widget en el top bar con número, barra vertical y badge de delta
- `Update-ScoreWidget` — actualiza header y llama al panel de categorías
- `Update-ScorePanel` — barras por categoría (Rendimiento/Privacidad/Red/Servicios) en tab Info
- `Animate-ScoreCount` — contador animado con easing cúbico via `DispatcherTimer`
- `Animate-BarWidth` — animación de barras con `DoubleAnimation` y fallback sin animación
- `Show-ScoreDelta` — badge +N/-N junto al score tras optimizar
- Botón "Recalcular" en panel de Info del sistema

### Fase 2 — Features visibles

**Módulo 4A — Motor de detección de bloatware**
- Base de datos de 55 apps en 5 categorías: Juegos, Comunicación, Telemetría, OEM, Utilidades
- `Get-InstalledAppxMap` — carga todos los `AppxPackage` indexados por `PackageFamilyName`
- `Test-WingetAvailable` — detecta si winget está disponible
- `Get-WingetInstalledMap` — lista paquetes winget con timeout de 8 segundos via `Start-Job`
- `Get-BloatwareList` — cruza la DB contra los mapas, búsqueda por fragmento bidireccional
- `Get-BloatwareSummary` — resumen rápido para el header de la UI

**Módulo 4B — UI del detector de bloatware**
- Nueva pestaña "Bloatware" con stats (detectados/MB/seguros/precaución)
- `Render-BloatItems` — filas con badge de categoría por color, badge de método (AppX/winget), badge de riesgo
- `Start-BloatScan` — ejecuta el scan, actualiza stats, respeta filtro de categoría
- `Update-BloatStats` — conteo en tiempo real de selección y MB estimados
- ComboBox de filtro por categoría, botones seleccionar seguros/deseleccionar
- Auto-scan al abrir la app via `BeginInvoke ApplicationIdle`

**Módulo 4C — Motor de desinstalación**
- `Remove-BloatItem` — intenta AppX primero, fallback a winget con `--silent --disable-interactivity`
- `Save-BloatBackup` — guarda `bloatware_removed.json` en la sesión de backup activa
- `Invoke-RemoveBloat` — confirmación detallada separando seguros de precaución, log en consola, re-scan automático al terminar

**Módulo 5A — Motor de procesos pesados**
- `$script:systemProcessNames` — HashSet con 45 procesos que nunca se pueden terminar
- `Test-SystemProcess` — triple validación: nombre, PID ≤ 4, ruta en System32/SysWOW64
- `Get-ProcessDetails` — lee Path/Description/Company via `FileVersionInfo` + fallback CIM
- `Get-HeavyProcesses` — dos muestras separadas 600ms para CPU% real, combina top por CPU y RAM sin duplicados, score ponderado CPU×1.5+RAM/100
- `Stop-ManagedProcess` — termina proceso con doble validación de seguridad

**Módulo 5B — UI de procesos pesados**
- Sección "Procesos Pesados" en tab Herramientas con altura fija 280px
- `Render-ProcessList` — filas con mini-barra de CPU (Grid proporcional), RAM en MB/GB con color reactivo, badge Sistema o botón Terminar
- `Refresh-ProcessList` — respeta toggle "Mostrar sistema", actualiza stats CPU total y conteo
- `Start-ProcTimer` / `Stop-ProcTimer` — `DispatcherTimer` de N segundos (configurable desde Settings)
- Auto-arranque al entrar al tab Herramientas, pausa al salir

**Módulo 6A — Motor de temperatura**
- `Get-CPUTemperature` — `MSAcpi_ThermalZoneTemperature` via CIM root/wmi, múltiples zonas, promedio y máximo, conversión de décimos de Kelvin
- `Get-GPUTemperature` — intenta LHM/OHM namespace, fallback graceful si no hay sensores
- `Get-ThermalStatus` — objeto unificado con thresholds normal (<70°C), warning (70-85°C), critical (>85°C)

**Módulo 6B — UI de temperatura**
- Integrada en monitor en tiempo real del tab Info del sistema
- `pbCPUTemp`, `lblCPUTemp`, `pbGPUTemp`, `lblGPUTemp`, `lblGPUTempSource`
- `Update-ThermalDisplay` — tick cada 5s via `$script:monitorTimer` existente
- Color reactivo verde/amarillo/rojo, badge "N/D" si no hay sensor

### Fase 3 — Automatización

**Módulo 7A — Motor de tareas programadas**
- `New-MaintenanceTask` — `Register-ScheduledTask` con frecuencias Daily/Weekly/AtStartup
- `Get-MaintenanceTask` / `Remove-MaintenanceTask` — gestión del estado de la tarea
- `Invoke-MaintenanceCycle` — ciclo standalone: temp, recycle, DNS flush, TRIM si SSD
- Genera `maintenance.ps1` standalone en `%USERPROFILE%\.OptimizarPC\`
- Log JSON con máximo 30 entradas en `maintenance_log.json`

**Módulo 7B — UI de mantenimiento automático**
- Sección en tab Herramientas con toggle ON/OFF, frecuencia, hora, checkboxes de acciones
- `Update-MaintUI` — muestra último run y próximo run
- TRIM deshabilitado automáticamente si no hay SSD
- `$script:brMaintOn/Off/Err` brushes congelados para el timer

**Módulo 8A — Motor historial enriquecido**
- `Get-SessionHistory` — envuelve `Get-BackupSessions` + agrega `scoreImprovement`
- `Get-HistoryStats` — devuelve TotalSessions, TotalFreedMB, AvgImprovement, DaysSince

**Módulo 8B — UI historial enriquecido**
- 4 cards de stats: sesiones totales, MB liberados, mejora promedio de score, días de uso
- Mini gráfico de barras de score por sesión (últimas 8) via Canvas bottom-aligned
- Barras coloreadas por rango de score, track gris de fondo

**Módulo 9A — Motor de detección fullscreen**
- `Add-Type Win32FS` con P/Invoke: `GetForegroundWindow`, `GetWindowRect`, `MonitorFromWindow`, `GetMonitorInfo`, `GetWindowThreadProcessId`
- `Test-FullscreenProcess` — devuelve el proceso activo fullscreen o `$null`
- `Test-KnownGame` — compara contra `$script:knownGames` (39 juegos conocidos)
- Guard idempotente con `'Win32FS' -as [type]`

**Módulo 9B — Motor de optimización en foco**
- `Apply-GameFocusMode` — eleva prioridad a `High`, silencia notificaciones via `ToastEnabled=0`
- `Restore-GameFocusMode` — restaura prioridad y notificaciones previas
- `$script:gameFocusState` — guarda Process/PreviousPriority/PreviousToast/Active

**Módulo 9C — Timer de detección**
- `$script:gamingTimer` — `DispatcherTimer` de 5s
- Badge `badgeGamingMode` en top bar (verde pulsante cuando activo)
- Guard `HasExited` para proceso que terminó sin pasar por no-fullscreen
- `Add_Closing` detiene el timer y restaura foco si la app cierra con gaming mode activo

### Fase 4 — Reportes

**Módulo 10 — Exportar reporte HTML**
- `Build-HTMLReport` — genera HTML standalone con CSS inline: info sistema, score antes/después, sesión, acciones aplicadas
- `Export-HTMLReport` — guarda en `Documentos\OptimizarPC_Reporte_yyyy-mm-dd.html` y abre el browser
- Botón `btnExportHTML` en footer de la pestaña Consola
- `HtmlEncode` para CPU/GPU/acciones, `double-quoted here-string` con variables expandidas

**Módulo 11A — Captura de estado del sistema**
- `Get-SystemSnapshot` — CPUIdle, RAMFreeMB, SvcCount, Score, ProcCount, DiskFreeMB
- `Compare-Snapshots` — 6 filas con delta y status better/neutral/worse
- Hooked en `btnRun` antes y después de optimizar

**Módulo 11B — Modal de comparativa antes/después**
- `Show-CompareDialog` — ventana WPF secundaria con tabla 5 columnas: dot + métrica + antes + después + delta
- 7 filas: 6 del snapshot + MB liberados
- Botones: Reiniciar ahora / Reiniciar después / Ver log
- Reemplaza el `MessageBox` final de `btnRun`

### Fase 5 — Empaquetado y monetización

**Módulo 12A — Motor de licencias**
- `Get-HardwareID` — SHA256 de ProcessorId + BIOSSerial, 16 hex mayúsculas, fallback MachineName+OSSerial
- `Get-ExpectedKey` — SHA256(hwid+salt) formateado XXXX-XXXX-XXXX-XXXX
- `Test-LicenseKey` — valida formato regex + compara contra hwid actual
- `Get-LicenseStatus` — lee `license.key`, retorna IsActivated/HardwareID/ExpiryDate

**Módulo 12B — Modo Free vs Pro**
- `Lock-ProFeature` — bloquea features Pro si no hay licencia activada
- `$script:IS_PRO` — flag global seteado al arrancar por `Get-LicenseStatus`
- Features bloqueadas en Free: tweaks de registro, revertir sesión, desinstalar bloatware, mantenimiento automático

**Módulo 12C — UI de activación**
- Tab "Licencia" (índice 8) con `badgeLicenseFree`/`badgeLicensePro` en header
- `lblHardwareID`, `btnCopyHWID`, `txtLicenseKey`, `btnActivateLicense`, `lblActivationResult`, `btnGetLicense`
- `Update-LicenseBadge` — actualiza badge según estado de activación

**Módulo 13 — Compilado a .exe**
- `Build.ps1` — script de compilación con 6 pasos: validar, instalar ps2exe, compilar, copiar XAML, firmar con certificado autofirmado, mostrar resumen
- `installer/WinBoost.iss` — script Inno Setup 6 para instalador profesional
- Genera `dist/WinBoost.exe` + `installer/Output/WinBoost_Setup_4.0.exe`

**Módulo 14 — Auto-updater mejorado**
- `Check-ForUpdates` extendido — guarda `$script:updateMeta` con Version/Changelog/ReleaseUrl/DownloadUrl/Sha256
- `Show-ChangelogDialog` — dialog con changelog + 3 botones
- `Start-UpdateDownload` — `WebClient` async + `DispatcherTimer` 300ms para progreso
- `Apply-Update` — script helper `do_update.ps1` en TEMP que espera PID, copia y relanza
- `version.json` extendido con `downloadUrl`, `sha256`, `changelog`

**Módulo 15A — Detección de primer uso**
- `Test-FirstRun` — lee/escribe `profile.json` con campo `firstRun`
- `Set-FirstRunComplete` — pone `firstRun=false`
- Hook en `Add_ContentRendered` para mostrar onboarding en primer inicio

**Módulo 15B — Ventana de bienvenida (Onboarding)**
- `Show-OnboardingDialog` — wizard de 4 pasos en ventana 600x500
- Paso 0: hardware detectado (CPU/GPU/RAM/Disco/Tipo)
- Paso 1: score inicial animado con color según rango
- Paso 2: 3 tarjetas de preset (Gaming/Productividad/Conservador) con badge "Recomendado" según hardware
- Paso 3: resumen + botón Empezar que aplica el preset elegido
- Dots de progreso en header, bloqueo del botón X durante el wizard

---

## Post-roadmap v3 — Estabilidad

**Módulo 3.2 — Limpieza profunda de cache**
- 4 categorias de limpieza con MB liberados individuales y total loggeado en consola:
  - **Explorer cache**: `%LOCALAPPDATA%\IconCache.db` + `iconcache_*.db` + `thumbcache_*.db` (detiene y reinicia Explorer)
  - **WER reports**: `ReportQueue` y `ReportArchive` en `%LOCALAPPDATA%` y `%ProgramData%`
  - **Logs CBS/DISM**: `%SystemRoot%\Logs\CBS\` y `%SystemRoot%\Logs\DISM\` (`.log` y `.cab`)
  - **Shader cache**: `D3DSCache`, `NVIDIA\DXCache`, `NVIDIA\GLCache`, `AMD\DxCache` en `%LOCALAPPDATA%`
- `lblDeepCleanStatus` muestra "Listo  X MB liberados" al terminar
- Cada paso llama `Write-Log` con su MB, activando el badge de errores del sidebar si algo falla
- XAML: descripcion actualizada para mencionar los 4 tipos de cache limpiados

**Módulo 2.6 — Validacion de archivos .reg antes de restaurar**
- `Test-RegFileValid` — nueva funcion: lee los primeros bytes del archivo, detecta encoding (UTF-16 LE con BOM `FF FE` o ANSI/UTF-8), verifica que la primera linea sea `Windows Registry Editor Version 5.00` o `REGEDIT4`, y que el contenido incluya al menos un bloque `[HKEY_`
- `Restore-RegFromSession` extendida: llama `Test-RegFileValid` antes de `reg.exe import`; archivos invalidos incrementan `failed` y se agregan a `result.invalidFiles`
- `Restore-Session` extendida: loggea cada archivo invalido por nombre con tipo `"err"` para que aparezca en consola y active el badge de errores del sidebar

**Módulo 2.3 — Badge de errores en sidebar**
- `$script:errorList` — `List[string]` global que acumula cada mensaje de tipo `"err"` con su timestamp
- `Write-Log` extendido: cuando `type -eq "err"` agrega a `$script:errorList`, activa `btnErrBadge.Visibility=Visible` y actualiza `lblErrCount` ("1 error" / "N errores")
- `btnErrBadge` — nuevo botón en sidebar (Row 2, entre info sistema y licencia), oculto por defecto, estilo `BtnErrBadge` (fondo rojo oscuro `#2A0A0A`, borde `#5A1515`, icono ⚠)
- `Show-ErrorSummary` — ventana WPF secundaria 440×360 con lista scrolleable de errores, botón "Ver consola" (navega al tab Consola y cierra el dialog) y botón "Limpiar" (vacia `$script:errorList` y oculta el badge)

---

## Post-roadmap v2 — Estética y UX

**Módulo 1.7 — Tema claro**
- 11 pinceles tematizables (`BrushAppBg`, `BrushSidebar`, `BrushCard`, `BrushDeep`, `BrushElev`, `BrushCtrl`, `BrushBorder`, `BrushFg1`, `BrushFg2`, `BrushFgMuted`, `BrushFgDim`) definidos en `Window.Resources` con valores oscuros por defecto
- 363 referencias de color hardcodeadas en la seccion de layout del XAML convertidas a `{DynamicResource BrushXxx}` (backgrounds, borders y foregrounds; los estilos de botones/controles en `Window.Resources` quedan hardcodeados)
- `cboTheme` ahora tiene 3 opciones: Oscuro / Claro / Automatico (index 0/1/2)
- `Apply-Theme` — nueva funcion: detecta preferencia, lee `AppsUseLightTheme` del registro para modo Auto, actualiza todos los pinceles via `$window.Resources[key] = brush.Freeze()`; modo dark y light definidos con paleta completa
- `Apply-Settings` ahora llama `Apply-Theme` al final para aplicar el tema al iniciar
- `cboTheme.Add_SelectionChanged` ahora llama `Apply-Theme` en tiempo real (ya no muestra MessageBox)
- `Render-SettingsUI` actualizado para mapear los 3 indices correctamente

**Módulo 1.6 — Hover states en cards del tab Optimizar**
- Nuevo estilo `CardOptimizar` en `Window.Resources`: setters para Background, CornerRadius, BorderBrush, BorderThickness, ClipToBounds + trigger `IsMouseOver` que cambia `BorderBrush` a `#00C8FF`
- Las 5 cards del tab Optimizar (Limpieza, Sistema y Rendimiento, Privacidad, Red, Servicios) usan `Style="{StaticResource CardOptimizar}"` en lugar de propiedades inline, para que el trigger funcione correctamente (local values tienen mayor precedencia que style triggers)

**Módulo 1.5 — Responsive / escalado**
- `icScoreHistory` Canvas: removido `HorizontalAlignment="Left"` para que el canvas ocupe el ancho completo disponible (Stretch)
- `Render-ScoreHistory` reescrita: calcula `barWidth` dinamicamente segun `ActualWidth` del canvas, centra las barras con `$xOffset`, fallback a 320px antes del primer layout
- `Add_SelectionChanged` extendido con case "Historial": re-renderiza el chart con `BeginInvoke` a prioridad `Loaded` al abrir la tab
- `Add_ContentRendered` extendido: defer inicial de `Render-ScoreHistory` a `DispatcherPriority::Loaded` para obtener `ActualWidth` real post-layout
- Handler debounced `$window.Add_SizeChanged`: `DispatcherTimer` de 200ms que re-renderiza el chart solo si la tab Historial esta activa

**Módulo 1.4 — Consistencia visual entre pestañas**
- Tab Consola: agregado header "CONSOLA DE LOG" (FontSize=11, SemiBold, `#00C8FF`) como nueva Row=0; controles de toolbar movidos a Row=1 con Margin `0,0,0,12`; log area a Row=2
- Tab Herramientas: root `Grid Margin` ajustado de `20,16` a `20,14` para igualar densidad visual con Optimizar
- 5 headers de cards en Herramientas: "LIBERADOR DE RAM", "LIMPIEZA PROFUNDA DE CACHE", "BENCHMARK RAPIDO DE DISCO", "MANTENIMIENTO AUTOMATICO", "PROCESOS PESADOS" — FontSize `10` → `11` para consistencia con secciones de Optimizar

**Módulo 1.3 — Estados vacíos diseñados**
- `New-EmptyState` — helper que devuelve un `Border` centrado con icono 44px (Segoe UI Symbol) + título `SemiBold` + subtítulo wrapeado, `vertPadding` configurable
- Historial sin sesiones: icono ⏱ (`0x23F1`), "Sin historial", hint de cómo crear la primera
- Bloatware limpio: icono ✓ (`0x2713`), "Sistema limpio", confirma que no se detecto bloatware
- Procesos sin actividad: icono ⚙ (`0x2699`), "Sin actividad pesada", padding reducido a 20px para el panel fijo de 280px

**Módulo 1.2 — Animaciones de transición entre pestañas**
- `Set-ActiveNav` ahora anima `SelectedContent.Opacity` de 0→1 en 150ms via `DoubleAnimation` al cambiar de tab
- Fade-in aplica en toda navegación sidebar (click manual y llamadas programáticas)
- Envuelto en `try/catch` para que un fallo de animación no bloquee la navegación

**Módulo 1.1 — Splash screen de carga**
- `Show-SplashScreen` — ventana WPF 400×260, `WindowStyle=None`, fondo `#111111` con borde acento `#1A3A44`
- Logo `⚡` (Segoe UI Symbol, 44px, `#00C8FF`) + título "WinBoost" (30px bold) + subtítulo tenue
- Barra de progreso custom: track `#1A1A1A` + fill `#00C8FF`, animación ease-out cúbica en ~2.4s (150 ticks × 16ms)
- Se lanza solo si `settings.ShowSplash = $true` (toggle en Ajustes ya existente)
- `Load-Settings` llamado antes del splash para respetar la preferencia del usuario

---

## Post-roadmap — Mejoras adicionales

**Rediseño visual completo**
- Migración de TabControl horizontal a sidebar vertical (155px) con botones pill redondeados
- Top bar con logo ⚡ WinBoost + badges + score widget + OS
- Nuevo nombre: **WinBoost** (antes "OptimizarPC Universal")
- Estilo `BtnNav` / `BtnNavActive` con fondo `#00C8FF18` y borde `#00C8FF40`
- Press animation en botones via `ScaleTransform 0.97` en `IsPressed`
- Borde de color por categoría en secciones del tab Optimizar
- CheckBox custom con ControlTemplate oscuro
- ScrollBars delgadas con thumb `#333333`
- Score widget clickeable que navega a Info del sistema

**Pestaña Ajustes**
- Sección Apariencia: selector de tema (oscuro/automático), selector de idioma placeholder (deshabilitado, próximamente)
- Sección Comportamiento: cerrar/minimizar, splash toggle, intervalo de procesos (1/3/5/10s), iniciar con Windows
- Sección Mantenimiento: ruta de backups (FolderBrowserDialog), retención configurable (7/14/30/60/ilimitado)
- Sección Acerca de: versión, botón buscar updates, stats de uso (sesiones/MB/mejor score/días), reset settings
- `Load-Settings`, `Save-Settings`, `Apply-Settings`, `Render-SettingsUI`
- Persiste en `settings.json` separado de `profile.json`

**Footer dinámico**
- El footer (Ejecutar optimización) solo visible en la pestaña Optimizar, colapsado en las demás

**Async en pasos lentos**
- `Get-WingetInstalledMap` con timeout de 8s via `Start-Job`
- Score post-optimización calculado en `BeginInvoke Background`
- Scan de bloatware inicial con prioridad `ApplicationIdle`
- `Flush-UI` antes/después de cada volumen en TRIM

**Purga de Standby List**
- `Invoke-StandbyListPurge` — `NtSetSystemInformation` con `MemoryPurgeStandbyList=4`
- Se ejecuta automáticamente después de liberar RAM
- Log separado: "Working Set: +X MB" + "Standby List: +Y MB" + "Total: +Z MB"
