# Spike: WPF-UI (lepoco/wpfui) — evaluación

**Descartable.** No forma parte del producto. No toca `src-csharp/WinBoost` ni comparte código
con él. Su único objetivo fue responder, con evidencia de código y de la app corriendo, si
WPF-UI es una base viable para el rediseño de WinBoost (ver `docs/PENDIENTES.md`, Módulo 1).

## Qué es

Una `FluentWindow` mínima con:
- `NavigationView` (sidebar) con 4 items (Optimizar / Sistema / Avanzado / Ajustes), navegando
  a `Page`s reales vía `TargetPageType`.
- En "Optimizar": dos `Card` con métricas, un `ToggleSwitch`, botones `Primary`/`Secondary`/
  `Danger`, y un botón que abre un `ContentDialog` (vía `ContentDialogHost`).
- Marca de WinBoost aplicada sobre el theming de WPF-UI: tema oscuro, accent `#00C8FF`
  (`ApplicationAccentColorManager.Apply`), Segoe UI, sin emojis, textos en español.

## Cómo correr el publicado

```powershell
cd spike\WpfUiSpike
dotnet publish -c Release -p:PublishProfile=win-x64-selfcontained
```

El `.exe` self-contained single-file queda en `spike\WpfUiSpike\bin\publish\win-x64\WpfUiSpike.exe`.
Correrlo directo (no requiere .NET instalado ni admin).

## Aprendizajes para la integración en WinBoost (registrar, no accionar todavía)

Del diagnóstico y fix del crash de navegación (ver más abajo). Anotado acá para no perderlo cuando
se decida integrar WPF-UI al producto real:

1. **El `ContentDialogHost` va UNA sola vez por ventana** (en la `Window` raíz, ej. `MainWindow`),
   nunca declarado dentro de cada `Page`. WPF-UI solo permite uno registrado por ventana; si vive en
   una página que se recrea al navegar, la segunda visita revienta (`InvalidOperationException`,
   ver diagnóstico abajo).
2. **La navegación inicial de WPF-UI va en `Loaded`, no en el constructor** de la ventana —
   `NavigationView.Navigate(...)` necesita que su `ControlTemplate` (con el `Frame` interno) ya esté
   aplicado, si no tira `NullReferenceException`.
3. **`NavigationCacheMode` es una decisión por página**, no un default a ignorar: acá quedó en
   `Disabled` (el default de WPF-UI) para las 4 páginas del spike. Al integrar, pantallas con datos
   vivos (info del sistema, procesos, temperaturas) probablemente quieran `Disabled` (refrescan al
   entrar); pantallas con estado editable del usuario, `Required` (para no perder lo que se estaba
   editando al cambiar de sección y volver). Decidir pantalla por pantalla en el rediseño real, no
   copiar el default a ciegas.

## Resultado (respuestas a las 4 preguntas del spike)

1. **¿Look premium?** Sí, a simple vista. El tema oscuro + accent `#00C8FF` sobre `NavigationView`/
   `Card`/`Button` da una dirección muy cercana a PTU/Win11 sin CSS/XAML custom más allá de un tema
   y algunos colores.
2. **¿Controles cubren los items 1/3/8 del rediseño?** Sí, tal cual, sin trabajo extra:
   `NavigationView` = sidebar (item 1), `ToggleSwitch` = toggle estilizado (item 3),
   `ContentDialog`/`ContentDialogHost` = diálogo propio (item 8). `Card` cubre bien las métricas
   del dashboard (item 2 del Módulo 1, no evaluado a fondo acá pero el control aplica directo).
3. **¿La marca convive o pelea?** Convive. `ApplicationAccentColorManager.Apply(Color, ApplicationTheme)`
   acepta `#00C8FF` sin resistencia — todos los controles (selección de nav, toggle, botón primario,
   botones del diálogo) heredan el accent vía `AccentTextFillColorPrimaryBrush`/recursos dinámicos
   del tema, no hace falta re-templatear nada para verlo aplicado.
4. **¿Carga limpio en el .exe publicado self-contained single-file?** Sí, con una salvedad de
   implementación (no de WPF-UI): `NavigationView.Navigate(...)` llamado en el **constructor** de
   la ventana revienta con `NullReferenceException` en `UpdateContent` (el `ControlTemplate` con el
   `Frame` interno todavía no se aplicó). Moviendo la primera navegación a `Loaded` se resuelve. Con
   ese fix, tanto Debug como el publicado (mismo perfil de publish que `Publish-CSharp.ps1`: self-
   contained, single-file, `IncludeAllContentForSelfExtract=false`) arrancan sin
   `FileNotFoundException` ni recursos faltantes.

## Otros hallazgos (con evidencia)

- **Peso:** WPF vacío self-contained single-file (mismo perfil) publica en **71.58 MB**
  (`71.582.280` bytes). Este spike con WPF-UI publica en **74.07 MB** (`74.068.531` bytes).
  Overhead de WPF-UI: **~2.37 MB** (~3.5%).
- **Íconos en Windows 10:** WPF-UI usa la fuente `Segoe Fluent Icons` (confirmado por búsqueda
  literal del string en `Wpf.Ui.dll`) y **no la embebe** — el paquete NuGet `WPF-UI 4.3.0` no trae
  ningún `.ttf`/`.otf`. `Segoe Fluent Icons` es nativa de Windows 11; en Windows 10 depende de que
  el sistema la tenga instalada (no siempre es el caso). En la máquina de desarrollo (Windows 10
  Pro build 19045) se confirmó que **`Segoe Fluent Icons` NO está instalada** (`InstalledFontCollection`
  solo lista `Segoe MDL2 Assets` y `HoloLens MDL2 Assets`) — y aun así los íconos del spike
  (`Rocket24`, `Desktop24`, `Wrench24`, `Settings24`, `Info24`) **renderizaron correctamente**
  (ver capturas). Esto es consistente con que varios glyphs comunes comparten el mismo codepoint
  PUA entre `Segoe Fluent Icons` y `Segoe MDL2 Assets` (nativa de Win10), y el fallback de fuentes
  de Windows resuelve al segundo. **No es garantía para todo el set de íconos de WPF-UI**: los
  símbolos agregados solo en Fluent (sin equivalente en MDL2) sí arriesgan mostrarse como "tofu" en
  Win10 sin esa fuente — habría que auditar cada ícono puntual que se use en el rediseño real antes
  de confiar en el fallback.
- **Mica / FluentWindow sin Win11:** por código (`WindowBackgroundManager.cs`), el backdrop Mica se
  gatea por detección de versión de Windows 11; en un SO que no la soporta el mecanismo no lo aplica
  (no hay crash documentado), la ventana queda con el fondo opaco del tema. No se pudo confirmar
  visualmente en una máquina Windows 10 real en esta sesión — deja pendiente la confirmación visual
  del usuario mencionada en el pedido original.

## Veredicto

**GO condicionado:** los 4 controles cubren el checklist sin trabajo extra, la marca no pelea, el
peso adicional es marginal (~2.4 MB) y el publicado no rompe (con los dos ajustes de implementación
documentados en "Aprendizajes para la integración" arriba: navegación inicial en `Loaded`, y
`ContentDialogHost` único a nivel ventana — ninguno es un defecto de fondo de la librería). El único
punto abierto real es el riesgo de íconos faltantes en Windows 10 para símbolos que no tengan
equivalente en `Segoe MDL2 Assets` — a auditar ícono por ícono si se decide integrar WPF-UI al
producto.

La decisión de integrar (y cómo) queda fuera de este spike.

---

## Crash de navegación: diagnosticado y resuelto

**Síntoma original** (`11_diag_crash_navegacion_spike.txt`): el .exe publicado se cerraba solo tras
1-2 cambios de sección en el `NavigationView`.

**Causa raíz** (confirmada con log real, reproducida de forma consistente en Debug y en el
publicado):

```
System.InvalidOperationException: Only one ContentDialogHost instance is allowed per Window.
   at Wpf.Ui.Controls.ContentDialogHost.RegisterHost(Window window)
   at Wpf.Ui.Controls.ContentDialogHost.ContentDialogHost_Loaded(Object sender, RoutedEventArgs e)
```

`NavigationViewItem.NavigationCacheMode` tiene default `Disabled`, así que cada vuelta a "Optimizar"
creaba una `DashboardPage` nueva. `DashboardPage.xaml` declaraba su propio
`<ui:ContentDialogHost x:Name="DialogHost" />`, y `ContentDialogHost` se registra contra la `Window`
en su evento `Loaded`; WPF-UI solo permite uno registrado por ventana, y nada desregistraba el
anterior al descartar la página → la segunda visita a "Optimizar" chocaba contra el registro que
dejó la primera.

**Fix aplicado** (`12_fix_crash_navegacion_spike.txt`, opción canónica — la que WPF-UI espera y la
que se va a replicar al integrar en WinBoost, **no** el atajo de `NavigationCacheMode="Required"`
que solo tapa el síntoma):
- `ContentDialogHost` se movió de `DashboardPage.xaml` a `MainWindow.xaml`, uno solo por ventana
  (`Grid.RowSpan="2"` para cubrir TitleBar + contenido al abrirse).
- `MainWindow` expone `public ContentDialogHost DialogHost => RootDialogHost;`.
- `DashboardPage.xaml.cs` obtiene el host vía `(Window.GetWindow(this) as MainWindow)?.DialogHost`
  en vez de tener el suyo propio.

**Verificado sobre el .exe publicado**: 40 clicks de navegación (10 vueltas completas por las 4
secciones) sin crashear, más apertura del `ContentDialog` al final — todo OK, `%TEMP%\WpfUiSpike_crash.log`
queda limpio (solo la línea de arranque, ninguna excepción) en toda la corrida. Antes del fix, el
mismo log mostraba la excepción de arriba de forma repetible a la segunda vuelta a "Optimizar".

### Instrumentación de diagnóstico: qué se sacó y qué se dejó

- **Sacado**: los logs de `RootNavigation.Navigated`/`SelectionChanged` en `MainWindow.xaml.cs`
  (cumplieron su función para encontrar la causa raíz, ya no hacen falta).
- **Dejado a propósito**: la captura global de excepciones en `App.xaml.cs`
  (`DispatcherUnhandledException` / `AppDomain.UnhandledException` /
  `TaskScheduler.UnobservedTaskException`), que escribe a `%TEMP%\WpfUiSpike_crash.log`. Se
  mantiene mientras el spike siga en evaluación, por si aparece algo más al seguir probando
  controles; no es parte del control/producto real. Si se descarta el spike o se cierra esta
  evaluación, se puede sacar junto con el archivo de log.

### Dónde queda todo

- `.exe` publicado (con el fix): `spike\WpfUiSpike\bin\publish\win-x64\WpfUiSpike.exe`.
- Log de excepciones (vacío de crashes tras el fix, se sigue completando en cada arranque):
  `%TEMP%\WpfUiSpike_crash.log`.
