# WinBoost — PENDIENTES (unificado)

> **Para Claude Code:** leer al arrancar cada sesión. La migración PS1→C#/WPF está COMPLETA
> (corte 6.3): `src-csharp/` es la única versión oficial y distribuida; el `.ps1` fue jubilado a
> `legacy/`. El trabajo forward-looking está en los tres módulos de abajo, en este orden de
> prioridad: **(1) rediseño UX/UI → (2) nuevas funcionalidades → (3) obligatorio para salir al
> mercado.** Marcar `[x]` al completar y actualizar CHANGELOG.md. Reglas C# en CLAUDE.md.
>
> Este archivo unifica y reemplaza: el PENDIENTES.md previo, PENDIENTES_LANZAMIENTO.md (era PS1,
> ya obsoleto en su mayoría) e IDEAS_BENCHMARK_COMPETITIVO.txt (backlog + análisis competitivo).

---

## Estado actual (cerrado — referencia)

- Migración PS1→C#/.NET 8 WPF completa (corte 6.3). C# única versión oficial.
- Bug del single-file publicado resuelto (`FileNotFoundException` de `System.Text.RegularExpressions`
  por caché de extracción parcial de `IncludeAllContentForSelfExtract`; fix: flag removido del
  pubxml + `SanitizeFileName` sin Regex).
- Regresión completa validada **sobre el .exe publicado**: optimización, backup/restore, licencias
  (cripto RSA OK) y auto-updater.
- Fases históricas de la migración (0.1–6.3) y desarrollo PS1 (41/41): detalle en CHANGELOG.md.

---

# MÓDULO 1 — Rediseño estético / UX-UI  ·  **PRIORIDAD ACTUAL**

Lo que sigue para la app. Referencia visual: Paragon PTU (dark premium; el 80% es dirección de
arte replicable con XAML, no ventaja técnica). El objetivo es **jerarquía, aire y pulido**, no
cambiar la paleta.

**Reglas que se mantienen (no negociables):**
- Acento único `#00C8FF` (hover `#33D6FF`, pressed `#0088BB`). Estados: ok `#22C55E` / warn `#F59E0B` / err `#EF4444` / info `#00C8FF`.
- Fondo `#0D0D0D` / cards `#161616`. Segoe UI. CornerRadius 4/6/8. Espaciado escala 4px. Sin emojis. Texto en español.
- **El rediseño es una fase independiente post-corte. Primero paridad funcional (ya lograda), después estética. Nunca mezclar las dos en el mismo cambio.**

Checklist en orden de ejecución:

- [x] **1. Sidebar de navegación vertical** (icono + label) en reemplazo de las tabs superiores.
      Escala mejor con las 8 secciones actuales y se lee como "producto", no "herramienta".
      Agrupación tentativa: Optimizar / Sistema / Avanzado / Ajustes. *(Cambio estructural #1.)*
      **HECHO (corte 25, ajustado en 26/27/30)**: sidebar full-height a la izquierda con bloque de
      marca (logo + versión + badge de licencia) arriba. Agrupación real (distinta a la tentativa
      original): grupo **PRINCIPAL** (Optimizar, Herramientas, Tuning Avanzado, Bloatware) y grupo
      **SISTEMA** (Arranque, Historial); **Home** (corte 30) como item propio arriba de ambos grupos,
      es la entrada de la app. Item activo con pill de fondo cyan (corte 26). Consola/Ajustes/
      Licencia bajaron a una fila de íconos al fondo del sidebar (corte 27); Consola abre un overlay
      modal en vez de navegar a una pestaña. Ver CHANGELOG (cortes 25, 26, 27, 30).
- [x] **2. Dashboard de entrada** con estado del sistema arriba (CPU/GPU/RAM detectados + score +
      CTA principal), en vez de abrir con una grilla fría de checkboxes. WinBoost ya tiene el score
      y la info de sistema: promover esa data a pantalla de entrada.
      **HECHO (corte 30, pulido en 31/32)**: Home es la entrada de la app y reemplazó a Info del
      sistema. Medidores circulares CPU/RAM/GPU en vivo (gauge custom con arco de progreso, no
      `ui:ProgressRing` — corte 31), malla de salud glossy con insights reales (Privacidad ahora
      afirmativa en 4/4 tras el fix del corte 32), card de última optimización desde Historial,
      botones glossy sin escalón en el reflejo (corte 31), y overlay System Info (hardware +
      componentes). Ver CHANGELOG.
- [ ] **3. Componente toggle estilizado reutilizable** que reemplace los checkboxes de sistema en
      todas las secciones. Detalle chico, gran impacto en percepción de calidad.
      **Parcial**: los 3 controles de Tuning Avanzado (Scheduler CPU, HAGS, Política Térmica) ya
      usan `ui:ToggleSwitch` de WPF-UI (corte 16B, "16B_tuning_toggleswitch.txt") — pero es solo esos
      3 controles. Los checkboxes de Optimizar/Bloatware (los que este ítem apunta a reemplazar)
      recibieron únicamente un restyle visual (vidrio translúcido + borde acento, corte
      "15_adopcion_paso1_checkbox.txt"), siguen siendo `CheckBox`, no un componente toggle. El ítem
      sigue pendiente en su alcance completo. Nota de dirección (2026-08-20, feedback directo del
      usuario, no negociable): la pestaña Optimizar en particular necesita una remodelación mayor de
      arquitectura/diseño (tarjetas por tweak con toggle propio, categorías/tabs, buscador, sin
      checkboxes, ítems de limpieza de archivos separados a una sección "Limpieza" aparte) — este
      ítem probablemente se quede chico frente a ese alcance; evaluar expandirlo o reemplazarlo
      cuando se planifique esa remodelación.
- [ ] **4. Subir padding/espaciado global** (usar los escalones altos de la escala 4px). La UI
      actual aprieta; el rediseño pide más aire en pantallas de entrada/decisión.
- [ ] **5. Reforzar jerarquía tipográfica** (Segoe UI en varios pesos): títulos claramente más
      pesados que el cuerpo, valores numéricos/métricas destacados en tamaño.
- [ ] **6. Palanca de transparencia en cada card de tweak:** línea de "qué hace" + acceso al
      detalle (qué clave toca y por qué). Es el diferenciador que el segmento esconde; deja el
      hueco para el explicador IA (Módulo 2).
- [ ] **7. Panel de métricas before/after graficado** (diferenciador honesto vs. los % de
      marketing de la competencia; el score medido por Event ID, bien graficado, se ve igual de
      premium). ⚠️ Si incluye temperaturas/RPM → resolver primero la **decisión PawnIO /
      LibreHardwareMonitor** (ver "Decisiones registradas").
- [ ] **8. Diálogos y notificaciones propios** (reemplazan los MessageBox nativos grises + sonido
      de error de Windows, que rompen la estética y se ven amateur, sobre todo en el paywall):
      un componente de diálogo dark reutilizable (info / confirmación / bloqueo Pro), quitar/suavizar
      el sonido de error, y convertir el bloqueo Pro en oportunidad de venta (comunicar el valor y
      el upgrade, no un portazo "requiere Pro"). Alcance: todos los MessageBox de la app.
- [ ] **9. Splash de carga al iniciar:** pequeño logo de WinBoost centrado con una animación del
      trueno azul (prende/apaga o similar) como transición hasta que la app termina de levantar.
      Cubre el hueco entre el doble clic y la aparición de la ventana (hueco real en single-file
      self-contained: el runtime tarda un momento en levantar). Nota técnica: en single-file el
      splash debe aparecer ANTES de que cargue el grueso de la app (no es un control más de la
      ventana; tiene su truco de implementación). Definir la animación exacta y el mecanismo en la
      fase de diseño.
- [x] **10. Resolución definitiva/predeterminada y quitar el maximizar/pantalla completa.** La app
      se ve estirada y desproporcionada al maximizar (contenido diseñado para un tamaño concreto);
      fullscreen no aporta y empeora el aspecto. Fijar un tamaño (o un rango acotado con mín/máx) y
      deshabilitar el maximizar. Pendiente de decidir en la fase de diseño: tamaño FIJO (no
      redimensionable) vs. rango con mínimo y máximo sensatos. Es un cambio de "amateur → terminado"
      (las apps de escritorio pulidas que no son editores/navegadores no se maximizan a fullscreen).
      **RESUELTO**: tamaño FIJO 1000x720, `ResizeMode="CanMinimize"`, maximizar sacado de la
      TitleBar + guard de `StateChanged`. Ver CHANGELOG. El aprovechamiento del espacio extra que
      deja el alto nuevo queda para los pasos de rediseño de pantallas.

Densidad: buscar el punto medio — aire en pantallas de entrada/decisión, densidad donde el técnico
opera (no caer en "limpio" que hace poco por pantalla).

---

# MÓDULO 2 — Nuevas funcionalidades (backlog priorizado)

**Regla:** todo esto es desarrollo post-corte en C#. Nada entra al PS1 legacy. Orden por valor real
vs. esfuerzo, tal como está clasificado en el benchmark competitivo.

## Infraestructura transversal (habilita varios items)

- [ ] **Proxy backend.** Protege la API key del explicador IA **y** ancla la integridad del trial
      (ver Módulo 3, licencias). Se construye una vez y desbloquea dos frentes; embeber la key en
      el .NET es inseguro (decompilación IL trivial).

## Prioridad 1 — Feature #1 del segmento

- [ ] **Perfiles por juego** (reemplazo del Game Focus Mode dado de baja). Detectar juegos
      instalados escaneando Steam (`steamapps\common`); lista con toggle por juego (off gris /
      on `#00C8FF`); toggle ON = auto-aplicar prioridad alta **cada vez** que el juego arranca.
      Requiere un **componente residente en background** (tray/servicio que arranca con Windows y
      vigila el lanzamiento de procesos, modelo Process Lasso) → **cambio de arquitectura**: WinBoost
      deja de ser "solo la app que abrís". Es la feature #1 del nicho (Paragon/Hone la venden como
      premium). Definir: consumo del watcher, convivencia app/servicio.
- [ ] **Explicador IA** (premium, diferenciador difícil de copiar). Claude Haiku explica en lenguaje
      simple qué hace cada tweak; el motor determinista ejecuta. Requiere el proxy backend (arriba).
      Refuerza la palanca de transparencia del Módulo 1 (item 6).

## Prioridad 2 — Quick wins (barato + alto valor percibido)

- [ ] **Fixes de un click** (pestaña Herramientas; en C# van como `Process` asíncrono, nunca
      bloquear UI):
      - Reset Network (`netsh int ip reset` + `winsock reset`) — winsock **requiere reinicio**:
        avisar y ofrecer reiniciar.
      - System Corruption Scan (`sfc /scannow` + `DISM /RestoreHealth`) — 10–30+ min: **salida en
        vivo a la pestaña Consola** (redirección async de stdout), botón cancelar, y lock para que
        no corran dos a la vez. DISM necesita internet / WU funcional.
      - Reset Windows Update (re-registrar DLLs + reiniciar servicios).
      - WinGet Reinstall (restaurar winget si falla) — **implementar antes** que el instalador WinGet.
      - Set Up Autologin — **debilita la seguridad**: gate con advertencia explícita + confirmación;
        candidato a tier Técnico.
- [ ] **Paneles legacy de Windows** (`Process.Start` de cada `.cpl`/comando; trivial, sin riesgo):
      Control Panel, `ncpa.cpl`, `powercfg.cpl`, `intl.cpl`, `mmsys.cpl`, `sysdm.cpl`, `netplwiz`.
- [ ] **DNS — más proveedores** (el selector ya existe; el hint debe explicar qué filtra cada uno):
      Cloudflare Security `1.1.1.2/1.0.0.2`, Cloudflare Family `1.1.1.3/1.0.0.3`, AdGuard
      `94.140.14.14/94.140.15.15`, AdGuard Family `94.140.14.15/94.140.15.16`, Quad9
      `9.9.9.9/149.112.112.112`. Confirmar IPv6 equivalentes.

## Prioridad 3 — Medianas (evaluar)

- [ ] **Presets de Windows Update empresariales** (vía HKLM Policies): Default (limpia políticas —
      el más valioso, mucha gente llega con updates rotos por otros tweakers), Security/Recomendado
      (deferral feature 365d / security 4d), Disable ALL (solo sistemas aislados). Detectar edición
      y **avisar honestamente en Home** (varias políticas de deferral no se respetan). Documentar
      qué claves toca cada preset + undo por BackupService.
- [ ] **Windows Features toggle** (DISM): seguros → .NET (2/3/4), Legacy Media, F8 Recovery, NFS.
      ⚠️ Hyper-V/WSL/Sandbox requieren reinicio + virtualización, y **Hyper-V activa VBS** (costo de
      FPS + conflicto con anticheats — contramano del pitch gaming): si se agregan, tier Técnico con
      advertencia explícita, o recortar la lista. "Daily Registry Backup" programado: sinergia
      natural con BackupService + auto-mantenimiento.
- [ ] **Export/Import config** (paridad de automatización): `WinBoost.exe -Silent -Config perfil.json`
      (el JSON sale del export del item 3.7). Esfuerzo bajo sobre la infra ya validada; venta directa
      al tier Técnico.
- [ ] **Power plan con identidad propia** ("Plan WinBoost") — quick win de marketing, el preset de
      energía ya existe.
- [ ] **Automatización de drivers (versión honesta):** detectar desactualizados + **linkear al
      driver oficial**. NUNCA instalar automáticamente. (El instalador WinGet cubre parte.)
- [ ] **Tests de red como diagnóstico:** latencia, jitter, DNS. NO "packet optimization" mágica.
- [ ] **Guía BIOS educativa** por fabricante. Tocar BIOS desde la app **JAMÁS** (la competencia
      tampoco lo hace: es guía asistida vendida como premium).
- [ ] **OpenSSH Server** (nicho Técnico): `Add-WindowsCapability` + sshd + regla firewall :22. Abre
      superficie de ataque real → solo Técnico, con advertencia, y el toggle de apagado revierte
      TODO (servicio + firewall).

## Prioridad 4 — Feature estrella (v5.0, esfuerzo alto)

- [ ] **Instalador de apps vía WinGet** (tipo Ninite integrado): Install/Upgrade Selected, Upgrade
      All, Uninstall, Get Installed, buscador con filtro en vivo. **Catálogo chico y curado**
      (gaming + esenciales), no replicar los cientos de WinUtil. Implementar el fix "WinGet Reinstall"
      antes. Testear los paquetes bajo admin (contexto máquina se comporta distinto). Sinergia con el
      modo CLI. Justifica prensa y reactivación de usuarios.

## Re-evaluar / deuda de producto

- [ ] **Purga de RAM (Standby List):** falla con `STATUS_PRIVILEGE_NOT_HELD` (el
      `AdjustTokenPrivileges` "tiene éxito" sin habilitar el privilegio; no se verifica GetLastError).
      Bug heredado del PS1. Decisión: **arreglar el P/Invoke O sacar/degradar por placebo** (Windows
      gestiona la Standby solo; forzar la purga rara vez mejora y vacía caché útil). Alineado con la
      marca anti-placebo → sacar/degradar. La liberación de Working Set (real) se conserva en
      cualquier caso.
- [x] **Bug: el health score muestra Privacidad 3/4 aunque se apliquen TODOS los tweaks de la
      sección Privacidad y Telemetría.** **RESUELTO (corte 32)**: causa raíz = `CheckTasks` parseaba
      la salida LOCALIZADA de `schtasks` (`.Contains("Disabled")`), que en Windows español dice
      "Deshabilitado" → daba false → 3/4. Confirmado en vivo en la máquina del usuario (es-ES). Fix:
      leer `Enabled` (bool, sin idioma) via la API COM `Schedule.Service` (late-bind por reflection).
      Privacidad → 4/4 en cualquier idioma. Ver CHANGELOG. (Era la misma familia que el bug de la
      política térmica.)

---

# MÓDULO 3 — Obligatorio para salir al mercado

## Bloqueante de distribución

- [ ] **Code signing** — certificado OV (~100–200 USD/año; Sectigo, DigiCert o GlobalSign). EV da
      reputación inmediata en SmartScreen pero es más caro (token hardware). La migración a C# ya
      eliminó el falso positivo Wacatac de ps2exe; falta la **firma para la reputación de
      SmartScreen**. Integrar en `Publish-CSharp.ps1` al obtenerlo. Complementos: reportar el binario
      a Microsoft ("Submit a file for analysis") y verificar el FP en VirusTotal.
  - [ ] **Verificación de firma Authenticode en el updater** (depende de code signing). Tras descargar
        el instalador y **antes de `ApplyUpdate`**, verificar que esté firmado con el certificado de
        WinBoost (`Get-AuthenticodeSignature` / `WinVerifyTrust`) y abortar si el firmante no es el
        esperado. Cierra el hueco: hoy la integridad se apoya solo en el SHA256, que sale del mismo
        `version.json` que el `DownloadUrl` (no protege contra repo comprometido) y el instalador
        corre en silencio y elevado. Archivos: `UpdateService.cs` (ApplyUpdate) + el flujo de
        MainWindow. *Resto del ciclo (Check/Download/gate SHA256/Apply+relaunch) ya validado OK.*

## Modelo de licencias — rediseño (prerequisito para vender)

No se puede lanzar comercialmente con el modelo actual. Cripto validada OK (RSA-2048, Pro atado a
HWID, rechazo de claves inválidas/HWID ajeno, persistencia). Dos debilidades de **diseño** a resolver
en el rediseño:

- [ ] **Trial sin integridad** (client-side burlable): fecha futura → cientos de días; borrar
      `settings.json` → trial nuevo repetible; resetear la fecha a hoy → trial eterno; atrasar el
      reloj → no avanza. Objetivo: anclar al **proxy backend**; mitigación intermedia sin server =
      HMAC del estado + anclaje redundante (registro/archivo) + anti-rollback de reloj.
- [ ] **Clave Tech = llave maestra global** (firma sobre la constante `WINBOOST-TECH`, sin variable →
      `Gen-License.ps1` genera siempre la misma cadena; una clave desbloquea cualquier PC para
      siempre, sin revocación). Regla a adoptar: **toda clave que valga dinero firma sobre algo único**
      (mínimo el HWID). Destino: degradar Tech a testing interno, O reconstruirla como tier de pago
      único (lifetime/ULTRA) firmando `WINBOOST-<TIER>-<HWID>(-<comprador>)`.
- Dirección tentativa del modelo definitivo: degradar Tech; tier **ULTRA** sobre Pro (pasar el gating
  booleano `IS_PRO`/`IS_TECH` a **niveles ordenables** + mensaje de firma por tier); bajar el trial de
  14 a **3–7 días** (evaluar junto con qué otorga el trial, hoy da Pro completo).

## Pre-lanzamiento

- [ ] **Testing externo en Win10 y Win11 limpios, SOBRE EL .EXE PUBLICADO** (self-contained
      single-file de `Publish-CSharp.ps1`, no el Debug) — regresión completa: optimización al 100%,
      backup/restore revierte valores reales, bloatware, licencias Free/Pro/Tech, auto-updater,
      escaneo de driver store. Pasar a 2-3 personas de confianza, usar sin explicarles nada, traer
      bugs al chat.
- [ ] **Auditar la base de datos de bloatware.** Bug encontrado: 3 entradas de Xbox tenían nombres de
      paquete viejos (`XboxGamingOverlay`/`GamingApp`/`Xbox.TCUI` → `XboxGameOverlay`/`XboxApp`/
      `XboxGameCallableUI`) y daban "0 detectados" en Windows moderno; ya se arreglaron aceptando ambos.
      Pendiente: revisar las ~55 entradas contra `Get-AppxPackage` en un Win11 limpio y actualizado,
      aceptar alias `viejo|nuevo` donde aplique, verificar categoría y flag de riesgo. Una detección
      que se pierde apps mina la confianza (el usuario ve "sistema limpio" cuando no lo está).
- [ ] **Auditoría de parseo de salidas de CLI independiente de idioma.** El código lee la salida de
      comandos (`powercfg`, `pnputil`, `netsh`, `sc`, etc.) y en varios lugares matchea TEXTO
      LOCALIZADO en inglés (o inglés+español a mano), lo que falla en Windows en otros idiomas —
      crítico para el mercado LATAM (español y portugués/Brasil): funciona en dev (inglés), falla en
      la máquina del usuario real. Ya corregido: `GetCoolingPolicyState` (política térmica) ahora lee
      del registro, independiente de idioma. También corregido: `CheckTasks` del health score (corte
      32) ahora lee `Enabled` via la API COM del Task Scheduler en vez de parsear `schtasks`
      ("Deshabilitado" vs "Disabled"). **Verificados OK, sin bug real (corte 33)** — se habían
      reportado como sospechosos pero la verificación en la máquina real (Windows 10 es-ES) los
      descartó: `CheckHpet` (`SystemInfoService.cs` ~línea 181, `bcdedit /enum` buscando
      `disabledynamictick`+`"Yes"`) — confirmado que `bcdedit` **no localiza** sus valores booleanos
      Yes/No (se probaron 4 elementos BCD distintos, todos mostraron "Yes" en español); y
      `CheckTcpTuning`/RSS (~línea 329, `netsh int tcp show global`) — ya tenía un fix bilingüe
      (etiqueta ES/EN + valor "enabled" no localizado), confirmado funcionando con la salida real de
      `netsh` en español. Ninguno de los dos se tocó (ver CHANGELOG). **Corregido, con limitación
      documentada (corte 34):** `ParsePnpUtil()` (`TuningService.cs`, detección de drivers obsoletos)
      matcheaba solo inglés+español y fallaba en portugués (mercado real: Brasil) — la lista de
      drivers quedaba vacía en ese idioma, sin error visible. Se investigó migrar a una fuente
      estructurada (WMI `Win32_PnPSignedDriver`, flag `/format` de pnputil, API nativa del Driver
      Store) y se descartó cada una con evidencia real (WMI no ve paquetes obsoletos/superseded, sin
      `/format` en `/enum-drivers`, API nativa desproporcionada) — detalle completo en CHANGELOG. Se
      extendió el regex a **trilingüe (en/es/pt-BR)**. Español validado end-to-end contra la salida
      real de `pnputil` (42/42 paquetes, sin regresión). **Los literales en portugués-BR NO se
      pudieron verificar contra una máquina real ni una fuente de Microsoft con ejemplo de salida real
      — quedan como mejor estimación documentada, pendiente de validación en un Windows en
      portugués real** cuando haya oportunidad de probar. Revisar también cualquier otro
      `RunCapture`/parseo de stdout que quede en el código (barrido no exhaustivo).
- [ ] **Compatibilidad de la ventana fija con pantallas chicas y escala DPI.** La ventana quedó en
      tamaño FIJO 1000x720 no redimensionable (Módulo 1 item 10), así que el usuario no puede
      achicarla si no le entra. Los 720px **lógicos** entran en una pantalla de 768px SOLO al 100%
      de escala de Windows: al 125% (muy común en laptops 1366x768 de gama baja/media, frecuente en
      LATAM y default de fábrica en muchos equipos) se renderizan como ~900px **físicos**, no entran,
      y la ventana queda cortada abajo sin salida. Mismo patrón que el bug de idioma de la política
      térmica y la auditoría de bloatware: funciona en dev (pantalla grande / escala 100%), falla en
      la máquina del usuario real. Decidir estrategia antes del lanzamiento (opciones a evaluar, NO
      implementar aún):
      - Bajar el alto lógico a un valor que entre incluso a 125% en 768px (~560-580px lógicos —
        apretado, hay que ver si el contenido entra sin sacrificar el diseño).
      - Detectar la resolución/escala efectiva al iniciar y ajustar el tamaño (o escalar el
        contenido) de forma adaptativa.
      - Permitir un modo "compacto" alternativo para pantallas chicas.
      - Documentar explícitamente la resolución/escala mínima soportada y no soportar por debajo.

      Validar la decisión en un 1366x768 real a 125%, no solo en el dev box.
- [ ] **Landing page:** before/after de métricas reales (las genera el reporte HTML de WinBoost),
      lista de tweaks documentados, estructura de planes (Free/Pro/[ULTRA]) con precios, botón de
      descarga al release de GitHub, sección "Qué cambia exactamente" (desarma el escepticismo de
      Reddit/foros).
- [ ] **Página de metodología pública** (la "landing de confianza"): cómo se mide el boot time, qué
      toca cada tweak, por qué se removió `Win32PrioritySeparation`. **Nadie del segmento la tiene.**
      Barata, alto diferencial.
- [ ] **Primer feedback real** (3-5 usuarios: conocidos, Discord, foros de gaming). Feedback honesto
      (qué gustó, qué no funcionó, qué les parece el precio). Define la siguiente versión.

## Pulido del repo

- [ ] Topics: `windows`, `optimization`, `wpf`, `performance`, `gaming`.
- [ ] Descripción "About" del repo.
- [ ] Capturas de pantalla en el README (el texto ya está actualizado post-corte).

## Go-to-market (posicionamiento — define el lanzamiento, no es checklist técnico)

- **Pricing regional + pago único** como posicionamiento explícito contra la suscripción en USD de
  todo el nicho. Arma fuerte en LATAM.
- **El foso real es DISTRIBUCIÓN, no features** (Paragon y Hone son operaciones de marketing con
  software): Discord propio en español desde el día 1, afiliados con micro-influencers hispanos
  (baratísimos vs. anglo), presencia en comunidades LATAM de Valorant/CS2/Fortnite.
- Contra Hone no se pelea de frente (2.5M usuarios + Epic Games Store); se gana por flanco: mercado
  hispano mal atendido + usuario quemado por optimizadores que rompieron algo + pricing sin
  suscripción.
- **NO copiar:** token crypto, % de FPS inventados (destruyen la única ventaja defendible), login
  obligatorio para ver precios.

## Procedimiento de release (C#, actualizado — reemplaza el de la era PS1)

1. Bump de versión en `App.xaml.cs` (`internal const string Version` — fuente única; `Publish-CSharp.ps1` la lee).
2. `Publish-CSharp.ps1` (self-contained single-file) + compilar el instalador Inno (`src-csharp/installer/WinBoost.iss`, recibe `/DAppVersion`).
3. SHA256 del instalador → `version.json` (sha256 + downloadUrl a la nueva versión).
4. Publicar el release con el instalador como asset (nombre exacto = el del downloadUrl).
5. Push de `version.json` a `main`.
6. Verificar la raw URL + probar el update desde una versión anterior **sobre el .exe publicado**.

---

## Decisiones registradas (definir en su fase)

- **PawnIO vs LibreHardwareMonitor** (para temps/RPM del dashboard, Módulo 1 item 7). Windows no
  expone temperaturas por API de usuario → hace falta un driver kernel. PawnIO (firmado, RSA,
  reemplaza a WinRing0 —que Defender marca como malicioso—) es la opción moderna correcta.
  Advertencias: algunos anticheats bloquean `PawnIO.sys` → hay que poder **detener/descargar el
  driver al jugar** (sinergia con el watcher de perfiles por juego); usar SIEMPRE la edición firmada
  oficial (pawnio.eu), nunca test-signed; es driver kernel (riesgo de inestabilidad/BSOD, testear).
  Alternativa sin driver: limitar el monitoreo a CPU/RAM/GPU % (sin temps) — menos "wow", menos
  superficie de riesgo. Decisión de producto en la fase de dashboard.
- **Modelo de licencias definitivo** (ver Módulo 3).

## Descartado / No implementar

- Win11 Creator (MicroWin) — meses de trabajo, nicho, soporte infinito (cada build rompe algo).
- Lanzador de O&O ShutUp10++ / herramientas de terceros — contradice la marca (responder por tweaks ajenos).
- Benchmark de disco — CrystalDiskMark existe y es gratis.
- Verificación SHA256 del XAML — optimización prematura.
- Ofuscación del PS1 — irrelevante (PS1 jubilado a legacy).
- Verificación online de versiones de drivers — frágil (la automatización de drivers honesta la reemplaza).
- Runspace completo — superado por el async nativo de C#.

## Diferenciadores actuales (no perder de vista)

- Undo granular por tweak + historial visible de sesiones (Hone lo *dice*, WinBoost lo *muestra*).
- Métricas medidas en la máquina del usuario (boot time por Event ID, before/after real) vs. % de landing.
- Transparencia de qué hace cada tweak en la UI (+ explicador IA planificado) — nadie del segmento la tiene.
- Español nativo de verdad: producto + soporte + docs + comunidad, no una landing traducida.
- Licencia perpetua + pricing regional vs. suscripción en USD.
