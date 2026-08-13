# WinBoost — Changelog

> Historial de implementaciones en orden cronológico.
> Usar para armar release notes al lanzar.

---

## C# fix: borde del CheckBox marcado quedaba "apagado" al destildar y volver a tildar

Bug reportado por el usuario sobre el publicado: la primera vez que se tilda una casilla el
borde se ve en acento (bien), pero si se destilda y se vuelve a tildar la misma casilla, el
borde queda gris/apagado en vez de acento — el relleno sí se comporta bien, solo el borde falla.

**Causa raíz**: el diseño de las dos entradas anteriores (relleno solido → translúcido)
animaba `Background`/`BorderBrush` con `ColorAnimation` vía `Storyboard.TargetName`, pero
tenía **dos triggers independientes animando la misma propiedad** (`chkBrd.Color`): el de
`IsChecked` y un `MultiTrigger` de hover (con condición `IsChecked="False"` pensada
justamente para que nunca compitieran). El problema: al hacer click, el mouse siempre está
encima de la casilla — `IsMouseOver` ya es `True` en el momento exacto en que `IsChecked`
cambia, así que el `MultiTrigger` de hover también dispara sus `EnterActions`/`ExitActions`
en el mismo instante que el trigger de `IsChecked`. Dos `Storyboard` sin nombre animando la
misma propiedad al mismo tiempo (`HandoffBehavior.Compose` por default) no tienen un ganador
determinista — cuál de los dos queda "sostenido" (`FillBehavior.HoldEnd`) depende del orden
de evaluación interno de WPF, no es controlable desde el XAML. Por eso funcionaba la primera
vez (temporizaciones distintas al cargar la página) y fallaba en el segundo ciclo.

**Fix**: se sacó la animación por completo del borde y el fondo — se volvió al patrón
**determinista** que ya usaba el diseño original de este mismo `CheckBox` (antes de la
adopción WPF-UI): `Setter` planos con `TargetName="chkBorder"` apuntando directo a las
propiedades `Background`/`BorderBrush` del `Border` (un `FrameworkElement` real, no un
`SolidColorBrush` con nombre). A diferencia de los `Storyboard` compitiendo, la precedencia de
WPF entre `Setter`s de múltiples triggers activos a la vez SÍ está garantizada y es
determinista: gana el último trigger declarado en `ControlTemplate.Triggers` para esa
propiedad. Orden final: `IsMouseOver` primero (tiñe el borde solo si no está marcado), luego
`IsChecked` (si está marcado, su `Setter` de `BorderBrush` gana sobre el de hover — asegura
que un checkbox marcado+hover se vea con el borde solido de acento, nunca el tinte de hover),
y `IsEnabled=False` al final (gana sobre todo). Se sacaron los pinceles nombrados `chkBg`/
`chkBrd` (ya no hacen falta sin animación) — el `Border` vuelve a tener `Background`/
`BorderBrush` como valores literales directos. El color final del relleno marcado
(translúcido `#4D00C8FF`) y del borde (`{StaticResource BrushAccent}`, sólido) no cambiaron,
solo el mecanismo que los aplica.

**Verificación**: `dotnet build` (0 errores), publish con `Publish-CSharp.ps1 -SkipInstaller`,
corrida sobre el .exe publicado con capturas `PrintWindow` confirmando el estado por defecto
(marcado = relleno vidrio + borde solido; desmarcado = caja oscura). El ciclo exacto que
reportó el bug (destildar y volver a tildar la MISMA casilla) no se pudo automatizar de forma
confiable en esta sesión — la simulación de clicks por coordenadas y UI Automation no
localizaban los `CheckBox` de forma consistente sobre este `FluentWindow` (limitación de la
herramienta de testing, no ambigüedad sobre la causa del bug: el mecanismo de `Storyboard`
compitiendo es una causa raíz real y documentada de WPF, no una hipótesis). Le pedimos al
usuario repetir a mano el repro exacto (tildar, destildar, tildar de nuevo la misma casilla,
con el mouse sin moverse) sobre el publicado en
`src-csharp\WinBoost\bin\publish\win-x64\WinBoost.exe`.

---

## C# ajuste: relleno del CheckBox marcado pasa a translúcido ("vidrio" cyan)

Feedback del usuario tras ver el relleno sólido de acento (ver entrada anterior): pidió un
efecto más translúcido, "como si fuera un vidrio transparente de color cyan". Cambio en
`MainWindow.xaml`, mismo `ControlTemplate` de `CheckBox`: la `ColorAnimation` de `chkBg` en el
trigger `IsChecked="True"` pasa de `{StaticResource AccentColor}` (opaco) a un `Color` literal
con canal alfa reducido — iterado en dos pasadas con el usuario: primero `#D900C8FF` (~85%
alfa, casi opaco, insuficiente) y despues `#4D00C8FF` (~30% alfa, confirmado) — de forma que se
vea el fondo oscuro de la card por debajo (efecto vidrio). El borde (`chkBrd`) se dejó en
`{StaticResource AccentColor}` sólido a propósito, sin alfa: da el contorno definido que
mantiene la casilla legible como "marcada" incluso con el relleno casi transparente. El resto
del template (caja 16x16, sin checkmark, transición con `DurFast`, hover, disabled) no cambió.

**Verificación — sobre el PUBLICADO**: `dotnet build` (0 errores) y publish con
`Publish-CSharp.ps1 -SkipInstaller` en cada iteración; capturas `PrintWindow` del .exe real
confirmando el efecto vidrio (pixel-sample sobre la captura: color efectivo notablemente mas
oscuro/apagado que el acento puro, consistente con el blend de alfa) antes de pedir la
confirmación visual final del usuario.

---

## C# fix: checkmark del CheckBox mal centrado — se saca el glyph, queda solo el relleno de acento

Feedback del usuario tras confirmar visualmente el paso 1 de adopción (CheckBox) sobre el
publicado: el trazo del checkmark no quedaba centrado dentro de la casilla. En vez de ajustar
las coordenadas del `Path` (`chkMark`, `Data="M 3,8.2 L 6.4,11.6 L 13,4"`), se sacó el glyph
por completo — el estado marcado se comunica solo con el relleno sólido de acento (`#00C8FF`)
de la casilla, sin nada dibujado encima. Cambio quirúrgico sobre `MainWindow.xaml`:

- Se removió el `<Path x:Name="chkMark" .../>` del `ControlTemplate` de `CheckBox` y la
  `DoubleAnimation` de `Opacity` que lo desvanecía in/out en los triggers de `IsChecked`
  (entrance y exit). El resto del template (caja `chkBorder` 16x16, pinceles animables
  `chkBg`/`chkBrd`, transición de color con `DurFast` al marcar/desmarcar, hover con
  `MultiTrigger` condicionado a `IsChecked="False"`, estado deshabilitado) queda igual.
- Sigue siendo el mismo `Style` implícito (sin `x:Key`): no se tocó ninguna de las 79
  declaraciones de `CheckBox`.

**Verificación — sobre el PUBLICADO**: `dotnet build` (0 errores), publish con
`Publish-CSharp.ps1 -SkipInstaller`, corrida real del .exe con captura `PrintWindow` —
confirmado en tab Optimizar (categorías Privacidad, Red, Servicios): las casillas marcadas se
ven como pastilla sólida de acento sin ningún trazo encima, las desmarcadas conservan la caja
oscura vacía. Usuario confirmó visualmente sobre el publicado.

---

## C# rediseño Módulo 1, adopción WPF-UI paso 1: CheckBox estilizados

A partir de `15_adopcion_paso1_checkbox.txt`, sobre la fundación WPF-UI + dark-only + fix de
ComboBox ya commiteados. Alcance estricto: solo `CheckBox` de selección — ni botones
(`BtnMain`/`BtnSec`/`BtnNav`/`BtnToggleOn`/`BtnToggleOff`) ni el modelo de interacción
(selección múltiple + botón "Aplicar") se tocaron.

**Discrepancia con el prompt, verificada contra el repo real antes de tocar nada** (regla del
proyecto: los "HECHOS DEL CÓDIGO REAL" del prompt son para verificar, no para asumir): el
prompt daba por sentado que los 79 `CheckBox` eran default (pintados por el estilo implícito
de WPF-UI, "no hay estilos custom que desmontar"). Falso: `MainWindow.xaml` ya tenía un
`<Style TargetType="CheckBox">` **implícito** (sin `x:Key`) con `ControlTemplate` propio desde
antes de la fundación WPF-UI — la misma entrada de CHANGELOG de la fundación ya lo registraba
como "preservado por diseño" (un estilo implícito en `FluentWindow.Resources`, scope más
cercano, le gana al implícito de WPF-UI mergeado en `Application.Resources`). No había nada que
"desmontar" de WPF-UI; el trabajo real fue upgradear ese `ControlTemplate` custom existente.

**Enfoque elegido** (`MainWindow.xaml`, mismo `<Style TargetType="CheckBox">` sin `x:Key`,
líneas ~156-217): se mantuvo **implícito a propósito** — es la opción de menor riesgo posible,
porque se aplica automáticamente a las 79 casillas sin tocar ninguna de sus 79 declaraciones
(ninguna tiene `Style` local que le gane). Cambios visuales sobre el `ControlTemplate`:
- Caja de 14x14 a 16x16, `CornerRadius` de 3 fijo a `{StaticResource RadiusSm}` (4, token
  compartido) — más redondeada, más cerca de la convención Fluent/WinUI que sigue WPF-UI.
- Estado marcado: de "caja oscura + trazo de acento" a **relleno solido de acento** con
  checkmark blanco/oscuro (`#0D0D0D`, el mismo tono que usa `BtnMain` para texto sobre fondo de
  acento — reuso de una convención de color ya establecida) — es el look Fluent/WinUI real que
  sigue WPF-UI (casilla-pastilla rellena, no un contorno).
- Transiciones de color animadas (fondo, borde y fade-in del checkmark) reusando el patrón y el
  token `DurFast` (0.13s) que ya usan `BtnMain`/`BtnSec` — mismo lenguaje de micro-interacción
  ya establecido en el proyecto, antes ausente en el CheckBox (los triggers eran swaps
  instantáneos sin animar).
- Lección del ComboBox aplicada: los pinceles del check (`chkBg`, `chkBrd`) son
  `SolidColorBrush` con nombre, sin congelar, targeteados por `Storyboard.TargetName` (igual
  que `bgMain`/`bgSec`/`bdSec` de los botones) — **no** por `Setter.TargetName` directo: se
  probó y WPF no resuelve `Setter.TargetName` contra un `Freezable` con nombre (error de build
  `MC4111`, "no se puede encontrar el destino"), solo `Storyboard.TargetName` lo soporta. Los 3
  triggers (`IsChecked`, hover, `IsEnabled`) usan `Storyboard`/`ColorAnimation` por esto.
- Bug de diseño encontrado y corregido antes de que llegara a build: si el trigger de hover
  hubiera estado activo también con la casilla marcada, competiría por la misma propiedad
  `Color` con la animación (sostenida via `FillBehavior.HoldEnd`) del trigger de `IsChecked` —
  al sacar el mouse de una casilla marcada, el hover-exit la hubiera dejado con el borde gris
  de "sin marcar" en vez de acento. Fix: el trigger de hover es un `MultiTrigger` con condición
  extra `IsChecked="False"`, así nunca está activo al mismo tiempo que el de `IsChecked="True"`
  — sin carrera entre animaciones, sin necesidad de la `MultiTrigger` combinada
  checked+hover que tenía el diseño anterior.
- Ningún `CheckBox` de las 79 declaraciones se tocó: `Content`, `IsChecked` (defaults
  `True`/`False` actuales), `x:Name`, `Margin` y los `ToolTip` embebidos (incluidos los
  `Foreground="#EF4444"` de impacto alto, ej. `chkEventLogs`) quedan exactamente iguales — se
  verificó con `grep` que ningún `<CheckBox>` tiene `Style` local (nada puede pisarle el
  implícito) y que el contenido de `chkEventLogs` no cambió una letra.
- Único caso especial encontrado: `chkMaintTRIM` es la única casilla que el code-behind
  deshabilita en runtime (`MainWindow.xaml.cs`, `UpdateMaintUIAsync` — no hay SSD), y siempre
  lo hace junto con `IsChecked = false` en la misma línea, así que el combo
  marcado+deshabilitado (que competiría de forma similar al bug de hover de arriba) no ocurre
  nunca en la práctica; no se agregó manejo extra para un caso que no existe en el código real.

**Verificación — sobre el PUBLICADO**:
- `dotnet build`: 0 errores, 0 advertencias (incluyendo el intento fallido con `Setter.TargetName`
  que primero tiró `MC4111`, corregido antes de continuar).
- `src-csharp\Publish-CSharp.ps1 -SkipInstaller`: publish OK, single-file real (70.9 MB).
- **Corrida real del .exe publicado**, capturas `PrintWindow` + UI Automation: confirmado en
  tab Optimizar (categorías "Limpieza de archivos", "Sistema y rendimiento", "Privacidad y
  telemetria" — checkmark blanco sobre pastilla de acento, cajas vacías consistentes para las
  desmarcadas, sin recorte ni grillas descolocadas) y en tab Bloatware (CheckBox dentro de la
  fila del listado, mismo estilo, sin romper el layout de la grilla). Funcional: "Seleccionar
  todo"/"Deseleccionar" siguen tildando/destildando las 79 casillas correctamente, incluida la
  exclusión de `chkEventLogs` de "Seleccionar todo" (contador de acciones se actualiza acorde).
  Tooltips: contenido verificado igual en el XAML (no se tocó ninguna declaración); no se pudo
  confirmar visualmente el popup en la captura automatizada porque `PrintWindow` no incluye
  ventanas de popup superpuestas (limitación de la herramienta de captura, no del cambio). El
  usuario hará la confirmación visual final de los tooltips y del resto de pantallas
  (Mantenimiento, Red, Ajustes) — .exe en
  `src-csharp\WinBoost\bin\publish\win-x64\WinBoost.exe`.

No se marcó ningún item de `docs/PENDIENTES.md` (el rediseño del Módulo 1 avanza por pasos, se
marca cuando el conjunto esté completo). Botones y demás controles quedan para pasos
posteriores de adopción.

---

## C# dark-only + fix de los ComboBox recortados por WPF-UI

A partir de `14_darkonly_y_fix_dropdowns.txt`, siguiendo a la fundación WPF-UI. Dos cambios
independientes sobre lo que dejó esa integración: (1) degradar el tema claro (decisión de
producto: WinBoost pasa a dark-only) y (2) corregir los ComboBox que WPF-UI recortaba en el
publicado.

**PARTE 1 — Dark-only (`Services/SettingsService.cs`, `MainWindow.xaml`,
`MainWindow.xaml.cs`)**

- `SettingsService.ApplyTheme`: se eliminaron la rama `"light"` (paleta clara) y la resolución
  `"auto"` (leía `AppsUseLightTheme` del registro de Windows). El método ahora aplica siempre
  la paleta oscura (mismos valores hex de antes: `BrushAppBg` `#0D0D0D`, `BrushCard` `#161616`,
  etc.) y fija `ApplicationThemeManager.Apply(..., ApplicationTheme.Dark, ...)` de WPF-UI sin
  condicional — WPF-UI queda fijo en oscuro sin ninguna rama que pueda resolver a claro.
- `MainWindow.xaml` (card "Tema de la aplicacion", tab Ajustes): el `ComboBox cboTheme` pasó de
  3 opciones (Oscuro/Claro/Automatico) a una sola (`"Oscuro"`), con `IsEnabled="False"` y el
  subtitulo cambiado a "Mas temas proximamente" — mismo patrón ya usado por el item "Idioma" de
  la misma card (deshabilitado, un solo valor real, comunica "existe, viene despues" sin
  prometer nada). No se tocó el layout de la card.
- `MainWindow.xaml.cs` (`WireSettingsControls`): se quitó el bloque que fijaba
  `cboTheme.SelectedIndex` desde `Current.Theme` y el `SelectionChanged` que reescribía
  `Current.Theme`/llamaba `ApplyTheme`/guardaba settings — el combo ya no puede disparar
  cambios (`IsEnabled="False"`), no hace falta handler.
- `AppSettings.Theme`: se dejó el campo tal cual (no se removió del modelo). Camino elegido:
  compatibilidad de lectura de `settings.json` viejos (instalaciones previas al dark-only
  pueden tener `"light"`/`"auto"` grabado) sin que tenga ningún efecto — `ApplyTheme` ya no lo
  lee. Se prefirió esto a remover el campo por ser el cambio de menor riesgo (deserializar un
  campo desconocido con `System.Text.Json` no rompe nada, pero remover una propiedad que
  settings.json viejos SI tienen podria interactuar mal con el resto del loader si algun dia se
  vuelve a leer).
- Verificado que ningun control referencia un brush que solo existiera en la rama light: las
  keys del diccionario (`BrushAppBg`, `BrushSidebar`, `BrushCard`, `BrushDeep`, `BrushElev`,
  `BrushCtrl`, `BrushBorder`, `BrushFg1/2`, `BrushFgMuted`, `BrushFgDim`) son las mismas en
  ambas ramas, ahora solo queda la oscura.
- Nota de arquitectura (no implementada, solo no cerrada la puerta): el `AccentColor` ya vive
  centralizado en `App.xaml`, asi que variantes dark con distinto acento a futuro no requieren
  tocar `ApplyTheme` de nuevo.

**PARTE 2 — Fix de los ComboBox recortados (`MainWindow.xaml`, estilo `ComboDark`)**

Diagnóstico (no se parcheó a ciegas): el síntoma reportado — primer caracter del texto del
ComboBox tapado por una franja angosta — se reprodujo visualmente sobre el .exe publicado
(capturas `PrintWindow` reales, no una hipótesis) en varios ComboBox de distintos tabs
(`cboPrio` en Tuning Avanzado, `cboDNSProvider` en Optimizar). En los tres casos se veía la
misma forma: un "pill" redondeado de ~24px de ancho (el fondo/borde del control) superpuesto
sobre el arranque del texto, mientras el texto en sí (mucho más ancho) se renderizaba completo
por fuera de ese fondo — es decir, no era el texto el que se recortaba, era el CHROME (fondo +
borde + flecha) del ComboBox el que colapsaba a un ancho mínimo.

Causa raíz confirmada leyendo el `ControlTemplate` de `ComboDark` (`MainWindow.xaml`, dentro de
`FluentWindow.Resources`): el `ToggleButton x:Name="tgl"` que da el fondo/borde al control tiene
un `ToggleButton.Template` local (por eso su aspecto visual — Border redondeado, flecha — nunca
cambió), pero NO tenía ningún `Style` local asignado. Antes de WPF-UI, sin ningún `Style`
implícito de `ToggleButton` en scope, el `ToggleButton` usaba el default de WPF
(`HorizontalAlignment="Stretch"` por herencia de `FrameworkElement`) y ocupaba todo el ancho del
`ComboBox`. Con la fundación WPF-UI, `ui:ControlsDictionary` (mergeado en
`Application.Resources`) aporta un `Style` implícito para `ToggleButton` sin `x:Key` — al no
haber ningún `Style` implícito de `ToggleButton` más cercano en `FluentWindow.Resources` que lo
tape, ese estilo de WPF-UI pasó a aplicarse a `tgl`. Ese estilo fija (entre otras cosas)
`HorizontalAlignment="Left"`, que rompe el layout por una razón específica de WPF: el
`ToggleButton.Template` interno tiene un `Grid` con columnas `*`/`24` (la `*` para el fondo, la
`24` para la flecha) sin ningún otro elemento que fuerce un ancho — cuando un `FrameworkElement`
dentro de una celda de `Grid` sin columnas propias pasa de `Stretch` a `Left`, WPF lo mide con
ancho disponible infinito, y en esa pasada las columnas `*` de su contenido se miden como si
valieran `0` (las `*` solo reciben ancho real en el paso de `Arrange`, no en `Measure`) — el
`ToggleButton` termina con un ancho "auto" de exactamente los 24px de la columna de la flecha,
que es el pill angosto observado. El `TextBlock x:Name="cp"` (el texto del valor seleccionado)
no tiene este problema porque es hermano del `ToggleButton` en el `Grid` externo y sigue
alineado `Left` con `Margin` fijo — por eso el texto se veía completo y solo el fondo quedaba
recortado.

Se descartó la hipótesis de un `Padding`/`MinWidth` distinto en el estilo de WPF-UI (la causa
real es de alineación + colapso de columnas `*`, no de tamaño mínimo) y la de que el `ComboBox`
en sí se hubiera achicado (su `ActualWidth` es el mismo de siempre — columna `*`/`Width` fijo
según la instancia — solo el `ToggleButton` interno colapsaba).

**Fix aplicado** (consistente: un solo cambio en el `ControlTemplate` compartido de
`ComboDark`, no parches de ancho por instancia): al `ToggleButton x:Name="tgl"` se le agregó
`Style="{x:Null}"` (lo desconecta de cualquier estilo implícito, presente o futuro, de
`ToggleButton` que aporte cualquier librería mergeada) más `HorizontalAlignment="Stretch"
VerticalAlignment="Stretch"` como valores locales — un valor local siempre gana sobre cualquier
`Style`, sea implícito o explícito, así que esto queda blindado independientemente de qué haga
WPF-UI en el futuro. Como todos los `ComboBox` de la app comparten el mismo `Style
x:Key="ComboDark"`, el fix corrige los ~11 ComboBox de una sola vez (Ajustes, DNS, Mantenimiento,
Bloatware, Tuning, etc.).

**Verificación — sobre el PUBLICADO**:
- `dotnet build`: 0 errores, 0 advertencias (build limpio antes y después de cada cambio).
- `src-csharp\Publish-CSharp.ps1 -SkipInstaller`: publish OK, single-file real (70.9 MB, sin
  dependencias sueltas).
- **Corrida real del .exe publicado** con capturas `PrintWindow` directas de la ventana (no
  screenshot de escritorio): confirmado ANTES/DESPUÉS sobre `cboPrio` (tab Tuning Avanzado,
  "Responsividad (0x24) - prioridad al proceso activo") — antes, el pill de ~24px tapaba la
  "R" inicial con el resto del texto renderizado sin fondo; después, el control se ve como un
  campo completo con borde, fondo y flecha ocupando todo el ancho de la columna, sin recorte.
  Confirmado también sobre `cboDNSProvider` (tab Optimizar, "Cloudflare -- 1.1.1.1 / 1.0.0.1")
  y `cboBackupRetention` (tab Ajustes, "7 dias") — mismo resultado, control completo sin
  recorte. Falta la confirmación visual final del usuario sobre el resto de las pantallas
  (Mantenimiento, Bloatware) y sobre el selector de tema fijo/deshabilitado en Ajustes; el
  fix es al `ControlTemplate` compartido, no por instancia, así que el mismo mecanismo aplica
  a todas por igual. El .exe queda en
  `src-csharp\WinBoost\bin\publish\win-x64\WinBoost.exe`.

Nota: a futuro se evaluarán variantes dark con distinto acento sobre este dark-only (no
implementado en esta pasada).

---

## C# fundación WPF-UI: integrada al producto real (MainWindow → FluentWindow), paridad funcional/visual preservada

A partir de `13_fundacion_wpfui.txt`, siguiendo el veredicto GO condicionado del spike (ver
entradas de abajo). Primera integración de WPF-UI en `src-csharp/WinBoost` (no en el spike
descartable). Deliberadamente conservador: solo el paquete + el chrome de la ventana + el
theming de marca sobre la librería. NO se agregó el sidebar (`NavigationView`), NO se cambió
la navegación por tabs, NO se rediseñó ninguna pantalla — eso queda para los prompts
siguientes del Módulo 1, uno por vez.

**Archivos modificados**
- `src-csharp/WinBoost/WinBoost.csproj` — `PackageReference` a `WPF-UI 4.3.0` (misma versión
  validada en el spike).
- `src-csharp/WinBoost/App.xaml` — `Application.Resources` pasó de lista plana a
  `ResourceDictionary` con `ResourceDictionary.MergedDictionaries` (`ui:ThemesDictionary
  Theme="Dark"` + `ui:ControlsDictionary`) mergeados PRIMERO, seguidos de los tokens propios
  de WinBoost (`AccentColor`, `Brush*`, `Font*`, `Space*`, `Radius*`, `DurFast`) sin tocar:
  una `ResourceDictionary` siempre resuelve sus entradas directas antes que las de sus
  `MergedDictionaries`, así que los tokens propios ganan por diseño sin necesidad de reordenar
  nada.
- `src-csharp/WinBoost/App.xaml.cs` — en `OnStartup`, antes de cualquier rama (silencioso o
  UI): `ApplicationThemeManager.Apply(ApplicationTheme.Dark, WindowBackdropType.None,
  updateAccent: false)` + `ApplicationAccentColorManager.Apply(#00C8FF, ApplicationTheme.Dark)`
  — fija el acento de marca antes de que WPF-UI lo pise con el accent de Windows.
- `src-csharp/WinBoost/MainWindow.xaml` — root `<Window>` → `<ui:FluentWindow
  ExtendsContentIntoTitleBar="True">` (mismo flag que el spike, ya validado). Se agregó una
  fila `Auto` nueva arriba con `<ui:TitleBar Title="WinBoost"/>` como chrome de reemplazo (ver
  "Por qué el TitleBar no es opcional" abajo); el `<Grid>` de contenido original (4 filas: TOP
  BAR de marca propia, sidebar+tabs, barra de progreso, footer) pasó a ser la fila `*` de
  abajo, sin tocar ni una línea de su contenido. `Window.Resources` → `FluentWindow.Resources`
  (obligatorio: el nombre del property-element XAML tiene que matchear el tag del root).
- `src-csharp/WinBoost/MainWindow.xaml.cs` — clase base `: Window` → `:
  Wpf.Ui.Controls.FluentWindow` (totalmente calificado, SIN `using Wpf.Ui.Controls;` — ver
  "Namespace clash evitado" abajo).
- `src-csharp/WinBoost/Services/SettingsService.cs` (`ApplyTheme`) — al final, después de
  aplicar la paleta de brushes propia de WinBoost, reconcilia el tema de WPF-UI con el switch
  claro/oscuro de la app: `ApplicationThemeManager.Apply(Light/Dark según `theme`,
  WindowBackdropType.None, updateAccent: false)`. Sin esto, los controles con estilo implícito
  de WPF-UI (ver abajo) se hubieran quedado fijos en oscuro aunque el usuario cambiara el tema
  de WinBoost a claro.

**Por qué el `ui:TitleBar` NO es opcional (verificado en el código fuente de WPF-UI 4.3.0, no
asumido)**: la intención inicial era la migración más conservadora posible — `FluentWindow`
sin `ExtendsContentIntoTitleBar` ni `TitleBar`, para no tocar el chrome en absoluto. Se
verificó en el `Wpf.Ui.dll`/fuente de `FluentWindow.cs` que esto es inviable:
`FluentWindow.SetWindowChrome()` aplica SIEMPRE (con o sin `ExtendsContentIntoTitleBar`,
incluso con `WindowBackdropType.None`) `WindowChrome` con `CaptionHeight = 0` y
`UseAeroCaptionButtons = false` — el titlebar nativo (ícono, texto, minimizar/maximizar/cerrar)
queda inerte apenas la clase hereda de `FluentWindow`, no es un efecto de `Mica` ni de extender
contenido. Sin un `ui:TitleBar` (u otro reemplazo) la ventana queda sin forma de
mover/minimizar/maximizar/cerrar. Se agregó como fila `Auto` propia, separada del "TOP BAR" de
marca (logo/versión/badges/salud) que ya existía como CONTENIDO — quedan dos barras apiladas
(chrome Fluent arriba, marca propia abajo), consistente con "el chrome puede cambiar, el
contenido no".

**Namespace clash evitado**: `Wpf.Ui.Controls` redefine versiones propias de casi todos los
controles WPF estándar que este archivo usa sin calificar (`Button`, `CheckBox`, `ComboBox`,
`TextBox`, `ProgressBar`, `ListBox`, etc. — confirmado contra el listado real de carpetas de
`src/Wpf.Ui/Controls` del repo de la librería). Un `using Wpf.Ui.Controls;` a nivel de archivo
en `MainWindow.xaml.cs` hubiera vuelto ambiguas decenas de referencias existentes (`Button[]
_navButtons`, `Dictionary<int, CheckBox>`, etc. — error CS0104). Se evitó agregando el using y
calificando `FluentWindow` completo (`Wpf.Ui.Controls.FluentWindow`) solo en la declaración de
la clase.

**Auditoría de paridad visual (item 5 del prompt) — qué controles reestiló WPF-UI y cómo se
resolvió**, verificado leyendo cada XAML de `src-csharp/WinBoost/` (no asumido) y confirmando
contra el código fuente real de `Wpf.Ui.Controls.*` (ej. `CheckBox.xaml` del paquete 4.3.0
tiene un estilo `x:Key="DefaultCheckBoxStyle"` + una `<Style TargetType="{x:Type CheckBox}"
BasedOn="{StaticResource DefaultCheckBoxStyle}"/>` implícita — mismo patrón para
ComboBox/TextBox/ProgressBar/RichTextBox/ScrollBar/etc.):
- **Preservados sin cambio (por diseño, no por override nuevo)**: `CheckBox`, `TabItem`,
  `ProgressBar` y `ScrollBar` ya tenían un `<Style TargetType="...">` implícito (sin `x:Key`)
  declarado en `MainWindow.xaml` → `Window.Resources` (ahora `FluentWindow.Resources`). La
  resolución de recursos de WPF busca primero en el scope más cercano al elemento (recursos de
  la ventana) antes que en `Application.Resources` (donde quedaron los diccionarios de
  WPF-UI), así que estos 4 tipos siguen usando el estilo propio de WinBoost sin que haga falta
  ningún cambio adicional. `ComboBox` (`ComboDark`) y `TextBox` (`TxtDark`) ya usaban un
  `Style="{StaticResource ...}"` explícito en las 10 + 1 instancias del archivo — un `Style`
  asignado localmente siempre gana sobre cualquier estilo implícito, sin importar el scope.
  `Button` está 100% cubierto: las 56 instancias reales de `<Button>` en `MainWindow.xaml`
  (auditadas una por una) asignan `Style` o `Template` local (`BtnMain`/`BtnSec`/`BtnPreset`/
  `BtnDanger`/`BtnNav`/`BtnNavActive`/`BtnNavLicense`/`BtnErrBadge`, o un `Button.Template`
  inline para `btnTrialUpgrade`) — cero riesgo de reestilo implícito.
- **Expuestos a WPF-UI pero sin impacto visual observado**: `RichTextBox` (`rtbLog` en
  Consola, `rtbRestoreLog` en Historial) no tiene protección local ni de WinBoost ni de
  WPF-UI para ese tipo — pero `Background`, `BorderThickness="0"` y `Padding` están fijados
  como valores locales en el propio elemento, que ganan sobre cualquier `Template` del estilo
  implícito. Verificado sobre el publicado: la Consola se ve igual que antes.
- **Reestilo de WPF-UI aceptado (bajo riesgo, confinado)**: los 5 diálogos secundarios
  (`CompareDialog`, `ConfirmOptimizationDialog`, `FinishOptimizationDialog`,
  `OnboardingDialog`, `ChangelogDialog`) son `<Window>` propios sin el override local de
  `ScrollBar` que sí tiene `MainWindow`; sus `ScrollViewer` van a tomar el scrollbar delgado
  estilo Fluent de WPF-UI en vez del scrollbar gris por defecto de Windows. Cambio menor,
  confinado a esos diálogos, no evaluado como negativo — queda a criterio del usuario si se
  homologa a mismo trato en un pase posterior.
- **`TextBlock`**: confirmado en el código fuente que el estilo implícito de WPF-UI para
  `TextBlock` está vacío (`<Style TargetType="{x:Type TextBlock}" />`, sin setters) — cero
  riesgo pese a los cientos de `TextBlock` sin `Style` explícito en toda la app.
- **Corner rounding automático**: `FluentWindow.WindowCornerPreference` por defecto es
  `Round` (aplicado automáticamente en `OnSourceInitialized`, no hace falta setearlo) — la
  ventana ahora tiene esquinas superiores redondeadas estilo Windows 11. Es un cambio de
  chrome, no de contenido; se dejó el default en vez de forzar `DoNotRound` porque es
  consistente con la dirección "premium" del Módulo 1 y no afecta el contenido.
- **NO se habilitó Mica** (`WindowBackdropType` se dejó en `None` explícito, a diferencia del
  spike que usó `Mica` solo para la evaluación): mantiene el fondo solido
  `{DynamicResource BrushAppBg}` sin cambios, evita el riesgo de Mica no confirmado
  visualmente en Windows 10 real (ver limitación abierta en el spike), y respeta el "NO
  rediseño" del prompt. Queda como decisión disponible para un pase de rediseño posterior del
  Módulo 1.

**Verificación — sobre el PUBLICADO, no solo Debug** (regla del proyecto):
- `dotnet build`: 0 errores, 0 advertencias.
- `src-csharp/Publish-CSharp.ps1 -SkipInstaller`: publish OK, single-file real sin
  dependencias sueltas (bundle check del script). **70.9 MB** (vs. 68.6 MB de la build previa
  sin WPF-UI — overhead ~2.3 MB, consistente con los ~2.4 MB medidos en el spike).
- **Corrida real del `.exe` publicado** (elevado, esta máquina de desarrollo ya corría como
  Administrador): arrancó sin `FileNotFoundException` ni recurso faltante (el tipo de bug que
  motivó la regla de validar sobre publicado — ver entradas de `System.Text.RegularExpressions`
  más abajo), proceso responsive, título de ventana `"WinBoost v4.2"`. Capturas directas de la
  ventana (`PrintWindow`, no screenshot de escritorio — evita falsos negativos por ventanas
  superpuestas) confirmaron visualmente: `ui:TitleBar` con minimizar/maximizar/cerrar estilo
  Fluent + esquinas redondeadas arriba, el "TOP BAR" de marca (logo, v4.2, badge PRO, SALUD
  87%, Windows 10 Pro) intacto debajo, sidebar de 10 tabs intacto, navegación entre tabs
  (`Herramientas`, `Licencia`) funcionando vía UI Automation sin crashear el proceso, y
  contenido de cada tab pixel-a-pixel consistente con el diseño original: `CheckBox` con el
  glyph propio (no el de WPF-UI), botones primarios/secundarios/danger con sus colores y
  radios de siempre, `TextBox` del HWID con el estilo `TxtDark`. Falta la confirmación visual
  del usuario en su propia máquina (y en Windows 10, no solo Windows 10 Pro de esta VM/PC de
  desarrollo) antes de dar el paso por cerrado para producción.

**No se marcó ningún item de `docs/PENDIENTES.md`** (el item 1 del Módulo 1 — sidebar — no se
tocó en este paso, sigue `[ ]`). Esta fundación es un precursor del Módulo 1, no uno de sus
items.

---

## Spike WPF-UI: resuelto el crash de navegación (ContentDialogHost por página)

A partir de `12_fix_crash_navegacion_spike.txt`. Fix aplicado al spike de evaluación
(`spike/WpfUiSpike/`): el `ContentDialogHost` pasó de vivir en `DashboardPage` a ser único a nivel
`MainWindow` (patrón que WPF-UI espera y que se replicará al integrar en WinBoost), eliminando el
choque de registro que crasheaba al volver a "Optimizar". Validado sobre el .exe publicado (40
navegaciones sin crash). Se sacó la instrumentación de logging de navegación; se dejó a propósito
la captura global de excepciones. Detalle y aprendizajes para la integración en
`spike/WpfUiSpike/README.md`.

---

## Spike WPF-UI: diagnóstico del crash de navegación (sin fix aplicado)

A partir de `11_diag_crash_navegacion_spike.txt`. Se agregó captura global de excepciones +
logging de navegación al spike de evaluación (`spike/WpfUiSpike/`) para diagnosticar el crash al
cambiar de sección reportado sobre el publicado; causa raíz encontrada y reproducida (choque de
`ContentDialogHost` al recrearse `DashboardPage` en cada navegación). Solo diagnóstico, detalle en
`spike/WpfUiSpike/README.md`.

---

## Spike: evaluación de WPF-UI (lepoco/wpfui) para el rediseño

A partir de `10_spike_wpfui.txt`. Proyecto aislado y descartable en `spike/WpfUiSpike/` (no toca
`src-csharp/WinBoost`), evaluando `NavigationView`/`ToggleSwitch`/`Card`/`ContentDialog` con la
marca de WinBoost aplicada, verificado sobre el .exe publicado self-contained single-file. Veredicto
GO condicionado (marca conforme, overhead ~2.4 MB, publicado sin `FileNotFoundException`; riesgo
abierto de íconos faltantes en Win10 según el símbolo). Detalle completo en `spike/WpfUiSpike/README.md`.

---

## Documentacion: corregidas en README.md tres features desactualizadas y sincronizado el item 2.5 de PENDIENTES.md

A partir de `8_corregir_readme_y_2_5.txt`, siguiendo a la sync anterior. Verificado cada
reemplazo contra el CHANGELOG real (no se asumio la redaccion sugerida por el prompt) antes de
escribir.

**`README.md` (seccion Herramientas):**
- "Analisis de espacio en disco: top 10 carpetas mas pesadas..." -> "Espacio en disco: vista de
  discos del equipo con barra usado/libre por unidad, estilo Windows" (la entrada "C# Info sistema
  — panel de espacio en disco: de 'top 10 carpetas' a vista de discos" confirma el reemplazo real:
  `PopulateDiskPanel` sobre `DriveInfo.GetDrives()`, ya no hay scan de carpetas).
- "Benchmark rapido de disco" — eliminado del README. La entrada "C# Fixes... + benchmark
  descartado" confirma que nunca se migro (CrystalDiskMark cubre el caso) y el cuadrante quedo
  oculto (`Visibility="Collapsed"`) en la tab Herramientas; `docs/PENDIENTES.md` ya lo tenia en
  "Descartado / No implementar".
- "Dispositivos con problemas y inventario de drivers con filtro por clase" -> "Dispositivos con
  problemas (Win32_PnPEntity con error de configuracion)". La entrada "C# Herramientas — removido
  el inventario de drivers" confirma que el inventario se removio por decision de producto y que
  Dispositivos con problemas se conserva intacto.
- No se toco "Limpieza del Driver Store: detecta duplicados obsoletos..." (feature distinta del
  inventario de drivers eliminado; se verifico que sigue presente en `TuningService.cs` /
  `MainWindow.xaml(.cs)` antes de dejarla).

**`docs/PENDIENTES.md`:** item 2.5 pasa de `[x]` entero a `[~]`, misma convencion que 4.4:
inventario de drivers implementado y luego removido (no activo), "Dispositivos con problemas" se
conserva y sigue vigente.

**Cotejo adicional:** se repaso el resto del CHANGELOG buscando otras remociones/descartes
(`removido`/`eliminado`/`descartado`) que pudieran afectar afirmaciones de Score, Bloatware,
Mantenimiento, Reporte HTML, CLI o Licencias en el README — no se encontro ninguna otra
desincronizacion en esta pasada.

---

## Documentacion: sincronizado PENDIENTES.md tras el corte 6.3 (item 4.4 y nota obsoleta del 6.3)

A partir de `7_sync_pendientes_post_corte.txt`. Cotejados los checkboxes de `docs/PENDIENTES.md`
contra `docs/CHANGELOG.md` real antes de editar.

- **Item 4.4 (Game Focus Mode):** estaba `[x]` a secas, lo cual era enganoso — el CHANGELOG tiene
  una entrada posterior ("C# Game Focus Mode dado de baja...") que registra su remocion completa
  (decision de producto: afinidad a nucleos fisicos sin impacto medible, Process Lasso cubre el
  nicho). Se cambio a `[~]` con el detalle de que fue implementado y luego removido, que no esta
  activo en la app actual, y que el reemplazo (deteccion Steam + prioridad por juego) queda
  pendiente post-migracion.
- **Nota del item 6.3:** ya habia sido corregida en el corte mismo (sesion anterior) para no
  confundir 6.3 como pendiente — aclara que "code signing" sigue bloqueando la DISTRIBUCION, no
  el corte (que ya esta hecho). No hizo falta editarla de nuevo.

**Otras desincronizaciones encontradas al cotejar (reportadas, NO corregidas — fuera del alcance
declarado de este prompt, que pedia tocar solo las dos zonas de arriba):**
- Item 2.5 ("Dispositivos con problemas + inventario de drivers") sigue `[x]` entero, pero una
  entrada del CHANGELOG ("C# Herramientas — removido el inventario de drivers") registra que el
  inventario de drivers se removio por decision de producto (sin valor accionable frente a
  GeForce Experience/Adrenalin/Windows Update); "Dispositivos con problemas" si se conserva
  intacto. El `[x]` de 2.5 hoy afirma como vigentes dos cosas de las que solo una lo esta.
- `README.md` (raiz, reescrito en el corte 6.3) tiene al menos tres afirmaciones de producto que
  ya no son ciertas para el C# actual, ninguna tocada en el corte porque no eran evidentes sin
  cotejar contra el CHANGELOG completo:
  - "Dispositivos con problemas y inventario de drivers con filtro por clase" — mismo caso que
    2.5, el inventario ya no existe.
  - "Analisis de espacio en disco: top 10 carpetas mas pesadas con barras proporcionales (async)"
    — la entrada "C# Info sistema — panel de espacio en disco: de 'top 10 carpetas' a vista de
    discos" registra que se reemplazo por una vista de discos usado/libre estilo Windows; ya no
    lista carpetas.
  - "Benchmark rapido de disco" — la entrada "C# Fixes... + benchmark descartado" registra que
    nunca se migro (CrystalDiskMark ya cubre el caso) y el cuadrante quedo oculto
    (`Visibility="Collapsed"`) en Herramientas. `docs/PENDIENTES.md` ya lo tenia bien clasificado
    en "Descartado / No implementar"; el README no reflejaba ese descarte.

Estas quedan para una pasada de sync separada (README + PENDIENTES 2.5) si el usuario la pide.

---

## Corte 6.3: migracion PS1 -> C# cerrada, C# como unica version oficial, PS1 jubilado a legacy/

A partir de `6_corte_6_3.txt`. Ultimo item de la migracion a C#/WPF (`docs/PENDIENTES.md`,
FASE 6). WinBoost C#/.NET 8 WPF (`src-csharp/`) pasa a ser la UNICA version oficial y
distribuida; el `.ps1` legacy (`OptimizarPC_App.ps1` + `OptimizarPC_UI.xaml` + su cadena de
build) queda descontinuado.

**Diagnostico previo (solo lectura, antes de mover nada):**
- Sin acople real entre la distribucion C# y el PS1: `src-csharp/Publish-CSharp.ps1` y
  `src-csharp/installer/WinBoost.iss` resuelven todas sus rutas dentro de `src-csharp/`. La
  unica referencia cruzada de `OptimizarPC_UI.xaml` en el instalador C# es en `[UninstallDelete]`
  (borra el archivo huerfano que dejaba el instalador PS1 viejo en `{app}` del usuario) — no es
  una dependencia de build sobre el archivo del repo.
- `WinBoost.ico` es un asset COMPARTIDO: `src-csharp/WinBoost/WinBoost.csproj`
  (`ApplicationIcon`) y `src-csharp/installer/WinBoost.iss` (`SetupIconFile`) lo referencian como
  `..\..\WinBoost.ico` / `..\..\WinBoost.ico` relativo a la raiz del repo. Se dejo en la raiz,
  NO se movio a `legacy/`. `Create-Icon.ps1` (genera ese .ico) tampoco depende del PS1, asi que
  tambien se dejo en la raiz.
- El XAML del C# (`src-csharp/WinBoost/MainWindow.xaml`, 2645 lineas) ya diverge del XAML legacy
  (`OptimizarPC_UI.xaml`, 2551 lineas) y no hay ningun `Link`/copia en el `.csproj` — dejaron de
  compartirse en algun punto anterior de la migracion, antes de este corte.
- Desincronizaciones encontradas y reportadas (no corregidas por fuera de este corte):
  - El item 6.3 en PENDIENTES.md decia estar "supeditado a" code signing y a la pasada de
    regresion sobre el publicado. La regresion ya se valido OK en sesiones previas; code signing
    SIGUE pendiente (item abierto en "Bloqueante de distribucion"). Se ejecuto el corte igual
    porque retirar el PS1 (y la clave RSA comprometida que lleva embebida) es independiente de la
    firma del instalador C# — no la reemplaza ni la resuelve.
  - El nodo "Pendiente" del CHANGELOG sobre `Gen-License.ps1` decia que seguia trackeado en el
    indice de git; en el estado actual del repo YA NO esta en `git ls-files` (se destrackeo en un
    commit anterior, `f1ac5a9`/"fixes pre migration c#"). Sigue existiendo en el HISTORIAL de git
    (commit `7fa247e`), asi que la evaluacion de limpieza de historial (si el repo es publico)
    sigue siendo un pendiente manual real; el `git rm --cached` en si ya no aplica.
  - PENDIENTES.md 4.4 (Game Focus Mode) esta marcado `[x]`, pero una entrada posterior de este
    mismo CHANGELOG ("C# Game Focus Mode dado de baja...") registra que la feature se removio del
    C# por decision de producto — confirmado tambien en codigo (`GameFocusService` no existe en
    `src-csharp/`). No se toco ese checkbox (fuera de alcance de este corte); se saco la seccion
    "Game Focus Mode" del README.md principal para no anunciar una feature que el C# no tiene.
  - Hallazgo nuevo de higiene de repo, no bloqueante: `.gitignore` tenia `installer/Output/`
    (ancla solo a la raiz) sin cubrir `src-csharp/installer/Output/`, que termino con instaladores
    `.exe` trackeados por accidente en git (visto en `git status`:
    `src-csharp/installer/Output/WinBoost_Setup_4.2.exe` modificado + `4.1.exe` sin trackear). Se
    corrigio el patron para adelante (ver mas abajo); destrackear los `.exe` ya versionados
    (`git rm --cached`) queda como pendiente manual del usuario, igual que la evaluacion de
    limpieza de historial.

**Ejecutado:**
- `git mv` de la cadena legacy a `legacy/`: `OptimizarPC_App.ps1`, `OptimizarPC_UI.xaml`,
  `Build.ps1`, `EJECUTAR_COMO_ADMIN.bat`, `installer/WinBoost.iss` -> `legacy/installer/`.
  `installer/Output/` (instaladores viejos, ya ignorados por git) y `dist/` (artefactos de
  `ps2exe`, ya ignorados) se movieron con `mv` a `legacy/installer/Output/` y `legacy/dist/`.
  `installer/` en la raiz quedo vacio y se elimino.
- `legacy/README.md` nuevo: marca la version PS1 como descontinuada/sin soporte, y documenta
  explicitamente el aviso de seguridad de la clave publica RSA vieja embebida (rotada por la
  filtracion de la privada via `Gen-License.ps1`) — no redistribuir ni reactivar ese codigo. Este
  aviso es el cierre formal del incidente: mientras el PS1 fuera distribuible, la clave privada
  filtrada podia seguir firmando licencias validas contra esa version.
- `.gitignore`: `dist/` -> `legacy/dist/`, `installer/Output/` -> `legacy/installer/Output/`, mas
  `src-csharp/installer/Output/` nuevo (cierra el gap de higiene encontrado en el diagnostico).
- `README.md` (raiz): reescrito para describir la app C#/.NET 8 WPF como unica version oficial.
  Nota de antivirus actualizada (ya no ps2exe/Wacatac; SmartScreen pendiente de firma). Seccion
  "Desarrollo" reemplazada por `dotnet build` + `src-csharp/Publish-CSharp.ps1`. "Estructura del
  proyecto" y "Stack tecnico" reescritos para C#. Se saco la seccion "Game Focus Mode" (feature
  dada de baja, ver arriba).
- `CLAUDE.md`: reescrito para reflejar la migracion cerrada — "Archivos del proyecto" apunta a
  `src-csharp/` como version oficial y a `legacy/` como descontinuada; se retiraron las reglas
  PS5.1 (`Get-Ctrl`/`Flush-UI`/variables `$script:`/numeracion de modulos 1A-15B), que ya no
  aplican a desarrollo activo, dejando solo un puntero a `docs/CHANGELOG.md` por si algun dia hay
  que tocar `legacy/`. Se mantuvieron "Estilo visual" (tokens de color/tipografia, siguen
  aplicando al XAML activo en C#) y "Orden de tabs", pero esta ultima se corrigio: el orden
  documentado (0=Optimizar...9=Tuning) era el del PS1 y NO coincide con el orden real de
  `SetActiveNav` en `src-csharp/WinBoost/MainWindow.xaml.cs` (0=Optimizar, 1=Herramientas,
  2=Info del sistema, 3=Arranque, 4=Bloatware, 5=Consola, 6=Historial, 7=Ajustes, 8=Licencia,
  9=Tuning) — desincronizacion real encontrada al verificar, corregida al valor actual en vez de
  copiarse a ciegas.
- `docs/PENDIENTES.md`: 6.3 marcado `[x]` con el detalle de lo movido y las notas de las
  desincronizaciones encontradas (code signing sigue abierto; ver arriba). Nota superior y titulo
  de la seccion de migracion actualizados de "TRABAJO ACTIVO" a "COMPLETA".

**Pendientes manuales del usuario (acciones de git, no ejecutadas por Claude Code):**
- Evaluar limpieza de historial de git para el contenido viejo de `Gen-License.ps1` (commits
  `7fa247e` en adelante), si el repo es publico — el `git rm --cached` en si ya no aplica (no
  esta en el indice actual).
- `git rm --cached` de los instaladores `.exe` bajo `src-csharp/installer/Output/` que quedaron
  trackeados por accidente (ver hallazgo de higiene arriba), antes de que el `.gitignore`
  corregido tenga efecto sobre lo ya versionado.

**Verificacion:** `dotnet build` sobre `src-csharp/WinBoost/WinBoost.csproj` sin tocar rutas de
`src-csharp/` (el corte no movio nada dentro de esa carpeta); `src-csharp/installer/WinBoost.iss`
y `src-csharp/Publish-CSharp.ps1` no referencian ningun path movido (confirmado por lectura,
segun el diagnostico de acople de mas arriba).

---

## Documentacion: registrado el sub-item de verificacion de firma Authenticode del instalador en el updater

A partir de `5_registrar_authenticode_updater.txt`. En la regresion del auto-updater sobre el .exe
publicado se valido OK el ciclo completo (Check, Download, gate SHA256, Apply+relaunch). Se
identifico una debilidad de SEGURIDAD de diseno (no un bug): el SHA256 y el DownloadUrl salen
ambos del mismo `version.json`, por lo que el hash no protege contra un repositorio/cuenta de
GitHub comprometidos — un atacante que modifique `version.json` cambia instalador y hash juntos, y
`ApplyUpdate` correria ese instalador en silencio y elevado. Se agrego en `docs/PENDIENTES.md`,
como sub-item dependiente del item de code signing ya existente, la verificacion de firma
Authenticode del instalador antes de `ApplyUpdate` (Services/UpdateService.cs). Solo cambio de
documentacion, sin tocar codigo.

---

## Documentacion: registradas dos debilidades de diseno del modelo de licencias halladas en la regresion sobre el publicado

A partir de `4_registrar_hallazgos_licencias.txt`. Durante la regresion de licencias sobre el .exe
publicado se valido OK la parte criptografica (firma RSA-2048, Pro atado a HWID, rechazo de claves
invalidas/HWID ajeno, persistencia tras reinicio). Se encontraron dos debilidades de DISEÑO del
modelo actual (no de la criptografia): trial sin proteccion de integridad (client-side, burlable
por fecha futura/borrado de settings/reset de fecha/atraso de reloj) y clave Tech como llave
maestra global (firma sobre la constante "WINBOOST-TECH", sin HWID, sin revocacion posible). No se
corrigen ahora — el modelo de licencias no es el definitivo, se va a redisenar antes del
lanzamiento final. Quedan documentadas en `docs/PENDIENTES.md` (nueva seccion "Modelo de licencias
(rediseño pendiente)") como pendientes abiertos, junto con una nota de la direccion tentativa del
rediseño (degradar Tech, posible tier ULTRA por encima de Pro, acortar el trial de 14 a 3-7 dias),
para que el rediseño no repita los mismos patrones. Solo cambio de documentacion, sin tocar codigo.

---

## Documentacion: PENDIENTES.md actualizado tras el cierre del bug del single-file

A partir de `3_actualizar_pendientes.txt`. Antes de editar se cotejo `docs/PENDIENTES.md`
completo contra el historial real de `docs/CHANGELOG.md`:

- **Desincronizacion detectada al momento de editar** (reportada, no corregida en silencio): el
  prompt daba por sentado que el bug del single-file ya estaba "validado sobre el .exe
  publicado", pero la entrada de CHANGELOG que cerro ese fix (`FIX_regex_singlefile.txt`) decia
  "Pendiente de validar por el usuario" — esa sesion no pudo automatizar la corrida interactiva
  con UAC. `PENDIENTES.md` se redacto en base a lo que el CHANGELOG confirmaba como hecho en ese
  momento (causa raiz + fix aplicado + build/publish limpios), sin afirmar una validacion
  interactiva que el registro todavia no respaldaba. El usuario confirmo despues, corriendo el
  `.exe` publicado, que la Optimizacion completa ya no muestra el `FileNotFoundException` — esa
  entrada de CHANGELOG se actualizo para reflejarlo (ver arriba).

**Cambios en `docs/PENDIENTES.md`:**
- Seccion "Pendientes de producto / distribucion": nueva subseccion "Resuelto" con el bug del
  single-file como item cerrado `[x]` (causa raiz + fix, referencia al detalle en CHANGELOG.md).
  No es un pendiente abierto, es historico.
- "Pre-lanzamiento": se fusionaron los dos items redundantes ("Validar la suite completa... sobre
  el publicado" + "Testing externo en Win10/Win11 limpios") en uno solo que deja explicito que el
  testing externo se hace sobre el .exe publicado, con la pasada de regresion completa
  (optimizacion, backup/restore, bloatware, licencias, updater, driver store).
- FASE 6, item 6.3 (corte del `.ps1`): sigue `[ ]` sin marcar (no esta completo). Se agrego una
  nota de que queda supeditado a code signing (ya listado como bloqueante) y a la pasada de
  regresion sobre el publicado (Pre-lanzamiento) — sin inventar dependencias nuevas.

No se reordeno ni reformateo el resto del archivo.

---

## Proceso: institucionalizada la regla de validar sobre el binario publicado, no sobre Debug

A partir de `2_regla_validar_publicado.txt`. El bug de `System.Text.RegularExpressions` en el
single-file (ver entradas anteriores) quedo oculto porque toda la validacion de cierre
(backup/restore, licencias, updater, optimizacion) se habia hecho sobre `dotnet build -c Debug`,
un artefacto distinto al que recibe el usuario. Para que no vuelva a pasar:

- **`CLAUDE.md`** (seccion "Convenciones C# (src-csharp)"): nueva regla — la validacion
  funcional de un release candidate se hace SIEMPRE sobre el .exe de
  `src-csharp/Publish-CSharp.ps1` (self-contained single-file), nunca solo sobre
  `dotnet build`/`dotnet run`. `dotnet build` solo valida que compila.
- **`docs/PENDIENTES.md`** (seccion "Pre-lanzamiento"): nuevo item de checklist para validar la
  suite completa (optimizacion, backup/restore, bloatware, licencias, auto-updater, incluyendo
  el escaneo de driver store y de bloatware por su uso de Regex) sobre el .exe publicado.

**Discrepancia con el prompt**: pedia agregar el item en `docs/PENDIENTES_LANZAMIENTO.md`, pero
ese archivo no existe en el repo — el checklist pre-lanzamiento real vive en la seccion
"Pre-lanzamiento" de `docs/PENDIENTES.md` (unico archivo de pendientes que referencia
`CLAUDE.md`). Se uso ese archivo real en vez de crear uno nuevo con el nombre del prompt.

---

## C# limpieza: removida la instrumentacion de diagnostico temporal `[diag]`

A partir de `1_remover_diag.txt`: el bug del .exe publicado (FileNotFoundException de
`System.Text.RegularExpressions` por cache de extraccion parcial de
`IncludeAllContentForSelfExtract`) ya quedo diagnosticado, resuelto y republicado, asi que se
retiro toda la instrumentacion temporal agregada durante ese diagnostico.

**Removido** (todo lo marcado `[diag]`/`// DIAG-REMOVE`):
- `OptimizationService.cs`: el bloque de identidad/SID/HKCU-probe/HandleCount al inicio de
  `RunAsync`, el log de HandleCount al final de `RunAsync`, y las marcas pre/post-backup +
  detalle de excepcion (tipo/HRESULT/stack) en `SetReg` (vuelve a su `catch` original,
  `catch { Log($"Fallo: {name}", "err"); }`). Los `using System.Runtime.InteropServices;` y
  `using System.Security.Principal;` (agregados solo para esto) se quitaron por quedar sin uso.
- `TuningService.cs`: `SetWin32PrioritySep` y `SetHagsState` vuelven a no tener try/catch propio
  (el caller en `MainWindow.xaml.cs` ya maneja la excepcion para la UI); `ScanObsoleteDriversAsync`
  vuelve a su forma original sin try/catch. Se quito `using System.Runtime.InteropServices;`
  (sin uso).
- `RegistryPrivilegeHelper.cs`: los catches de `OpenWritable` vuelven a estar vacios
  (`catch (UnauthorizedAccessException) { }` / `catch (SecurityException) { }`, son parte del
  mecanismo real de fallback, no del diagnostico); se quito el log de entrada de
  `EnsureWritableAcl` y el detalle extra en su catch (el log original
  "No se pudo tomar ownership..." se mantiene, no es diag). Se quito
  `using System.Runtime.InteropServices;` (sin uso).
- `NativeMethods.cs`: `EnablePrivilege` vuelve a su forma original (ya no captura ni loguea
  `GetLastWin32Error()`/`ERROR_NOT_ALL_ASSIGNED`).

**NO se toco** (no era instrumentacion): el fix real del bug single-file
(`IncludeAllContentForSelfExtract=false` en el pubxml, `SanitizeFileName` sin Regex en
`BackupService.SaveRegBackup`), y el wrapping `Safe`/`SafeD` por paso en
`OptimizationService.RunAsync` (manejo de errores legitimo, no diagnostico).

Busqueda final de `[diag]`/`DIAG-REMOVE` en `src-csharp/`: 0 ocurrencias.

`dotnet build` y `dotnet build --no-incremental`: 0 errores, 0 advertencias.

---

## C# fix: el .exe publicado (single-file) fallaba TODAS las escrituras de registro y el backup del plan de energia con FileNotFoundException de System.Text.RegularExpressions

Investigado a partir de `FIX_regex_singlefile.txt`. El bug NO se veia en `dotnet build -c Debug`
(sin single-file); era exclusivo del artefacto publicado
(`src-csharp/Publish-CSharp.ps1` / profile `win-x64-selfcontained.pubxml`).

**Causa raiz de packaging (Frente 1) — CONFIRMADA con evidencia directa, no solo hipotesis:**
- `PublishTrimmed`/`TrimMode` estan vacios en todo el arbol (no hay `Directory.Build.props`,
  `.targets` ni `Directory.Packages.props` en ningun lado, y
  `dotnet publish ... -getProperty:PublishTrimmed` devuelve vacio) — se descarta el trimming.
- Se confirmo con evidencia real en esta maquina: `%TEMP%\.net\WinBoost\` tenia una carpeta de
  extraccion de bundle **incompleta** (77 de ~258 archivos que trae un publish self-contained
  sin trim), y le faltaba exactamente `System.Text.RegularExpressions.dll`.
- La causa: `IncludeAllContentForSelfExtract=true` hace que TODOS los assemblies (no solo las
  DLLs nativas de WPF) se extraigan a disco en el primer arranque, en vez de leerse del bundle
  en memoria. Esa extraccion se marca como "hecha" con solo verificar que la carpeta exista, sin
  chequear si esta completa: una corrida interrumpida (crash, UAC, antivirus, disco lleno) deja
  una carpeta parcial que se reutiliza para siempre en esa build, y el primer assembly que falta
  revienta con `FileNotFoundException` la primera vez que se necesita — que resulto ser
  `System.Text.RegularExpressions`, usado por primera vez en el flujo real dentro de
  `BackupService.SaveRegBackup` (llamado por `OptimizationService.SetReg` antes de cada
  escritura).
- Se descarto la hipotesis alternativa de un bug generico de single-file+compresion: un repro
  minimo (consola con WPF+WinForms+`System.Management`+`System.ServiceProcess.ServiceController`,
  mismos flags de publish, sin trim) publicado desde cero **no reprodujo el fallo** — el Regex
  cargo bien. Esto confirma que el disparador es una cache de extraccion corrupta/incompleta, no
  una incompatibilidad fundamental de la configuracion.
- **Discrepancia con el prompt**: decia "3 usos de Regex en el proyecto" pero
  `BackupService.cs` por si solo tiene 4 (`SaveRegBackup`, `SavePowerPlanBackup` — que extrae el
  GUID del plan activo, exactamente el "backup del plan de energia" que menciona el reporte,
  un matcher de label de HPET, y el helper generico `Match`), ademas de los 2 mencionados en
  `OptimizationService`/`TuningService`. El conteo real es al menos 7, no 3.

**Fix de packaging aplicado**: `IncludeAllContentForSelfExtract` -> `false` en
`Properties/PublishProfiles/win-x64-selfcontained.pubxml` (con comentario explicando el porque).
Los assemblies managed ahora se leen del bundle en memoria (sin extraccion a disco, sin cache
parcial posible). `IncludeNativeLibrariesForSelfExtract` queda igual (`true`): las DLLs nativas
de WPF (wpfgfx_cor3.dll, etc.) siguen extrayendose a disco, sin cambios ahi.

**Frente 2 — Endurecer `SaveRegBackup` (aplicado, independiente del Frente 1):**
`BackupService.SaveRegBackup` ya no usa `Regex.Replace` para sanitizar el nombre de archivo del
backup; se reemplazo por `SanitizeFileName` (recorrido de chars + `StringBuilder`), con el mismo
set de chars permitido (rango ASCII letra/digito/`_`, NO `char.IsLetterOrDigit()` porque ese es
Unicode-aware y hubiera cambiado el comportamiento con acentos/ñ). El
`using System.Text.RegularExpressions;` de `BackupService.cs` se mantiene: `SavePowerPlanBackup`,
el matcher de HPET y el helper `Match` lo siguen usando (fuera de alcance de esta pasada, per
`FIX_regex_singlefile.txt`; con el fix del Frente 1 esos otros usos ya no deberian romperse tampoco).

**Verificacion:**
- `dotnet build`: 0 errores, 0 advertencias.
- Republicado con `src-csharp/Publish-CSharp.ps1 -SkipInstaller` (v4.2, 68.6 MB, single-file
  real sin dependencias sueltas). Se borro la carpeta de cache corrupta previa en
  `%TEMP%\.net\WinBoost\` antes de republicar.
- **Validado por el usuario sobre el .exe publicado**: corrida la Optimizacion completa en el
  binario publicado, ya no aparece el `FileNotFoundException` y las escrituras de registro +
  el plan de energia dan OK. Bug cerrado.

---

## C# diagnostico: instrumentacion TEMPORAL para el "Fallo:" masivo en registro (ahora reproduce tambien en dev, no solo en Windows limpio)

Investigado a partir de `DIAG_registro_limpio_1.txt`. Reporte: el fix anterior (ver entrada de
abajo) ahora reproduce tambien en la maquina de desarrollo, y en la lista de "Fallo:" aparecen
tanto claves HKLM como HKCU (`MouseSpeed`, `GameDVR_Enabled`, `VisualFXSetting`, etc.), lo que
descartaria un problema puro de ACL/permisos. Esta pasada es SOLO diagnostico, sin fix
funcional, marcada con el tag `[diag]` y comentarios `// DIAG-REMOVE` para poder retirarla
despues.

**Hallazgos del diagnostico (solo lectura, sin cambios de logica):**
- **Git**: los cambios del fix anterior (`RegistryPrivilegeHelper` + wrapping `Safe`/`SafeD` en
  `OptimizationService.cs`/`TuningService.cs`) siguen **sin commitear** en el working tree
  (`git status` los muestra como `M`/`??`). Es decir, el "ahora reproduce en dev" coincide
  exactamente con la ventana de tiempo en que ese codigo nuevo esta presente sin commit — el
  candidato mas probable a regresion es el propio `RegistryPrivilegeHelper.OpenWritable`, que
  ahora esta en el camino de TODAS las escrituras de `OptimizationService.OpenOrCreateKey`
  (HKLM **y** HKCU, ya que `OpenOrCreateKey` enruta ambos hives por el mismo helper), no solo
  las HKLM protegidas. Esto es consistente con el sintoma de que ahora fallan tambien claves
  HKCU.
- **ACL owner en dev**: `(Get-Acl "HKLM:\...\Tasks\Games").Owner` devuelve `NT AUTHORITY\SYSTEM`
  en la maquina de desarrollo — el codigo de take-ownership NO mutó esa clave especifica (se
  descarta, para esa clave puntual, la hipotesis de "ownership dañado de una corrida previa").
- **`BackupService.SaveRegBackup`**: tiene su propio `try/catch` interno (bare `catch {}`), por
  lo que NO puede ser la causa de un throw no capturado dentro de `SetReg` — se descarta la
  hipotesis del prompt de que el primer `App.Backup.SaveRegBackup(psPath, name)` es lo que
  tira.
- **`NativeMethods.EnablePrivilege`**: ignoraba el resultado de `AdjustTokenPrivileges` y
  siempre devolvia `true`, sin revisar `ERROR_NOT_ALL_ASSIGNED`. Si el privilegio no se llega a
  habilitar realmente (por ejemplo, no esta en el token en esa maquina), el codigo de
  ownership seguia adelante creyendo que si, y fallaba mas abajo con un `UnauthorizedAccessException` distinto. Instrumentado para ver el `Marshal.GetLastWin32Error()` real.

**Call graph confirmado (Paso 1 del prompt), con lineas:**
- `OptimizationService.SetReg` (linea ~879) llama a `OpenOrCreateKey` (linea ~1000), que ahora
  devuelve `RegistryPrivilegeHelper.OpenWritable(hive, sub)` (linea ~1014) para HKLM **y**
  HKCU.
- `OptimizationService.DisableSvc` (linea ~891) usa `RegistryPrivilegeHelper.OpenWritable`
  directo (linea ~909).
- `TuningService.SetWin32PrioritySep` (linea 46) y `SetHagsState` (linea 65) usan
  `RegistryPrivilegeHelper.OpenWritable` (antes usaban `Registry.LocalMachine.CreateSubKey`
  directo).
- Unicos call sites de `RegistryPrivilegeHelper.OpenWritable`/`EnsureWritableAcl` en todo
  `src-csharp/WinBoost/`: los 4 de arriba. No hay ningun otro.

**Instrumentacion `[diag]` agregada (temporal, tag `// DIAG-REMOVE`):**
- `Services/OptimizationService.cs`
  - `SetReg`: marcas `[diag]` antes/despues de `SaveRegBackup` (para aislar si el throw cae ahi
    o despues), y en el `catch` ahora loguea tipo de excepcion completo (`GetType().FullName`),
    HRESULT (`Marshal.GetHRForException`) y `ex.ToString()` con stack trace.
  - `RunAsync`: al arrancar, loguea `WindowsIdentity.GetCurrent().Name`, el SID, un probe de
    `Registry.CurrentUser.OpenSubKey("Environment")` (para confirmar que HKCU es accesible bajo
    la identidad real del proceso) y el `HandleCount` del proceso; al terminar, vuelve a loguear
    `HandleCount` para comparar contra el del arranque.
- `Services/TuningService.cs`: `SetWin32PrioritySep`, `SetHagsState` y
  `ScanObsoleteDriversAsync` ahora loguean `HandleCount` al entrar y, en su `catch`, tipo +
  HRESULT + stack completo de la excepcion real, y vuelven a relanzar (`throw;`) — no cambia el
  comportamiento observable, solo agrega detalle al log.
- `Services/RegistryPrivilegeHelper.cs`: `OpenWritable` loguea si el primer intento de
  `CreateSubKey` fallo (y con que tipo de excepcion) antes de caer al fallback de
  take-ownership; `EnsureWritableAcl` loguea al entrar y, si el take-ownership falla, agrega
  tipo + HRESULT + stack al mensaje de error que ya existia.
- `NativeMethods.cs`: `EnablePrivilege` ahora loguea, inmediatamente despues de
  `AdjustTokenPrivileges` (antes de que el `CloseHandle` del `finally` pise
  `GetLastWin32Error`), el privilegio pedido, si `AdjustTokenPrivileges` devolvio true/false y
  el codigo de error real (marca si es `1300`/`ERROR_NOT_ALL_ASSIGNED`).

**Como leer el log (usuario):**
- Modo interactivo (UI normal): correr la optimizacion/tuning/scan de drivers, ir a la pestaña
  Consola y usar el boton "Exportar log" -> vuelca a
  `Documentos\WinBoost_Log_<fecha>.txt` (UTF-8). Buscar `[diag]` en ese archivo.
- Modo silencioso (`--silent`/preset): el log ya se escribe solo en
  `%USERPROFILE%\.OptimizarPC\logs\silent_<timestamp>.log`. Buscar `[diag]` ahi.
- Filtrar: `Select-String "\[diag\]" archivo.txt` (PowerShell) o cualquier grep/buscar de texto.

`dotnet build` y `dotnet build --no-incremental`: 0 errores, 0 advertencias.

**Sin fix funcional en esta pasada** (pedido explicito del prompt). Con el log `[diag]` real de
una corrida en la maquina de desarrollo (donde ahora reproduce) se puede confirmar si la causa
es la regresion del `RegistryPrivilegeHelper` sin commitear, un tema de identidad/token, o algo
distinto, y recien ahi decidir el fix.

---

## C# fix: la optimizacion se frenaba a mitad de camino (~30%, "plan de energia") en Windows limpio y fallaba varios tweaks de registro HKLM protegidos por ACL en frio.

Investigado a partir de `prompt_fix_privilegio_optimizacion.txt`. La hipotesis inicial (que
`TuningService` habilitaba un privilegio de token / take-ownership antes de escribir
`PriorityControl`/`GraphicsDrivers`, y que por eso "tocar Tuning primero" arreglaba la
optimizacion) **no se confirmo leyendo el codigo**: `TuningService` no llamaba a
`NativeMethods.EnablePrivilege` en ningun lado; sus `Set*` escribian el registro igual de
"en frio" que `OptimizationService`. La causa real eran dos bugs distintos de robustez:

1. **El freno al ~30%**: `RunAsync` (orquestador de la optimizacion) invocaba
   `PowerPlanTweaks`, `HpetTweaks`, `NetworkTweaks`, `ServiceTweaks`, `FastStartupTweaks` y
   `VisualTweaks` con `Task.Run` SIN try/catch alrededor. Estos metodos llaman a
   `Process.Start` (powercfg/bcdedit/netsh/ipconfig) sin envolver cada llamada; una sola
   excepcion no capturada (ej. `Process.Start` fallando en una maquina rara) se propagaba
   sin frenos hasta `WorkRunner.RunAsync`, que aborta TODO el flujo con un solo
   `catch (Exception)` generico. Como "Plan de energia" es el primer paso con llamadas a
   `Process.Start` sin blindar (30-36% del progreso), un fallo ahi explica el freno
   reportado al 30%.
2. **Accesos denegados en registro HKLM protegido en frio**: algunas claves (ej. la de GPU
   Priority en `SystemProfile\Tasks\Games`) pueden traer de fabrica una ACL que ni
   Administradores puede escribir sin tomar ownership primero, en instalaciones limpias de
   Windows.

**Archivos creados**
- `src-csharp/WinBoost/Services/RegistryPrivilegeHelper.cs` — punto unico compartido:
  `OpenWritable(hive, subKey)` intenta abrir/crear la clave normal y, solo si falla por ACL
  (`UnauthorizedAccessException`/`SecurityException`), habilita
  `SeTakeOwnershipPrivilege`/`SeRestorePrivilege` (via `NativeMethods.EnablePrivilege`, que
  ya existia), toma ownership de la clave y agrega `FullControl` para
  `BUILTIN\Administrators`, y reintenta. Cachea por proceso las claves ya arregladas.

**Archivos modificados**
- `src-csharp/WinBoost/Services/OptimizationService.cs`
  - `OpenOrCreateKey` (usado por `SetReg`, que ya escribe con try/catch por valor) y
    `DisableSvc` ahora pasan por `RegistryPrivilegeHelper.OpenWritable` en vez de
    `RegistryKey.CreateSubKey`/`OpenSubKey` directo.
  - `RunAsync`: cada paso de alto nivel ahora pasa por `Safe`/`SafeD` (helpers nuevos) que
    capturan cualquier excepcion (excepto `OperationCanceledException`, que sigue
    propagandose para que Cancelar funcione), loguean `"Fallo: <paso> (mensaje)"` y dejan
    que el resto de la optimizacion continue.
  - `PowerPlanTweaks`, `HpetTweaks`, `FastStartupTweaks` y los bloques de `NetworkTweaks`
    (Nagle/TCP/DNSFlush) ahora envuelven sus llamadas a `Process.Start` en try/catch
    individuales, para que si un `powercfg`/`bcdedit`/`netsh` puntual falla, el resto de
    comandos del mismo paso (ej. "hibernate off" despues de que fallo activar el plan) se
    sigan aplicando en vez de abortar el metodo entero.
- `src-csharp/WinBoost/Services/TuningService.cs` — `SetWin32PrioritySep` y `SetHagsState`
  usan `RegistryPrivilegeHelper.OpenWritable` en vez de `Registry.LocalMachine.CreateSubKey`
  directo (mismo mecanismo compartido que `OptimizationService`, por si esas claves
  llegan a estar ACL-protegidas en alguna maquina). No se agrego try/catch ahi: el caller en
  `MainWindow.xaml.cs` ya envuelve ambas llamadas y usa la excepcion para mostrar el error
  en la UI (`lblPrioStatus`/`lblHagsResult`); atraparla adentro hubiera roto ese feedback.

`dotnet build`: 0 errores, 0 advertencias.

**Pendiente de validar**: no hay una maquina Windows limpia disponible en esta sesion para
reproducir el freno original; el fix se valido leyendo el flujo completo (`RunAsync` ->
`WorkRunner.RunAsync` -> UI) y confirmando que ya no hay una excepcion no capturada capaz de
abortar el proceso a mitad de camino, mas el mecanismo de ownership para el caso de ACL
realmente restrictiva. Recomendado probar en la maquina limpia real antes del proximo release.

---

## C# updater: removido el boton "Ver en GitHub" del dialogo de actualizacion (no aporta valor al usuario final; el flujo es descargar e instalar directo).

**Archivos modificados**
- `src-csharp/WinBoost/ChangelogDialog.xaml` — quitado `btnUpdateGitHub`; quedan solo "Ahora no"
  y "Descargar e instalar" en el `StackPanel` de botones (sin hueco, misma alineacion a la derecha).
- `src-csharp/WinBoost/ChangelogDialog.xaml.cs` — quitado el valor `GitHub` de `ChangelogResult`
  y el handler `OnGitHub`.
- `src-csharp/WinBoost/MainWindow.xaml.cs` (`OnUpdateBadgeClick`) — quitado el `case
  ChangelogResult.GitHub` del switch. El helper `OpenUrl` NO se toco: sigue en uso en los
  fallbacks existentes (descarga no disponible, hash faltante, etc.) que abren
  `meta.ReleaseUrl` fuera del dialogo.

**Detalle**

Decision de producto: el boton mandaba al usuario final (gamers, no devs) a una pagina tecnica
en ingles de GitHub justo al momento de actualizar, ademas de apuntar a `/releases` (que ignora
pre-releases y puede llevar al release equivocado). Se quita el boton sin tocar la logica del
updater (check/download/verify/apply).

`dotnet build`: 0 errores, 0 advertencias. XAML validado con `ElementTree`.

---

## C# distribucion: build self-contained single-file + instalador Inno Setup; compatible con los flags silenciosos del auto-updater.

Arma la distribucion de la app C# (`src-csharp/WinBoost/`) pedida en `prompt_distribucion_csharp.txt`:
publish self-contained single-file + instalador. El PS1 sigue siendo la version distribuida; esto
NO ejecuta el corte (item 6.3 de PENDIENTES.md sigue pendiente).

**Archivos creados**
- `src-csharp/WinBoost/Properties/PublishProfiles/win-x64-selfcontained.pubxml` — settings de publish
  (RID/self-contained/single-file solo aca, no en el `.csproj` principal)
- `src-csharp/Publish-CSharp.ps1` — script reproducible: publish + chequeo del bundle + instalador
- `src-csharp/installer/WinBoost.iss` — instalador Inno Setup 6 para la version C#

**Archivos modificados**
- `src-csharp/WinBoost/WinBoost.csproj` — `AssemblyName`/`Product`/`AssemblyTitle`/`ApplicationIcon`

**Recomendacion (parte 1 del prompt)**

- *Modelo:* self-contained + single-file, `win-x64`, `IncludeNativeLibrariesForSelfExtract=true`
  (WPF no puede cargar sus DLLs nativas directo desde el single-file; las embebe y las extrae a un
  bundle-staging temporal en el primer arranque de cada version — comportamiento esperado, no bug),
  `EnableCompressionInSingleFile=true` (baja el tamano de descarga). `PublishReadyToRun` queda OFF:
  para WPF+single-file casi duplica el tamano por una mejora de arranque en frio marginal en una app
  que se abre ocasionalmente. Es single-file "puro": el `.pubxml` fuerza que no queden DLLs sueltas
  al lado del exe (verificado por el script, ver Verificacion).
- *RID/self-contained solo en un publish profile, no en el `.csproj` principal:* si esas propiedades
  quedan en el `PropertyGroup` de siempre, `dotnet build` (uso diario) tambien restaura y copia el
  runtime completo de WPF en cada compilacion de desarrollo. Con el profile, `dotnet build` sigue
  framework-dependent y rapido; el publish self-contained solo se dispara al pedirlo explicitamente.
- *Instalador: se adapto el `.iss` viejo (Inno Setup), no se cambio de herramienta.* Motivos: (1)
  Inno Setup YA soporta nativamente `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL` sin
  configuracion extra — son switches estandar del engine, no hubo que agregar nada para la
  restriccion no-negociable #1; (2) `PrivilegesRequired=admin` + `UsePreviousAppDir=yes` ya resuelven
  las restricciones #2 y #3 (misma carpeta estable entre versiones); (3) con un solo exe grande
  ya no hace falta empaquetar el XAML aparte, asi que el `.iss` se simplifica (un solo `[Files]`)
  en vez de complicarse. No se vio ninguna ventaja real de MSIX/WiX/Squirrel para este caso que
  justificara el cambio de herramienta y el research/setup adicional.

**Implementacion (parte 2 del prompt)**

- `win-x64-selfcontained.pubxml`: `RuntimeIdentifier=win-x64`, `SelfContained=true`,
  `PublishSingleFile=true`, `IncludeNativeLibrariesForSelfExtract=true`,
  `IncludeAllContentForSelfExtract=true`, `EnableCompressionInSingleFile=true`,
  `PublishReadyToRun=false`, `SelfContainedDeploymentUseAppHost=true`.
- `src-csharp/installer/WinBoost.iss`: mismo `AppId` que `installer/WinBoost.iss` (PS1) a proposito
  — si el auto-updater instala esta version sobre una instalacion previa (PS1 o C#), Inno Setup lo
  reconoce como upgrade del mismo producto (misma carpeta, mismo registro de Add/Remove Programs,
  sin entradas duplicadas). `[Files]` solo declara `WinBoost.exe` (sin XAML: en C# el XAML compila a
  BAML embebido en el assembly, no se carga externo como en el PS1). Nuevo paso `[Code]`
  `CurStepChanged(ssPostInstall)` que borra `OptimizarPC_UI.xaml` en `{app}` si existe, para no dejar
  huerfano el archivo que dejaba el instalador viejo al actualizar in-place. `OutputBaseFilename`
  mantiene el mismo patron `WinBoost_Setup_{#AppVersion}` que ya usa `version.json.downloadUrl`
  (restriccion #4). `AppVersion` se recibe por `/DAppVersion=X.Y` (lo pasa el script, leido de
  `App.Version` en `App.xaml.cs` — no hay que tocar el `.iss` en cada release).
- `src-csharp/Publish-CSharp.ps1`: `dotnet publish -c Release -p:PublishProfile=win-x64-selfcontained`
  → chequeo estatico del bundle (cabecera PE valida + que no haya DLLs sueltas al lado del exe, solo
  `.pdb` tolerado) → compila el `.iss` con ISCC si esta instalado (busca en PATH y en las dos rutas
  default de Inno Setup 6) → imprime tamano y SHA256 de exe e instalador. No lanza el exe: WinBoost
  requiere elevacion (`app.manifest requireAdministrator`), asi que ejecutarlo sin avisar dispararia
  un UAC real en el escritorio del usuario desde un script automatico — el script deja como "prueba
  manual pendiente" correrlo y aceptar el UAC, en vez de intentar automatizar algo que requiere un
  click humano en un dialogo del sistema.

**Verificacion (parte 3 del prompt, corrida en esta maquina)**

- `dotnet publish`: OK. `WinBoost.exe` self-contained single-file, **68.6 MB**, SHA256
  `314642671EBDDF3F493238995383952CE04DBB1940EC18BCF12FC5E9E7F97E32`. Carpeta de publish sin
  dependencias sueltas (solo el `.exe`).
  Nota: la maquina de build SI tiene .NET instalado, asi que "corre sin .NET" no se pudo confirmar
  en una maquina limpia — pendiente de probar en un Windows sin runtime .NET si se quiere el 100%
  de certeza (el mecanismo self-contained lo garantiza por diseno, pero no se verifico en maquina
  limpia real).
- Instalador (`ISCC.exe`, Inno Setup 6.7.3, ya presente en esta maquina): compilo sin errores ni
  warnings — **63.7 MB**, SHA256 `C1EDD1FB703FC149A5C96AC35DB18496BA966C065203D704906F920741EEB295`.
- Instalacion silenciosa real probada en esta maquina (sesion ya elevada, asi que no aparecio UAC —
  en un usuario final normal SI aparece una vez, es el comportamiento esperado de un instalador
  `admin`): `WinBoost_Setup_4.1.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL` → exit code 0,
  `C:\Program Files\WinBoost\WinBoost.exe` presente, entrada de Add/Remove Programs creada
  (`DisplayName=WinBoost versión 4.1`, `InstallLocation=C:\Program Files\WinBoost\`). Se lanzo el exe
  instalado: abrio elevado, con ventana principal (`MainWindowTitle=WinBoost`) respondiendo, y se
  cerro limpio. Se desinstalo con `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL` → exit 0,
  carpeta removida — la maquina de desarrollo quedo como estaba antes de la prueba (instalacion de
  test, no se dejo instalado a proposito).

`dotnet build` (proyecto normal, sin el publish profile): sin tocar, se mantiene framework-dependent
y rapido como antes.

---

## C# fix regresion: el escaneo de bloatware dejo de detectar tras el fix de desinstalacion; restaurada la deteccion sin romper los 3 intentos de uninstall.

**Archivo modificado**
- `src-csharp/WinBoost/Services/BloatwareService.cs` — DB de Xbox (3 entradas) + matching de `GetBloatwareListAsync`

**Diagnostico (causa raiz real, verificada corriendo la enumeracion + matching en un harness aparte
sobre esta maquina)**

NO fue el fix anterior de `RemoveAppAsync` (los 3 intentos de desinstalacion con try/catch separado):
`git diff` confirma que ese cambio solo toco la desinstalacion, no la enumeracion (`GetInstalledAppxMap`)
ni el matching (`GetBloatwareListAsync`) — esas dos funciones quedaron intactas.

La causa real es un gap preexistente en la DB de bloatware (heredado tal cual del `.ps1` original, sin
cambios recientes ahi tampoco): esta maquina tiene los paquetes de Xbox con nomenclatura **legacy**, y
la DB solo contemplaba la nomenclatura **nueva** — el `Contains` bilateral nunca matcheaba:
- "Xbox Game Bar" buscaba `Microsoft.XboxGamingOverlay`; el paquete real instalado es
  `Microsoft.XboxGameOverlay` (sin "ing").
- "Xbox App" buscaba `Microsoft.GamingApp`; el paquete real instalado es `Microsoft.XboxApp` (variante
  legacy de la app Xbox).
- "Xbox TCUI" buscaba `Microsoft.Xbox.TCUI`; Windows lo reemplazo por `Microsoft.XboxGameCallableUI` en
  builds mas nuevos (mismo rol — "Title/Game Callable UI" — nombre distinto).

No era falta de deteccion generica: la enumeracion de AppX (81 paquetes reales en esta maquina) y el
matching por substring seguian funcionando igual que siempre. Las apps "genericas" de la DB (Candy
Crush, Spotify, WhatsApp, etc.) simplemente ya no estaban instaladas en esta maquina (probablemente
desinstaladas en pruebas previas del propio removedor de bloatware) — de ahi que CUALQUIER coincidencia
restante dependiera de las 3 entradas de Xbox, y esas 3 fallaban por el gap de nomenclatura, dando
"Sistema limpio" con 0 detectados aunque el sistema no estuviera limpio.

**Fix**

- `BloatwareDbEntry.PackageId` ahora puede llevar varios alias separados por `'|'` (mismo paquete con
  nombre distinto segun la version de Windows).
- Las 3 entradas de Xbox pasan a `"Microsoft.XboxGamingOverlay|Microsoft.XboxGameOverlay"`,
  `"Microsoft.GamingApp|Microsoft.XboxApp"` y `"Microsoft.Xbox.TCUI|Microsoft.XboxGameCallableUI"`.
- El loop de matching en `GetBloatwareListAsync` itera cada alias (`entry.PackageId.Split('|')`) contra
  el mapa de AppX instalados, en vez de comparar contra un unico `PackageId`.
- La DB completa (55 entradas) sigue intacta; solo se agregaron alias a esas 3, no se removio ni
  reemplazo ninguna entrada.
- `RemoveAppAsync` (los 3 intentos de desinstalacion con try/catch separado, mensaje claro para apps
  protegidas) no se toco: sigue operando sobre `app.PackageFN`, que es siempre el nombre REAL resuelto
  por el matching, no el alias de la DB.

**Verificacion**

Harness standalone (fuera del proyecto, mismo codigo de enumeracion+matching) corrido en esta maquina
(elevado): antes del fix, 0/45 matches contra la DB completa pese a 81 paquetes AppX reales instalados;
despues del fix, 3 matches — exactamente los 3 paquetes de Xbox confirmados instalados (Xbox Game Bar
como `Microsoft.XboxGameOverlay_8wekyb3d8bbwe`, Xbox App como `Microsoft.XboxApp_8wekyb3d8bbwe`, Xbox
TCUI como `Microsoft.XboxGameCallableUI_cw5n1h2txyewy`). `dotnet build`: 0 errores, 0 advertencias.

---

## C# Fixes — Plan de energia (Ultimate Performance no se activaba y duplicaba) + Bloatware (mensaje claro para apps protegidas del sistema)

Dos bugs reportados en la app C# (`src-csharp/WinBoost/`). App corre elevada.

**Archivos modificados**
- `src-csharp/WinBoost/Services/OptimizationService.cs` — `PowerPlanTweaks` + nuevo helper `FindSchemeGuidByName`
- `src-csharp/WinBoost/Services/BloatwareService.cs` — `RemoveAppAsync` (script de remocion AppX) + nuevo helper `IsProtectedPackageError`

**BUG 1 — Plan de energia "Ultimate Performance": creaba pero no aplicaba, y duplicaba en cada corrida**

- *Causa raiz real (confirmada corriendo `powercfg /list` en el equipo):* tanto el `.ps1` legacy
  como el port C# verificaban "¿ya existe el plan?" buscando el GUID **semilla**
  `e9a42b02-d5df-448d-aa00-03f14749eb61` dentro de `powercfg /list`. Pero `powercfg
  -duplicatescheme` NO conserva ese GUID en el plan resultante: le asigna uno **nuevo y
  aleatorio** cada vez (verificado: en este equipo el plan "Máximo rendimiento" activo tiene
  GUID `6028fb9b-e71e-4cfa-9e79-98985b3bf5c5`, no `e9a42b02...`). Como la comparacion contra el
  GUID semilla nunca matcheaba, la app: (a) creaba un plan nuevo en CADA corrida (duplicados
  infinitos, porque siempre creia que "no existia"), y (b) al buscar el GUID semilla en el
  resultado para activarlo tampoco lo encontraba, asi que activaba el fallback SCHEME_MIN (Alto
  Rendimiento) en vez del plan Ultimate Performance recien creado — de ahi "crea pero no aplica".
  Este bug esta presente tambien en el `.ps1` legacy (mismo patron, lineas ~2919-2924); queda
  documentado aca pero fuera de alcance de este cambio (pedido explicitamente solo para C#).
- *Fix:* nuevo `FindSchemeGuidByName` parsea `powercfg /list` con regex y busca el plan por
  **nombre** (bilingue: "Ultimate Performance" / "Máximo rendimiento", tolerante al acento) en
  vez de por el GUID semilla, devolviendo su GUID real. `PowerPlanTweaks` ahora: busca el plan
  existente por nombre -> si no existe, duplica desde el GUID semilla y vuelve a buscar por
  nombre para obtener el GUID real asignado -> activa ESE guid con `/setactive`. Corridas
  repetidas detectan el plan ya creado (por nombre) y no vuelven a duplicar.

**BUG 2 — Bloatware: apps que fallan al desinstalar (ej. Xbox, 0x80070002) con mensaje generico**

- *Contexto:* el refresh de la lista post-desinstalacion YA re-escaneaba el estado real del
  sistema (`ScanBloatwareAsync` llama a `GetBloatwareListAsync`, que vuelve a enumerar AppX
  desde cero) — no habia bug ahi. El problema real estaba en el mensaje de fallo y en que el
  script de remocion abortaba de mas.
- *Causa raiz:* el script de PowerShell embebido envolvia los 3 intentos de remocion (usuario
  actual, `-AllUsers`, `Remove-AppxProvisionedPackage`) en un UNICO `try/catch`. Si el primer
  intento (`Remove-AppxPackage` para el usuario actual) fallaba con excepcion — como pasa con
  apps protegidas/aprovisionadas por el sistema (Xbox Game Bar, Xbox Identity Provider, Xbox
  TCUI con `0x80070002`) — el catch externo cortaba la ejecucion ANTES de intentar `-AllUsers` o
  el paquete provisionado, y devolvia el texto crudo de la excepcion .NET como mensaje.
- *Fix:* cada intento de remocion (usuario actual / AllUsers / Provisioned) corre ahora en su
  propio `try/catch` interno que acumula el error sin abortar los siguientes; al final SIEMPRE
  se verifica el estado real (`WB_STILL` si sigue instalado tras los 3 intentos). Nuevo
  `IsProtectedPackageError` detecta `0x80070002` / "access is denied" / "acceso denegado" /
  "denegado" en el detalle acumulado y traduce el mensaje a uno claro: "Protegida/aprovisionada
  por el sistema - Windows no permite quitarla (comun en apps de Xbox/sistema)", en vez del
  texto de excepcion crudo. Los fallos genuinos (no reconocidos como proteccion de sistema)
  siguen mostrando el detalle tal cual para diagnostico.

`dotnet build`: 0 errores, 0 advertencias.

---

## Seguridad: rotacion de claves de licencia — clave publica RSA reemplazada por par nuevo (la privada vieja quedo comprometida en repo publico); gitignore blindado contra generador y claves privadas.

**Archivos modificados**
- `src-csharp/WinBoost/Services/LicenseService.cs` — `PublicKeyXml` (RSA-2048) reemplazada por el
  par nuevo. Logica de verificacion (`TestSignature`, `TestLicenseKey`, `TestTechLicenseKey`) sin
  cambios.
- `.gitignore` (raiz) — agregado bloque para nunca subir el generador de licencias ni claves
  privadas: `Gen-License.ps1`, `*gen*license*.ps1`, `*_private*.xml`, `winboost_private*.xml`,
  `*.key`, `winboost_keys*/`.

**Detalle**

La clave privada RSA vieja quedo expuesta porque `Gen-License.ps1` (el generador) se subio al
repo publico. Se regenero un par RSA-2048 nuevo; este cambio solo toca la clave PUBLICA (la que
vive en la app) — la privada y el generador quedan fuera del repo, en la maquina del emisor.

Verificado: la clave vieja (`1i89Gsv9...`) ya no aparece en ningun archivo de `src-csharp/`; no
hay otro archivo con material de clave privada (`<P>`/`<D>`/`<InverseQ>`) en `src-csharp/`.
`dotnet build`: 0 errores, 0 advertencias.

**Pendiente (fuera de alcance de este cambio, reportado al usuario):**
- `Gen-License.ps1` sigue TRACKEADO en git (esta en el indice, no solo en el gitignore nuevo) —
  el `.gitignore` no lo va a destrackear retroactivamente. Requiere `git rm --cached
  Gen-License.ps1` (accion de git a confirmar con el usuario) y, dado que ya estuvo publico,
  considerar limpieza de historial si el repo es publico.
- El `.ps1` legacy (`OptimizarPC_App.ps1`) todavia tiene la clave publica VIEJA embebida
  (`1i89Gsv9...`) — fuera de alcance de este prompt (que pedia solo `src-csharp/`), pero como
  el PS1 sigue siendo la version distribuida, la licencia validada por esa version seguira
  aceptando firmas hechas con la clave privada vieja comprometida hasta que tambien se rote ahi.

---

## C# Game Focus Mode dado de baja (impacto marginal; Process Lasso cubre el nicho). Reemplazo por deteccion Steam + prioridad por juego queda pendiente post-migracion.

**Archivos modificados**
- `src-csharp/WinBoost/Services/GameFocusService.cs` — eliminado (servicio completo: deteccion
  de fullscreen, lista de juegos conocidos, mascara de nucleos fisicos, Apply/Restore)
- `src-csharp/WinBoost/App.xaml.cs` — eliminado el singleton `App.GameFocus`
- `src-csharp/WinBoost/Services/AppSettings.cs` — eliminada la propiedad `GameAffinityEnabled`
- `src-csharp/WinBoost/Services/SettingsService.cs` — eliminada la copia de `GameAffinityEnabled` en `Load()`
- `src-csharp/WinBoost/MainWindow.xaml.cs` — eliminados el campo `_gamingTimer`, su wiring
  (Tick/Start), el `Stop()` + `GameFocus.Restore()` en `OnClosed`, y el metodo `OnGamingTick`
- `src-csharp/WinBoost/MainWindow.xaml` — eliminado el badge `badgeGamingMode` del header
- `src-csharp/WinBoost/NativeMethods.cs` — eliminado el bloque `user32` completo
  (`GetForegroundWindow`, `GetWindowRect`, `MonitorFromWindow`, `GetMonitorInfo`,
  `GetWindowThreadProcessId`, `GetDesktopWindow`, `GetShellWindow`) y los structs `RECT`/`MONITORINFO`

**Detalle**

Decision de producto: la afinidad a nucleos fisicos no mostro cambio real medible y muchos
juegos ya arrancan en prioridad alta por su cuenta; Process Lasso ya cubre este nicho mejor.
Se remueve todo el modulo sin reemplazo inmediato.

- **P/Invoke `user32` (equivalente a `Win32FS` del PS1):** se verifico que las 7 funciones y
  los 2 structs eran de uso EXCLUSIVO de `GameFocusService` (unico archivo que las referenciaba
  fuera de `NativeMethods.cs`) -> removidas junto con el servicio. Ningun otro modulo (monitor,
  procesos, tuning, etc.) las usaba.
- **Setting huerfano:** `GameAffinityEnabled` se quita del modelo `AppSettings` y de `Load()`.
  `System.Text.Json` ignora propiedades desconocidas al deserializar por default, asi que un
  `settings.json` existente con `"GameAffinityEnabled": true` de una version anterior carga sin
  error (la propiedad simplemente se descarta).
- **Sin card en Ajustes que remover:** a diferencia del PS1 (que tenia `chkGameAffinity` en una
  card de Ajustes), la migracion a C# nunca llego a portar esa UI — el unico rastro visual era el
  badge "GAMING MODE" del header (`badgeGamingMode`), que se elimino junto con el resto.
- El resto de Ajustes (mantenimiento, apariencia, comportamiento, acerca de) no se toco.

`dotnet build`: 0 errores, 0 advertencias. XAML validado con `ElementTree`. Smoke test:
`WinBoost.exe` arranca y corre sin crashear (validacion completa de UI requiere clickear el UAC
de elevacion manualmente).

---

## C# modo silencioso CLI reparado: motor de optimizacion desacoplado de la UI (recibe preset como datos), NullReference resuelto; log por fecha en logs/

**Archivos modificados**
- `src-csharp/WinBoost/Services/AppLogger.cs` — nueva interfaz `IAppLogger`; `AppLogger` la implementa
- `src-csharp/WinBoost/Services/SilentFileLogger.cs` — nuevo: `NullLogger` (no-op, default) y `SilentFileLogger` (escribe al archivo, usado en modo silencioso)
- `src-csharp/WinBoost/App.xaml.cs` — `App.Logger` cambia de `AppLogger` a `IAppLogger` (inicializado con `NullLogger.Instance`); `RunSilentAsync` pasa a `Task<int>`, crea log `silent_<yyyyMMdd_HHmmss>.log` en `logs/`, instancia `SilentFileLogger` antes de correr, devuelve exit code (0=OK / 1=cancelado / 2=error fatal) pasado a `Shutdown()`
- `src-csharp/WinBoost/Services/BackupService.cs` — 5 null-refs corregidos: `App.Logger.Log(...)` → `App.Logger?.Log(...)` en `NewBackupSession` y `SaveSessionMetadata`; method group `App.Logger.Log` en `RestoreSession` → lambda `(msg, type) => App.Logger?.Log(msg, type)`
- `src-csharp/WinBoost/Services/GameFocusService.cs` — 5 null-refs corregidos: `App.Logger.Log(...)` → `App.Logger?.Log(...)`
- `src-csharp/WinBoost/Services/RamService.cs` — 1 null-ref corregido: `App.Logger.Log(...)` → `App.Logger?.Log(...)`

**Causa raiz del NullReferenceException**

`App.Logger` era `AppLogger = null!` (null hasta que MainWindow lo inicializa en `OnLoaded`). En modo silencioso, `MainWindow` nunca se crea, por lo que `App.Logger` quedaba null. La primera llamada real era `BackupService.NewBackupSession()` linea 40 con `App.Logger.Log(...)` sin null-conditional — crash inmediato antes de aplicar ningun tweak.

**Por que el motor de optimizacion NO necesitaba refactorizacion adicional**

`OptimizationService.RunAsync` ya recibia el preset como diccionario de datos (independiente de la UI). Las llamadas internas usaban `App.Logger?.Log(...)` y `App.Progress?.Set(...)` con null-conditional — no crasheaban. El problema era SOLO el Logger null en los servicios auxiliares (BackupService, GameFocusService, RamService).

**Solucion**

- `IAppLogger` como contrato comun. `AppLogger` (UI) y `SilentFileLogger` (archivo) lo implementan.
- `NullLogger` singleton como default: `App.Logger` nunca es null, los ~40 `App.Logger.Log(...)` existentes en MainWindow siguen validos sin cambios.
- En modo silencioso, `App.Logger = new SilentFileLogger(logPath)` antes de cualquier operacion → todos los pasos de optimizacion, backup y red quedan registrados en el archivo automaticamente.
- Log por fecha: `~/.OptimizarPC/logs/silent_<yyyyMMdd_HHmmss>.log` (no se pisa entre ejecuciones).
- Exit code: 0=OK, 1=cancelado/fallo, 2=error fatal — pasado a `Shutdown()`.

`dotnet build`: 0 errores, 0 advertencias.

---

## C# Fixes — 6 bugs: VRAM real, score Red, mantenimiento/backup, tema claro, guardar perfil, toast

Seis bugs de la app C# (`src-csharp/WinBoost/`). App corre elevada. Para cada uno:
diagnostico de causa raiz y fix. Referencias contra el `.ps1` legacy.

**Archivos modificados**
- `src-csharp/WinBoost/Services/TuningService.cs` — VRAM real desde el registro (BUG 1)
- `src-csharp/WinBoost/Services/SystemInfoService.cs` — check RSS bilingue (BUG 2)
- `src-csharp/WinBoost/MainWindow.xaml.cs` — toast in-app, seccion Ajustes, feedback de perfil (BUG 3/4/5/6)
- `src-csharp/WinBoost/MainWindow.xaml` — overlay de toast in-app (BUG 6)

**BUG 1 — VRAM muestra 4GB en vez del real (bug heredado)**
- *Causa raiz (confirmada en el equipo):* `Win32_VideoController.AdapterRAM` es un entero de
  32 bits con signo (max ~4GB). En la RX 6700 XT (12GB) reportaba `4293918720` (~4GB) por
  overflow. El valor real vive en el registro como QWORD de 64 bits: la subkey
  `...Control\Class\{4d36e968-...}\0000` tenia `HardwareInformation.qwMemorySize=12868124672`
  (~12GB).
- *Fix:* `GetExtendedInfoAsync` ahora lee la VRAM del registro (`qwMemorySize`), recorriendo los
  subkeys `0000/0001/...` de la clase de display y matcheando por `DriverDesc`; si no hay match,
  toma la GPU con mas VRAM dedicada. `AdapterRAM` queda solo como fallback. Lee QWORD o binario
  de 8 bytes. Se muestra en GB en la tab de componentes.
- *Driver version:* verificado — `Win32_VideoController.DriverVersion` (`32.0.21043.19003`)
  COINCIDE con el registro (`DriverVersion`) y con el Administrador de dispositivos. No requeria
  correccion; el path de registro tambien expone el mismo valor como respaldo.

**BUG 2 — Score no sube: categoria Red 2/3 (DIAGNOSTICO cruzado)**
- *Caso:* (b) la optimizacion SI aplica el tweak, pero el SCORE no lo mide bien (check mal
  portado). NO faltaba el tweak.
- *Check concreto:* `TCPTuning` ("TCP/IP optimizado (RSS habilitado)"). `CheckTcpTuning`
  parseaba `netsh int tcp show global` buscando la etiqueta en ingles "Receive-Side Scaling".
  En Windows en espanol la salida se localiza a "Estado de escalado de lado de recepcion:
  enabled", por lo que la regex en ingles NUNCA matcheaba -> el check daba negativo SIEMPRE,
  dejando Red en 2/3 aunque RSS estuviera activo (confirmado: RSS = enabled en el equipo, y la
  optimizacion aplica `netsh ... rss=enabled` correctamente).
- *Fix:* matcheo bilingue — el token "escalado" identifica la linea de RSS en espanol (la de RSC
  usa "fusion de segmento", sin "escalado") y "Receive-Side Scaling" la de ingles; el valor
  "enabled"/"disabled" que emite netsh no se localiza. Mismo patron de fix que el bug de pnputil
  documentado antes. (El mismo bug de localizacion existe en el `.ps1` legacy; fuera de alcance.)

**BUG 3 — Ajustes > Mantenimiento y backup no funcionaba**
- *Causa:* toda la seccion de mantenimiento/backup del tab Ajustes quedo SIN cablear en C#
  (ruta vacia, "Calculando..." colgado, combo y boton muertos).
- *Fix (`WireSettingsControls` + `LoadBackupInfoAsync`):* `lblBackupPath` se puebla con
  `Settings.BackupRoot` real; el tamano + conteo de sesiones se calcula async (`Task.Run`,
  recursivo) y reemplaza "Calculando..." por "N sesion(es) · X MB" (disparo lazy al entrar al
  tab). El combo "Retener backups por" persiste a `Settings.BackupRetainDays` (7/14/30/60/0=ilim);
  "Abrir carpeta" abre la carpeta real (creandola si falta); "Cambiar" usa `OpenFolderDialog`
  (.NET 8) y recalcula el tamano.

**BUG 4 — Cambio a tema claro no funcionaba**
- *Causa:* `SettingsService.ApplyTheme` (que reasigna los brushes de la paleta a light/dark en
  `window.Resources`) ya estaba portado y se aplicaba al arrancar, pero el combo `cboTheme`
  estaba SIN cablear: cambiarlo no hacia nada.
- *Fix:* `cboTheme` se inicializa al indice del tema persistido y su `SelectionChanged` setea
  `Settings.Theme`, llama `ApplyTheme(this)` (los consumidores `{DynamicResource}` se actualizan
  al instante) y guarda. Paridad con `Apply-Theme` del PS1 (solo la paleta tematizable cambia).

**BUG 5 — Guardar perfil "no guardaba"**
- *Causa:* `SaveProfile` SI escribia `opt_profile.json` correctamente (verificado en disco), pero
  no daba feedback: solo logueaba a consola, asi que el boton parecia muerto.
- *Fix:* se agrega el `MessageBox` de confirmacion (mirror del `btnSaveProfile` del PS1) al
  guardar OK y otro al fallar.

**BUG 6 — Toast queda estatico y no se va**
- *Causa:* el unico "toast" era `ToastService` (NotifyIcon/balloon del tray), que en Win10/11
  puede quedar en el Centro de actividades. No habia un toast in-app con auto-hide.
- *Fix:* toast in-app declarativo (overlay esquina inferior derecha, `toastHost`) + `ShowToast`
  que lo muestra y (re)arranca un `DispatcherTimer` unico de 4s; si aparece otro toast antes de
  vencer, el `Stop()+Start()` reinicia la cuenta y no quedan colgados (mirror del timer de
  `Show-ToastNotification`). Las dos llamadas (fin de optimizacion y de mantenimiento) usan
  `ShowToast` en vez del NotifyIcon.

`dotnet build`: 0 errores, 0 advertencias. XAML validado con ElementTree.

---

## C# Fixes — badge de errores, boton Limpiar de consola, bloatware fantasma + ExitCode=1

Tres bugs de la app C# tras el reorden de tabs. App corre elevada (no eran permisos).

**Archivos modificados**
- `src-csharp/WinBoost/MainWindow.xaml.cs` — cableado de `btnErrBadge.Click` y `btnClearLog.Click`
- `src-csharp/WinBoost/Services/BloatwareService.cs` — deteccion por presencia real + remocion robusta/grace

**BUG 1 — el badge "N errores" no llevaba a Consola**
- *Causa:* el `btnErrBadge` nunca tuvo handler de click cableado (solo se le pasaba al `AppLogger`
  para mostrar/contar). No era un indice viejo: directamente no navegaba.
- *Fix:* `btnErrBadge.Click += (_,_) => SetActiveNav(5)` — Consola es el indice 5 en el orden
  nuevo (Optimizar 0, Herramientas 1, Info 2, Arranque 3, Bloatware 4, Consola 5, Historial 6,
  Ajustes 7; Licencia 8 / Tuning 9 aparte).
- *Auditoria de indices:* se revisaron TODAS las llamadas a `SetActiveNav(n)` y las comparaciones
  `mainTabs.SelectedIndex == n` (lazy-loads de tabs). Todas ya apuntaban a la tab correcta del
  orden nuevo (Consola 5, Bloatware 4, Info 2, Historial 6, etc.). El unico desfasaje era el badge
  sin cablear. No quedaron otras referencias de indice obsoletas.

**BUG 2 — el boton "Limpiar" de la consola no limpiaba**
- *Causa:* `btnClearLog` existia en el XAML pero no estaba cableado en el code-behind (boton muerto).
- *Fix:* `btnClearLog.Click` -> `rtbLog.Document.Blocks.Clear()` + `lblLogStatus.Text="Log limpiado"`
  (mirror del PS1). El badge de errores no se toca al limpiar (paridad con el PS1).
- *Tambien cableado `btnExportLog` (Exportar .txt):* estaba muerto igual que Limpiar. Nuevo
  `ExportConsoleLog()` (mirror del `btnExportLog` del PS1): vuelca el texto de la consola via
  `TextRange(rtbLog.Document)` a `Documentos\WinBoost_Log_<fecha>.txt` (UTF-8 sin BOM), avisa por
  MessageBox y setea `lblLogStatus`. (En el PS1 exportaba `$script:logLines`; en C# no hay esa
  lista, asi que se lee el contenido del RichTextBox, que es equivalente.)

**BUG 3 — bloatware: apps fantasma + ExitCode=1 al reintentar**
- *Causa raiz (apps fantasma):* el scan enumeraba `Get-AppxPackage -AllUsers` sin filtrar, que
  incluye paquetes en estado **Staged** (preparados pero no instalados para ningun usuario, p.ej.
  tras una desinstalacion incompleta). Esos paquetes no estan presentes de verdad: reaparecian en
  la lista y al reintentar borrarlos `Remove-AppxPackage -EA Stop` fallaba con ExitCode=1.
- *Fix deteccion:* el scan ahora suma el usuario actual (`Get-AppxPackage`, siempre instalado) +
  `-AllUsers` filtrado a paquetes con al menos un `PackageUserInformation.InstallState -eq
  'Installed'`. Los staged-only dejan de listarse.
- *Fix remocion (robusta + graceful):* `RemoveAppAsync` quita el paquete del usuario actual y de
  todos los usuarios (`-AllUsers`, cubre staged) + el provisionado, y verifica el resultado real
  emitiendo un marcador en vez de fiarse solo del exit code: `WB_REMOVED` (existia y se quito) y
  `WB_NOTFOUND` (ya no estaba) -> Ok; `WB_STILL`/`WB_ERR:` -> fallo real que cae a winget. Asi un
  reintento sobre una app ya removida da "Ya estaba desinstalada" (verde), no error rojo.
- *winget:* el ExitCode `0x8A15002B` (NO_APPLICATIONS_FOUND = la app ya no esta) tambien se trata
  como "Ya estaba desinstalada" (exito), no como error.
- *Re-escaneo:* el re-scan automatico tras desinstalar ya existia (`SetActiveNav(4)` +
  `ScanBloatwareAsync()`); con la deteccion corregida la lista ahora refleja el estado real.

`dotnet build`: 0 errores, 0 advertencias.

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
