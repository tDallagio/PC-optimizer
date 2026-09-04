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
      **HECHO (corte 25, ajustado en 26/27/30/56/66/78)**: sidebar full-height a la izquierda con
      bloque de marca (logo + versión + badge de licencia) arriba. Estructura real de HOY: grupo
      **PRINCIPAL** (Tweaks, Network, Limpieza, Bloatware) y grupo **SISTEMA** (Herramientas, Arranque,
      Historial); **Home** (corte 30) como item propio arriba de ambos grupos, es la entrada de la
      app. Item activo con pill de fondo cyan (corte 26). Consola/Ajustes/Licencia en una fila de
      íconos al fondo del sidebar (corte 27); Consola abre un overlay modal en vez de navegar a una
      pestaña. Historia de la agrupación: al corte 30 era PRINCIPAL (Optimizar, Herramientas, Tuning
      Avanzado, Bloatware) / SISTEMA (Arranque, Historial); Tuning Avanzado se retiró en el corte 56
      (migrado a Tweaks), Optimizar clásico en el corte 66, y en el corte 78 se colapsaron los
      sub-headers sueltos de Tweaks/Network/Limpieza dentro de PRINCIPAL y Herramientas pasó a
      SISTEMA. Ver CHANGELOG (cortes 25, 26, 27, 30, 56, 66, 78).
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
      **Parcial (estado a corte ~16B)**: los 3 controles de Tuning Avanzado (Scheduler CPU, HAGS,
      Política Térmica) pasaron a `ui:ToggleSwitch` de WPF-UI (corte 16B, "16B_tuning_toggleswitch.txt")
      — pero solo esos 3 (y esa pestaña se retiró en el corte 56; los 3 controles viven ahora en
      Tweaks). Los checkboxes de Optimizar y de Bloatware (los que este ítem apuntaba a reemplazar)
      recibieron en su momento únicamente un restyle visual (vidrio translúcido + borde acento, corte
      "15_adopcion_paso1_checkbox.txt"): los de Optimizar se fueron con el tab clásico al retirarse en
      el corte 66; los de Bloatware siguen siendo `CheckBox`, no un componente toggle. El ítem sigue
      pendiente para las secciones que todavía usan `CheckBox`. Nota de dirección (2026-08-20,
      feedback directo del usuario, no negociable): la pestaña Optimizar (retirada después, corte 66)
      necesitaba una remodelación mayor de arquitectura/diseño (tarjetas por tweak con toggle propio,
      categorías/tabs, buscador, sin checkboxes, ítems de limpieza de archivos separados a una sección
      "Limpieza" aparte) — ver la ACTUALIZACIÓN de abajo: esa remodelación se construyó como
      arquitectura nueva y el tab clásico terminó retirándose.
      **ACTUALIZACIÓN (2026-08-24, Fases A/B/C completas; 2026-08-25, Power migrado — universo
      completo)**: la remodelación de arquitectura que pedía la nota de dirección de arriba ya se
      construyó y quedó validada con evidencia real, en paralelo al tab Optimizar clásico (a esa
      fecha todavía activo; **retirado completo en el corte 66** — ver el sub-ítem de abajo y
      `ARQUITECTURA_TWEAKS.md` 7.9). Arquitectura nueva: `TweakDefinition`/`TweakState` (On/Off/NoAplicable)/
      `TweakRegistry`/`TweakStateStore` (registro de tweaks individuales con revert real por tweak,
      persistencia propia en `tweak_state.json`, separada de `BackupService`). Secciones nuevas en
      el sidebar: **Tweaks** (Fase A/B + Power, 21 tweaks con toggle propio) y **Network** (Fase C —
      Nagle/TCP relocados sin cambio de lógica + DisableIPv6 nuevo + DNS con selector y revert real
      por adaptador + DNSFlush) y **Limpieza** (Fase C — 1 card con los 8 ítems de limpieza clásicos
      como checkboxes + botón ejecutar, sin revert — no aplica, borrar temporales nunca fue
      reversible ni en el tab clásico. **Corte 75**: la sección Limpieza sumó el checkbox "Caché
      profunda" —reemplazó al de "Thumbnails", que quedó subsumido, sin cambiar la cantidad neta de 8
      checkboxes— y dos bloques propios movidos desde Herramientas: **Mantenimiento automático** y
      **Limpieza del Driver Store**). TRIM/Desfrag se migró íntegro a **Herramientas** (reusa
      `App.Worker`/cancelación ya existente, no se forzó al patrón simple de acción rápida). Punto
      de restauración se agregó como card en **Home** (patrón `QuickActionDefinition`, con manejo
      honesto del límite de Windows de 1 punto cada 24hs). **Power** (plan de energía) se agregó
      después (prompt 51) a la sección Tweaks: texto honesto distinto por tipo de máquina (laptop
      vs. desktop, incluido el fallback real a "Alto Rendimiento" cuando falla la creación de
      "Ultimate Performance" — diagnosticado a fondo en el prompt 52, ya estaba bien contemplado sin
      necesitar ningún fix) y captura/revert de `standby-timeout-ac` (hueco de reversión que el
      mecanismo viejo de sesión, `BackupService.SavePowerPlanBackup`/`RestoreSession`, nunca cubrió).
      Revert de Power **confirmado con evidencia real sobre un original no trivial** (plan
      Equilibrado + hibernación encendida + `standby-timeout-ac` en 900s forzado como estado
      original): el original capturado en `tweak_state.json` coincidió exactamente con lo restaurado
      tras un ciclo On/Off completo.
      Con esto, **26 de los 26 tweaks individuales del tab clásico + el bloque de Limpieza ya tienen
      hogar en la arquitectura nueva — universo completo**. Detalle completo del mapeo tweak-por-
      tweak, los bugs reales encontrados en el camino (race condition en `TweakStateStore`, bug de
      idioma en el revert de TCP, casos de "asumir default en vez de leer el original real", revert
      de DNS con adaptadores huérfanos, etc.) y las divergencias respecto al plan original (sección
      5) están documentados en `ARQUITECTURA_TWEAKS.md`, sección 7. No se marca `[x]` porque queda
      pendiente:
      - [x] Decidir con Tomy si/cuándo retirar el tab Optimizar clásico — **retirado completo en el
            corte 66**: pantalla (XAML + `footerBar`) y code-behind exclusivo eliminados
            (`OnRunOptimizationAsync`, `FinishOptimizationAsync`, `ShowCompareDialog` + las clases
            `FinishOptimizationDialog`/`CompareDialog`, `ApplyPreset`, `AllOptCheckboxes`,
            `GetCurrentSel`, `SelectAll`, `UpdateDnsHint`, `UpdatePlanSummary`,
            `SaveProfile`/`LoadProfile`, `OptimizationService.BuildActionPlan`).
            `OptimizationService.RunAsync`/`GetPreset` se preservaron intactos — motor exclusivo del
            modo `-Silent` de CLI desde este corte. Probado por Tomy sobre el .exe publicado. Detalle
            completo en `ARQUITECTURA_TWEAKS.md` sección 7.9.
      - [ ] Validar en hardware o VM sin SSD real la rama `NoAplicable` (no-SSD) de
            SvcSysMain/SvcWSearch (Fase B, Tanda 4) — implementada y revisada contra el código, pero
            nunca ejercitada en vivo porque la máquina de build tiene SSD.
      - [ ] Hallazgo sin confirmar en vivo ni corregir (prompt 53): Power y FastStartup comparten el
            mismo `HibernateEnabled` de Windows — Fast Startup necesita hibernación habilitada para
            funcionar, Power la apaga por completo al activarse en desktop. Confirmado contra el
            código real que ninguno de los dos `LeerEstadoAsync` verifica el estado del otro tweak
            hoy, así que aplicar/revertir uno puede alterar en silencio lo que el otro reporta (ej.
            revertir FastStartup con Power todavía aplicado podría reactivar hibernación y
            desarmar parte de lo que Power dejó configurado, sin que ninguna de las dos cards lo
            avise). La decisión de cómo comunicarlo o resolverlo queda aparte, no tomada acá.
      - [x] Historial — confirmado que NO se degrada tras retirar el tab clásico (corte 66): la
            preocupación (diagnóstico prompt 54) era que, sin ningún flujo llamando
            `SaveSessionMetadata`, las stats agregadas y el gráfico de score quedaran congelados.
            `OptimizationService.RunAsync`/`GetPreset` no se tocaron — el modo `-Silent` sigue
            llamando `SaveSessionMetadata` exactamente igual, así que Historial sigue recibiendo
            sesiones con metadata completa (más las de Bloatware, sin metadata; su fila en Historial
            ya no ofrece "Revertir" desde el corte 69, ver abajo). Detalle en
            `ARQUITECTURA_TWEAKS.md` sección 7.6, hallazgo 1.
      - [x] Tuning Avanzado (Scheduler CPU, HAGS y Política térmica, los 3 controles ex-`ui:ToggleSwitch`
            del corte 16B) **ya no depende de `BackupService`** — migrado completo a
            `TweakRegistry`/`TweakStateStore` en el corte 56, pestaña retirada del sidebar
            (`SetWin32PrioritySep`/`SetHagsState`/`EnsureBackupSession` se eliminaron de
            `TuningService.cs`, sin caller). El mapa de dependencias de `BackupService`, **tras el
            retiro del tab Optimizar clásico en el corte 66**, queda: (a) el modo `-Silent` de CLI,
            (b) Bloatware. Detalle en `ARQUITECTURA_TWEAKS.md` sección 7.6.
      - [x] Bloatware: el botón "Revertir" de Historial sobre una sesión de desinstalación no
            reinstalaba nada — y **peor**, reportaba éxito falso (el diálogo prometía restaurar
            registro/servicios/red y, tras no hacer nada, la app decía "Sesión revertida
            correctamente… reinicia el equipo"). **Diagnosticado en el corte 68, resuelto en el
            corte 69.** El prompt 68 confirmó que un revert real no es viable de forma consistente
            (remoción = usuario + todos los usuarios + deprovisión de imagen, sin payload local;
            todo camino de vuelta —Store, winget, DISM— necesita internet, no es instantáneo, y
            varios casos no tienen solución real). Decisión de Tomy: se sacó el botón "Revertir"
            para las sesiones de Bloatware en Historial, **sin reemplazo** — la fila queda como
            registro informativo (badge "Bloatware", acción "—" inerte). Detección precisa vía
            `BackupSessionInfo.HasBloatwareRef` (presencia de `bloatware_removed.json`) +
            `IsBloatwareOnly` — deliberadamente NO se usó `HasMeta` solo (no es sinónimo exacto de
            "es Bloatware": un `-Silent` que muriera entre `NewBackupSession` y `SaveSessionMetadata`
            también daría `HasMeta=false`). `RestoreSession` endurecido con un guard explícito
            (loguea el motivo real y devuelve `false` en vez de recorrer sus 7 pasos en 0/0/0 y
            reportar éxito genérico). Segundo punto de entrada, no mapeado en el diagnóstico original
            y también corregido: `btnRevertLast` ("Revertir última sesión") ahora avisa en vez de
            revertir cuando la sesión más reciente es de Bloatware. Confirmado que no hay ningún otro
            camino (sin atajos de teclado, sin menú contextual, sin acción en lote). Probado por Tomy
            sobre el .exe publicado. Detalle en `ARQUITECTURA_TWEAKS.md` sección 7.6 (hallazgo 3) y
            7.10 (fix completo).
      - [ ] Bloatware — reinstalación automática (evaluar más adelante, sin compromiso): si algún
            día vale la pena construir un revert *real* (reinstalar lo desinstalado) para el
            subconjunto de apps de Store de consumo (Candy Crush, Bing*, etc.), donde `winget`/Store
            serían un camino técnicamente posible. El prompt 68 dejó la advertencia clara: **ningún
            camino es instantáneo ni offline**, y varios casos no tienen solución — apps de Xbox
            protegidas/aprovisionadas, Skype (discontinuado por Microsoft), OEM que reinstalaría una
            versión distinta a la original, y "Microsoft Print to PDF" que ni siquiera es una app (es
            una feature de Windows, se restaura por DISM). Detalle en `ARQUITECTURA_TWEAKS.md`
            sección 7.5.
      - [x] Bug real (card "Última optimización" del Home sin filtrar `HasMeta`) — **resuelto en los
            cortes 62/63, no con un parche de filtro**: Tomy notó que el problema de fondo no era el
            filtro sino que los 4 datos de esa card (MB liberados, acciones, score, fecha) pertenecían
            por completo al mecanismo de sesión del tab clásico (retirado después en el corte 66). Se reemplazó la
            card entera (`UpdateLastOptCardAsync` y sus 4 campos ya no existen) por un contador en vivo
            de "Tweaks activos" (`TweakRegistry.All` + `LeerEstadoAsync`, cache en memoria con ajuste
            incremental), desacoplado por completo de `BackupService`/`BackupSessionInfo` — sin nada
            que filtrar porque ya no lee sesiones. El corte 63 además confirmó y corrigió una race
            condition real entre el barrido inicial y los ajustes incrementales. Detalle completo en
            `ARQUITECTURA_TWEAKS.md` sección 7.8.
      - [x] La comparativa antes/después (`ShowCompareDialog`) y el reporte HTML
            (`ExportHtmlReportAsync`) — **resuelto retirando el código, no reemplazándolo (corte
            66, decisión de producto de Tomy)**: en vez de dejarlos exportando/mostrando datos
            vacíos o desactualizados, `ShowCompareDialog`/`FinishOptimizationDialog`/`CompareDialog`
            se eliminaron por completo y `ExportHtmlReportAsync` se eliminó con su botón
            (`btnExportHTML`, vive en el overlay de Consola) oculto explícito. Detalle en
            `ARQUITECTURA_TWEAKS.md` sección 7.6, hallazgo 5.
      - [ ] Nota menor: `CleanupOldBackups(keepDays)` en `BackupService.cs` no tiene ningún caller en
            todo el árbol — parece código muerto, sin relación directa con el tab clásico, candidato a
            limpieza de repo.
      - [ ] Onboarding: el paso de selección de perfil quedó pausado sin diseño real (corte 66). Se
            sacó del wizard (aplicaba `ApplyPreset`, eliminado junto con el tab clásico) sin construir
            ningún reemplazo — hace falta diseñar de fondo cómo elegir un perfil podría tener un
            efecto real contra la arquitectura nueva (aplicar un subconjunto de tweaks vía
            `TweakRegistry`, o rediseñar el paso para que no prometa algo que no hace) antes de poder
            reintroducirlo. `OnboardingDialog` quedó en 3 pasos (hardware, score, listo). Detalle en
            `ARQUITECTURA_TWEAKS.md` sección 7.9.
      - [ ] Tweaks/Network sin mecanismo de "aplicar varios de una" (decisión de alcance, corte 66):
            se evaluó construirlo al retirar el tab clásico y se decidió NO hacerlo en ese corte —
            evaluar más adelante, según uso real, si hace falta selección múltiple + aplicar en
            bloque para Tweaks/Network (mismo patrón que ya tiene Limpieza). Prioridad baja, sin
            fecha. Detalle en `ARQUITECTURA_TWEAKS.md` sección 7.9.
      - [x] Mapeo de "defaults seguros de Windows" para una acción "Restablecer a un valor
            predeterminado" (prompt 57 diagnóstico; **implementado en el corte 71**): de los 27
            `TweakDefinition` reales de `TweakRegistry.All`, 20 tienen un default de Windows confiable
            para ofrecer (Telemetry, SvcDiag, Tasks, PageFile, PowerThrot, MouseAccel, GameMode,
            Cortana, Notif, Nagle, Visual, SvcXbox, SvcWER, SvcMaps, HPET, FastStartup, SvcSysMain,
            SvcWSearch, DisableIPv6, HAGS) y 7 son riesgosos/inciertos, sub-divididos en **Grupo A**
            (aproximable con advertencia explícita — la mayoría de fuentes coincide aunque no sea 100%
            universal: TCP, GPUPrio, GameDVR, SvcFax) y **Grupo B** (sin ningún valor defendible,
            ofrecer uno sería inventarlo: Power —puntualmente `standby-timeout-ac`, el GUID de plan sí
            tiene un default razonable en Equilibrado—, Win32PrioritySep, PoliticaTermica —el caso más
            incierto de los 27, ni "restablecer a Equilibrado" resuelve nada porque el propio
            Equilibrado varía por OEM—). Motivo real del hallazgo: si un tweak ya está On desde antes
            de tocar el toggle (config externa del usuario, o una sesión vieja de WinBoost)
            `TweakStateStore` nunca capturó un original, y no había forma de apagarlo desde la app
            salvo editando el registro a mano ("Revertir" queda como no-op honesto, no es un bug) —
            que es exactamente lo que la acción nueva resuelve para los 20 Seguro.
            Detalle completo (tabla de los 27 + las 4 opciones de alcance evaluadas) en
            `ARQUITECTURA_TWEAKS.md` sección 7.7. **Alcance decidido (corte 71): opción A — solo los
            20 Seguro.** Se construyó "Restablecer a default de Windows" como acción separada de
            "Revertir", rotulada honestamente como valor de fábrica (no el original de esta máquina),
            visible solo cuando el tweak es uno de los 20 + está On + no hay `Original` capturado
            (reusa el mismo `HasEntry` que bloquea "Revertir"). Los 7 Riesgoso quedan sin la acción,
            con el bloqueo honesto sin cambios. Durante la implementación se corrigió el mapeo de
            GameMode (`AllowAutoGameMode` no es un default de fábrica → se borra, no se escribe un
            valor). Detalle de la implementación en `ARQUITECTURA_TWEAKS.md` sección 7.11; mecanismo
            por tweak en `CHANGELOG.md` (corte 71). Probado por Tomy sobre el .exe publicado.
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

- [ ] **Proxy backend.** Protege la API key del explicador IA — embeber la key en el .NET es
      inseguro (decompilación IL trivial). *(Antes este ítem también se justificaba como ancla de
      integridad del trial; el trial se eliminó en el corte 82, ver Módulo 3 → "Modelo de licencias".
      Si el rediseño de licencias suma validación/revocación server-side, ese pasaría a ser el
      segundo frente que lo justifica.)*

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
HWID, rechazo de claves inválidas/HWID ajeno, persistencia). Puntos de **diseño** a resolver en el
rediseño — **van juntos**: qué se gatea para Free y qué tiers existen son una sola decisión, no dos
aisladas. (La tercera pata —qué hacer con el trial— ya se resolvió por separado: se eliminó, corte 82.)

- [x] **Trial sin integridad** (client-side burlable) — **RESUELTO eliminando el trial por completo
      (corte 82)**, no mitigándolo. El problema: el estado vivía solo en
      `%USERPROFILE%\.OptimizarPC\settings.json` (`TrialStartDate` + `TrialExpired`), sin ancla de
      máquina ni server — fecha futura → cientos de días; borrar `settings.json` (o basura en
      `TrialStartDate`, que caía en un `catch` que regalaba 14 días nuevos) → trial repetible; resetear
      la fecha a hoy → trial eterno; atrasar el reloj → no avanzaba. Las mitigaciones que este ítem
      tenía planteadas (HMAC del estado, anclaje redundante registro/archivo, anti-rollback de reloj,
      proxy backend) **quedaron descartadas** — decisión de Tomy (diagnóstico del mecanismo completo en
      el prompt 81, implementación en el corte 82): se sacó el trial entero, no se blindó.
      `EvaluateTrial()` eliminado, `RefreshFromStored()` como único evaluador (`IsPro`/`IsTech` solo
      con licencia Pro/Tech real), `TrialStartDate`/`TrialExpired` fuera de `AppSettings`,
      `LockProFeature` con un mensaje único sin mención de trial, banner y badge de trial de Home
      eliminados sin reemplazo. Detalle en `CHANGELOG.md`, entrada **"Eliminación del trial gratuito
      de 14 días (82_eliminar_trial_gratuito.txt)"**.
- [ ] **Clave Tech = llave maestra global** (firma sobre la constante `WINBOOST-TECH`, sin variable →
      `Gen-License.ps1` genera siempre la misma cadena; una clave desbloquea cualquier PC para
      siempre, sin revocación). Regla a adoptar: **toda clave que valga dinero firma sobre algo único**
      (mínimo el HWID). Destino: degradar Tech a testing interno, O reconstruirla como tier de pago
      único (lifetime/ULTRA) firmando `WINBOOST-<TIER>-<HWID>(-<comprador>)`.
- [ ] **Gate de Pro perdido para casi toda la app** (efecto colateral no advertido del corte 66). El
      único gate que cubría los tweaks/servicios era el botón "Ejecutar" del tab Optimizar clásico
      (`OnRunOptimizationAsync`, gateado con `LockProFeature` desde la fase 5.1); los toggles por
      tweak nunca estuvieron gateados (desde el piloto de la Fase A, corte 38). Al retirar el tab
      clásico en el corte 66 no quedó **ningún** gate sobre la aplicación de tweaks, y el CHANGELOG
      del 66 no registra que se haya considerado. Hoy un usuario Free usa sin restricción: todos los
      tweaks (Tweaks + Network), "Restablecer a default de Windows", Limpieza
      de archivos, TRIM/Desfrag, selector de DNS + DNSFlush, liberador de RAM, punto de restauración
      y el score. Lo único que sigue con gate `LockProFeature` es **Desinstalar bloatware**,
      **Mantenimiento automático** (toggle + "Ejecutar ahora") y **Revertir sesión** de Historial
      (por fila y "Revertir última sesión"). **Decisión de Tomy (prompt 81): NO se restaura el gate
      todavía** — qué bloquear para Free se decide en conjunto con la eliminación del trial y el
      rediseño de tiers, no aislado. Sin cambio de código en el prompt 81.
- Dirección del rediseño (sin fecha): degradar Tech; planes **Free / Pro / Ultra** (se saca Tech, se
  agrega **Ultra** sobre Pro) — pasar el gating booleano `IS_PRO`/`IS_TECH` a **niveles ordenables** +
  mensaje de firma por tier. **El trial de 14 días ya se eliminó por completo (corte 82)** — decisión
  de Tomy (prompt 81), reemplazó a la idea previa de acortarlo a 3–7 días; ver el ítem "Trial sin
  integridad" arriba.

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
      portugués real** cuando haya oportunidad de probar. **Nuevo hallazgo (2026-08-24, detectado
      durante la Fase A/piloto, prompt 39):** el mecanismo viejo `BackupService.RestoreNetshFromSession()`
      (paso de red dentro de `RestoreSession`; su caller principal era el revert del tab Optimizar
      clásico hasta que se retiró en el corte 66 — hoy `RestoreSession` lo alcanzan el revert por
      fila de Historial sobre sesiones `-Silent` y el path de Bloatware, ya guardado) tenía el mismo
      tipo de bug de idioma que ya se encontró y se corrigió en el revert nuevo de TCP del registro
      de tweaks (`TweakRegistry.cs`) —
      pero el fix se aplicó solo ahí; `RestoreNetshFromSession()` en sí **no se tocó** y queda como
      sospechoso sin confirmar/corregir. Agregar a este barrido cuando se llegue a esta tarea (detalle
      en `ARQUITECTURA_TWEAKS.md` sección 7.4). Revisar también cualquier otro `RunCapture`/parseo de
      stdout que quede en el código (barrido no exhaustivo).
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
      toca cada tweak, cómo se eligió cada valor (ej. por qué `Win32PrioritySeparation` usa 0x28 en
      vez del viejo preset "Responsividad" 0x24 — nota corregida en el prompt 56: el tweak sigue
      activo como toggle opt-in, nunca se removió). **Nadie del segmento la tiene.** Barata, alto
      diferencial.
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
