# WinBoost — Changelog

> Historial de implementaciones en orden cronológico.
> Usar para armar release notes al lanzar.

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
