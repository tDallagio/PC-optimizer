# WinBoost v4.1

## Archivos del proyecto
- `OptimizarPC_App.ps1` — lógica principal (10400+ líneas)
- `OptimizarPC_UI.xaml` — interfaz WPF separada (2550+ líneas)
- `version.json` — check de updates en GitHub
- `EJECUTAR_COMO_ADMIN.bat` — launcher para desarrollo
- `Build.ps1` — compilar a exe + firma
- `installer/WinBoost.iss` — script Inno Setup para instalador
- `docs/PENDIENTES.md` — features pendientes con checkboxes
- `docs/CHANGELOG.md` — historial completo de implementaciones

## Stack
- PowerShell 5.1 (Windows 10/11)
- WPF + XAML cargado desde archivo externo
- `Get-CimInstance` (no WMI)
- Sin threading — todo en hilo UI con `Flush-UI` entre pasos
- Nombre de la app: **WinBoost**

## Migracion a C# / WPF (en curso)
La app esta migrando de PowerShell 5.1 a C#/WPF de forma incremental. El proyecto
C# vive en `src-csharp/`. El `.ps1` (OptimizarPC_App.ps1) sigue siendo la version
distribuida hasta que C# llegue a paridad. El XAML (OptimizarPC_UI.xaml) se reusa
en ambos.
- Las reglas de PowerShell de mas abajo aplican SOLO al codigo legacy en `.ps1`.
- Para codigo C# nuevo, usar las convenciones C# (ver mas abajo).
- Validar cada modulo migrado contra el comportamiento del `.ps1` original.

## Convenciones C# (src-csharp)
- .NET 8, WPF. Nullable habilitado.
- async/await + Task.Run para TODO trabajo pesado; nunca bloquear el hilo UI.
  (Reemplaza el patron Flush-UI del PS1: en C# la UI no se congela.)
- Actualizar la UI desde background via Dispatcher.
- Los elementos con x:Name en el XAML son campos tipados generados; NO usar FindName
  manual. (Reemplaza Get-Ctrl.)
- Brushes y colores desde recursos XAML tipados. (Reemplaza New-Brush.)
- P/Invoke nativo en una clase NativeMethods dedicada.
- Registrar cada modulo migrado en CHANGELOG.md.

## Reglas PowerShell legacy (.ps1) — NUNCA
- Sin operadores PS7 (`?.` `??` etc.)
- Sin `System.Threading.Thread`
- Sin `-Wait` en `Start-Process` en el hilo UI
- Sin propiedades WPF de .NET 5+ (`LetterSpacing` etc.)
- Sin caracteres no-ASCII en NINGUN string PS ejecutable: ni em-dash, ni tildes, ni ñ en MessageBox, ColorConverter, Write-Log u otras funciones. Solo seguros en comentarios # y here-strings HTML.
- No llamar funciones antes de definirlas — PS5.1 es lineal. Inicializaciones que dependen de funciones van en `Add_ContentRendered`.
- No crear un segundo `Add-Type` con el mismo DLL/clase si ya existe — genera error de tipo duplicado.
- ComboBox ControlTemplate: el ToggleButton interno NO hereda Background
  del ComboBox padre via TemplateBinding — usa el color del tema del sistema.
  Siempre hardcodear Background="#1E1E1E" directamente en el Border del
  ToggleButton, nunca {TemplateBinding Background}.
- En PS5.1, nunca usar `$wpfObject.DependencyProperty = [SomeClass]::StaticMethod(args)`
  dentro de funciones que retornan objetos — el valor de retorno del metodo estatico
  escapa al pipeline y corrompe el resultado de la funcion. Usar siempre variable
  intermedia + `[void]` para metodos void:
  `$val = [SomeClass]::StaticMethod($args); [void]$obj.SetValue($dp, $val)`
  Para crear brushes desde hex usar siempre `New-Brush`, que internamente usa
  `BrushConverter.ConvertFromString` en lugar de `ColorConverter`.

## Reglas PowerShell legacy (.ps1) — SIEMPRE
- `Flush-UI` despues de cualquier update de UI
- Logica en PS1, visual en XAML
- Controles UI: `$var = Get-Ctrl "xName"` — nunca `FindName` directo
- Al modificar un archivo, guardar los cambios directamente en su ruta. No imprimir el contenido del archivo en el chat.
- TODO cambio de codigo (feature, fix o mantenimiento) se registra en CHANGELOG.md, no solo los items del roadmap (F-numerados). Un cambio sin entrada en CHANGELOG.md esta incompleto.
- Antes de entregar PS1: verificar balance de llaves con script Python, resultado debe ser 0
- Antes de entregar XAML: parsear con `xml.etree.ElementTree`, debe ser valido

## Patrones clave
- Registrar control:    `$var = Get-Ctrl "x:Name"`
- Leer checkbox:        `$checks["Key"].IsChecked`
- Log:                  `Write-Log "mensaje" "tipo"` — tipos: `ok/err/skip/head/info`
- Progreso:             `Set-Progress [0-100] "mensaje"`
- Flush UI:             `Flush-UI`
- Navegacion sidebar:   `Set-ActiveNav [0-9]`
- Backup automatico:    `Save-RegBackup` integrado en `Set-Reg` / `Save-SvcBackup` integrado en `Disable-Svc`
- Nuevo modulo:         definir funciones → registrar controles con `Get-Ctrl` → agregar eventos → init en `Add_ContentRendered`

## Estilo visual
- Fondo `#0D0D0D` | Cards `#161616` | Acento `#00C8FF`
- Tipografia Segoe UI | CornerRadius 6-8
- Colores de estado: ok `#22C55E` | warn `#F59E0B` | err `#EF4444` | info `#00C8FF`
- Estilos de boton: `BtnMain` / `BtnSec` / `BtnPreset` / `BtnDanger` / `BtnNav` / `BtnNavActive` / `BtnNavLicense` / `BtnToggleOn` / `BtnToggleOff`

## Orden de tabs (SelectedIndex / Set-ActiveNav)
- 0 = Optimizar
- 1 = Consola
- 2 = Arranque
- 3 = Herramientas
- 4 = Info del sistema
- 5 = Historial
- 6 = Bloatware
- 7 = Ajustes
- 8 = Licencia
- 9 = Tuning Avanzado

## Variables globales — no redefinir
- `$IS_LAPTOP`, `$HAS_SSD`, `$totalRAM`, `$VERSION`, `$SYSDRIVE`
- `$PROFILE_PATH`, `$BACKUP_ROOT`, `$SETTINGS_PATH`
- `$script:settings` — objeto de configuracion (Load/Save/Apply-Settings)
- `$script:navButtons` — array de botones de navegacion sidebar
- `$script:activeSession`, `$script:sessionActions` — backup activo (mod 1A)
- `$script:auditItems` — checks del score (mod 3A)
- `$script:dnsProviders` — tabla de proveedores DNS
- `$script:bloatwareDb`, `$script:bloatList`, `$script:bloatChecks` — bloatware (mod 4A/4B)
- `$script:systemProcessNames` — HashSet procesos sistema (mod 5A)
- `$script:procsList`, `$script:procTimer`, `$script:procTimerRunning` — procesos (mod 5B)
- `$script:monitorTimer` — DispatcherTimer monitor 1s
- `$brMon`, `$brProc` — brushes congelados (monitor y procesos)
- `$script:gameFocusState`, `$script:gamingTimer`, `$script:knownGames` — gaming focus (mod 9A/9B/9C)
- `$script:updateMeta` — metadata de update disponible (mod 14)
- `$script:snapshotBefore`, `$script:snapshotAfter`, `$script:snapshotCompare` — comparativa (mod 11A/11B)
- `$script:isFirstRun` — flag primer uso (mod 15A)
- `$script:IS_PRO` — flag licencia Pro activa (mod 12B)
- `$script:scoreBefore`, `$script:scoreAfter` — scores para delta post-optimizacion

## Modulos implementados
Ver `docs/CHANGELOG.md` para detalle completo de cada funcion.

Resumen: 1A/1B/1C · 2 · 3A/3B · 4A/4B/4C · 5A/5B · 6A/6B · 7A/7B · 8A/8B · 9A/9B/9C · 10 · 11A/11B · 12A/12B/12C · 13 · 14 · 15A/15B + Settings + Sidebar + Async + Standby Purge

## Arranque de sesion
1. Lee `CLAUDE.md` — reglas, stack, variables
2. Lee `docs/PENDIENTES.md` — que falta implementar (checkboxes)
3. Lee `docs/CHANGELOG.md` — que se implemento (historial)

Continuar con el primer item sin tilde `[ ]` en PENDIENTES.md

## Probar
Ejecutar `EJECUTAR_COMO_ADMIN.bat` como administrador.
