# WinBoost — Arquitectura de Tweaks (Optimizar)

> Documento de trabajo/planificación para la rearquitectura de la pestaña Optimizar: pasar de
> checkboxes + selección/Aplicar a **toggles inmediatos por tweak** (prender = aplica ya, apagar =
> revierte ya). Generado por análisis de código real (no de la UI/descripciones), previo a
> implementar nada. Excluye Limpieza de Archivos (va a una sección propia "Limpieza").
>
> Fuentes: `OptimizationService.cs` (Apply real), `SystemInfoService.cs` (lectores de estado
> existentes, vía health score), `BackupService.cs` (precedente de reversión, hoy a nivel de sesión
> completa, no por tweak individual).
>
> **ACTUALIZACIÓN 2026-08-24**: las Fases A, B y C descritas como plan en este documento ya se
> implementaron y validaron por completo. Las secciones 1-6 quedan como registro histórico del
> análisis previo a implementar (varias de sus predicciones/decisiones NO coinciden con lo que
> terminó pasando en la práctica). **Ver Sección 7 al final para el estado real post-implementación**
> — es la fuente de verdad actual, no las secciones 4-5. La **pestaña Optimizar** que las secciones
> 1-6 analizan en presente ya **no existe**: se retiró completa en el corte 66 (7.9), una vez que
> los 26 tweaks + Limpieza tuvieron hogar en la arquitectura nueva.

---

## 1. Cifra real

**28 tweaks** en la pestaña Optimizar, excluyendo Limpieza de Archivos (8 checkboxes: Temp usuario,
Temp sistema, Prefetch, Cache Win Update, Cache navegadores, Thumbnails, Papelera, Logs de eventos).
El usuario estimaba ~25; la cifra real confirmada contra el XAML y `OptimizationService.BuildActionPlan`
es **28**, agrupados así en la UI actual:

- Sistema y Rendimiento: 10
- Privacidad y Telemetría: 6
- Red y Conectividad: 5
- Servicios Innecesarios: 7

---

## 2. Familias de lectura de estado (definición de trabajo)

- **Familia 1 — Registro directo**: clave/valor simple, comparar y listo. Precedente:
  `CheckTelemetry`/`CheckGameDvr`/`CheckCortana` en `SystemInfoService.cs`.
- **Familia 2 — Servicios de Windows**: `ServiceController.StartType`, estructurado.
- **Familia 3 — Tareas programadas**: API COM `Schedule.Service` (precedente: `CheckTasks`,
  corte 32 — reemplazó el parseo de texto de `schtasks`).
- **Familia 4 — CLI frágil** (powercfg/netsh/bcdedit): requiere el mismo cuidado que la política
  térmica / HPET / TCP (cortes previos) — verificar en vivo qué localiza el comando antes de decidir
  el mecanismo; NUNCA asumir.
- **Variante WMI** (no listada explícitamente en el prompt original, pero aparece 2 veces): el tweak
  se aplica y se puede leer vía clases WMI estructuradas (`Win32_PageFileSetting`,
  `Win32_NetworkAdapterConfiguration`) — tan robusto como Familia 1, pero no es "registro" ni
  "servicio" en sentido estricto. Se listan aparte para no forzarlos en una familia que no describe
  el mecanismo real.
- **CASO ESPECIAL**: no es un tweak ON/OFF limpio (acción de un solo disparo, sin estado persistente
  verificable, o sin operación inversa clara/segura).

---

## 3. Inventario completo

### 3.1 Sistema y Rendimiento (10)

| Tweak (id) | Qué hace (Apply real) | Familia | Lector ya existe | Reversible / notas |
|---|---|---|---|---|
| **Power** | `PowerPlanTweaks()`: desktop → activa/crea plan "Ultimate Performance" (`powercfg -duplicatescheme` de un GUID semilla + `-setactive`, matcheo de nombre bilingüe EN/ES ya resuelto) + `hibernate off` + `standby-timeout-ac 0`; **laptop → solo `SCHEME_MIN` (Alto Rendimiento)**, sin Ultimate ni hibernate off. | 4 (CLI, pero ya semi-robusto: compara por GUID, no por texto, salvo al buscar el plan por nombre bilingüe) | No hay `Check*` en el health score. Existe building-block reusable: `BackupService.SavePowerPlanBackup()` ya extrae el GUID activo actual vía regex (no localizado) antes de aplicar. | Reversible: `RestoreSession` ya restaura GUID previo + hibernate (`powerplan` action). `standby-timeout-ac` NO se respalda ni se revierte hoy (hueco). **Caso a decidir**: comportamiento distinto laptop/desktop — qué significa "toggle ON" en laptop. |
| **HPET** | `HpetTweaks()`: `bcdedit` — `deletevalue useplatformclock`, `set useplatformtick yes`, `set disabledynamictick yes`. | 4 (CLI) — **ya verificado robusto** (corte 33): `bcdedit` no localiza sus valores Yes/No en Windows español, confirmado en vivo. | Sí — `CheckHpet()` (`SystemInfoService.cs`). | Reversible: `RestoreHpetFromSession()` ya implementado (borra los 3 valores BCD). **Probablemente requiere reinicio** para que el sistema vuelva a usar el timer original (no confirmado explícitamente en comentarios del código, a diferencia de PageFile). |
| **GPUPrio** | `RegistryTweaks()`: 5 valores bajo `...Multimedia\SystemProfile\Tasks\Games` (GPU Priority=8, Priority=6, Scheduling Category=High, SFIO Priority=High, Background Only=False). | 1 | Sí — `CheckGpuPrio()` (solo valida `GPU Priority>=8`, no los otros 4 valores — cobertura parcial). | Reversible sin reinicio: `SetReg()` ya hace `SaveRegBackup()` por clave antes de escribir; import de `.reg` ya funciona (`RestoreRegFromSession`). |
| **PowerThrot** | `RegistryTweaks()`: `PowerThrottlingOff=1`. | 1 | Sí — `CheckPowerThrot()`. | Reversible sin reinicio, mismo mecanismo que arriba. |
| **Visual** | `VisualTweaks()`: `VisualFXSetting=2`, `FontSmoothing="2"`, + condicional `EnableTransparency=0` si RAM≤8GB. | 1 | Sí — `CheckVisual()` (solo valida `VisualFXSetting`, no `FontSmoothing` ni la transparencia condicional). | Reversible sin reinicio (reg backup). |
| **MouseAccel** | `RegistryTweaks()`: `MouseSpeed=0`, `MouseThreshold1/2=0` (HKCU) + `MouseDataQueueSize=20` (HKLM `mouclass`). | 1 | Sí — `CheckMouseAccel()` (solo valida `MouseSpeed`, no el valor HKLM). | Reversible sin reinicio conocido (HKCU es inmediato; el valor HKLM de `mouclass` no está confirmado si necesita reenumeración de dispositivo — no se afirma con certeza). |
| **Startup** ("Punto restauración") | `CreateRestorePoint()`: `Enable-ComputerRestore` + `Checkpoint-Computer` — **crea un snapshot AHORA**, no es un estado persistente. | **CASO ESPECIAL** | No aplica (no hay "estado" que leer — un restore point es un evento, no un flag). | **No es togglable limpiamente**: no hay "revertir la creación de un punto de restauración" con sentido, ni un "OFF" claro. Necesita decisión de producto (¿sale del modelo de toggle? ¿se pliega al flujo de Ejecutar? ¿queda como botón "Crear ahora"?). |
| **FastStartup** | `FastStartupTweaks()`: `HiberbootEnabled=0` (reg) + `powercfg /hibernate off`. | 1 (la señal primaria es el registro) | Sí — `CheckFastStartup()`. | **Matiz de reversión**: el reg backup restaura `HiberbootEnabled`, pero NO vuelve a correr `powercfg /hibernate on` — hibernate podría quedar sin `hiberfil.sys` aunque el flag diga 1. Revert hoy sería incompleto sin lógica custom (como HPET/PageFile la tienen). |
| **PageFile** | `PageFileTweaks()`: WMI — `Win32_ComputerSystem.AutomaticManagedPagefile=false` + crea `Win32_PageFileSetting` con min/max calculado, borra los anteriores. | WMI estructurado (no textual, tan robusto como Familia 1) | No hay `Check*` en el health score (se podría leer vía `Win32_PageFileSetting`/`AutomaticManagedPagefile`, estructurado). | Reversible: `SavePageFileBackup()`/`RestorePageFileFromSession()` **ya implementados completos**. **REQUIERE REINICIO** — explícito en el código y en los logs ("Cambio efectivo tras reinicio") en ambas direcciones. |
| **TrimDesfrag** | `TrimTweaksAsync()`: habilita tarea `ScheduledDefrag` (schtasks) + si SSD: `fsutil behavior set DisableDeleteNotify 0` + **ejecuta `Optimize-Volume -ReTrim` YA MISMO** en cada SSD. | Mixto: Familia 3 (tarea programada) + Familia 4 (fsutil, aunque ya lee por valor numérico `"= 1"`, no texto localizado — ya robusto) + **acción no reversible** (el TRIM en sí). | No hay `Check*`. | **CASO ESPECIAL**: mezcla un estado togglable (tarea + flag fsutil) con una acción de un solo disparo sin operación inversa (no se puede "deshacer" un TRIM). Necesita decisión: ¿se separa en "TRIM semanal automático" (toggle) + "Ejecutar TRIM ahora" (botón aparte)? |

### 3.2 Privacidad y Telemetría (6)

| Tweak (id) | Qué hace (Apply real) | Familia | Lector ya existe | Reversible / notas |
|---|---|---|---|---|
| **GameDVR** | `RegistryTweaks()`: 4 valores (HKCU `GameConfigStore` x3 + HKLM Policies `AllowGameDVR`). | 1 | Sí — `CheckGameDvr()` (solo valida `GameDVR_Enabled`, no las otras 3). | Reversible sin reinicio (reg backup). |
| **GameMode** | `RegistryTweaks()`: `AutoGameModeEnabled=0`, `AllowAutoGameMode=0` (HKCU `GameBar`). | 1 | **No** — confirmado ausente del health score (ya anotado en PENDIENTES como decisión previa, no bug). | Reversible sin reinicio. |
| **Telemetry** | `RegistryTweaks()`: `AllowTelemetry=0` en DOS ubicaciones (`Policies` + `CurrentVersion\Policies`). | 1 | Sí — `CheckTelemetry()` (solo valida la primera ubicación). | Reversible sin reinicio. |
| **Cortana** | `RegistryTweaks()`: `AllowCortana=0` (HKLM Policies). | 1 | Sí — `CheckCortana()`. | Reversible sin reinicio. |
| **Notif** | `RegistryTweaks()`: `ToastEnabled=0` (HKCU). | 1 | **No** — confirmado ausente del health score (misma decisión previa que GameMode). | Reversible sin reinicio. |
| **Tasks** | `RegistryTweaks()`: `schtasks /change /tn "..." /disable` sobre **5** tareas (Compatibility Appraiser, ProgramDataUpdater, Consolidator, UsbCeip, DiskDiagnosticDataCollector). | 3 (tareas programadas) — Apply usa CLI `schtasks`, pero ya existe el mecanismo COM robusto (`CheckTasks`, corte 32) para LEER. | Sí, parcial — `CheckTasks()` solo verifica **3 de las 5** tareas que Apply toca (falta ProgramDataUpdater y UsbCeip). | **No existe reversión hoy** (ni en `BackupService` ni en ningún flujo) — apagar una tarea vía `schtasks /disable` nunca se revierte. Trivial de construir con el mismo mecanismo COM (`Enabled=true`), pero falta. |

### 3.3 Red y Conectividad (5)

| Tweak (id) | Qué hace (Apply real) | Familia | Lector ya existe | Reversible / notas |
|---|---|---|---|---|
| **Nagle** | `NetworkTweaks()`: por cada adaptador con `DhcpIPAddress` activo, `TcpAckFrequency=1` + `TCPNoDelay=1`. | 1 (multi-instancia por adaptador, pero lectura de registro directa). | Sí — `CheckNagle()` (basta 1 adaptador con el valor, coincide con el criterio de Apply). | Reversible sin reinicio: pasa por `SetReg()`, backup automático. |
| **TCP** ("TCP/IP gaming"; health score: `TCPTuning`) | `NetworkTweaks()`: 4 comandos `netsh` (autotuning=normal, chimney=disabled, rss=enabled, fastopen=enabled). Backup previo dedicado: `SaveNetshBackup()`. | 4 (CLI) — **ya verificado robusto** (corte 33) solo para el criterio RSS. | Sí, parcial — `CheckTcpTuning()` solo verifica RSS, no los otros 3 parámetros. | Reversible sin reinicio: `RestoreNetshFromSession()` **ya implementado completo** (reaplica los 4 valores desde el backup de texto). |
| **DNS** (+ `cboDNSProvider`) | `NetworkTweaks()`: WMI `SetDNSServerSearchOrder` en todos los adaptadores con IP habilitada. | WMI estructurado. | Sí — `CheckDns()` (compara contra IPs conocidas de los 4 proveedores). | Reversible sin reinicio: `SaveNetBackup()`/`RestoreNetworkFromSession()` **ya implementados completos** (DNS previo + binding IPv6 por adaptador). |
| **DNSFlush** | `ipconfig /flushdns`. | **CASO ESPECIAL** | No aplica — vaciar la caché no deja estado verificable. | No es togglable: es una acción puntual sin "revertir" con sentido (no se puede "rellenar" la caché). |
| **DisableIPv6** | `NetworkTweaks()`: `DisabledComponents=0x20` (`Tcpip6\Parameters`). | 1 | **No** — ausente del health score. | Reversible vía reg backup (pasa por `SetReg()`). **Posible necesidad de reinicio** del stack de red para efecto completo — no confirmado con certeza en el código, marcar a validar. |

### 3.4 Servicios Innecesarios (7)

| Tweak (id) | Qué hace (Apply real) | Familia | Lector ya existe | Reversible / notas |
|---|---|---|---|---|
| **SvcXbox** | `DisableSvc()` x3: `XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`. | 2 | Sí — `CheckSvcXbox()` (≥2 de 3). | Reversible sin reinicio: `DisableSvc()` ya llama `SaveSvcBackup()`; `RestoreServicesFromSession()` **ya implementado completo** (modo de inicio + re-arranque si corresponde). |
| **SvcDiag** | `DisableSvc("DiagTrack")`. | 2 | Sí — `CheckSvc("DiagTrack")`. | Reversible sin reinicio, mismo mecanismo. |
| **SvcWER** | `DisableSvc("WerSvc")`. | 2 | Sí — `CheckSvc("WerSvc")`. | Reversible sin reinicio, mismo mecanismo. |
| **SvcSysMain** | `DisableSvc("SysMain")` — **solo si `hasSsd`** (si no, se omite/skip). | 2 | **No** — ausente del health score. | Reversible sin reinicio, mismo mecanismo. **Matiz condicional**: en HDD, Apply no hace nada — qué debe mostrar/hacer el toggle en ese caso es una decisión de UX, no técnica. |
| **SvcMaps** | `DisableSvc()` x2: `MapsBroker`, `lfsvc`. | 2 | **No** — ausente del health score (faltaría un `CheckSvcMaps` análogo a `CheckSvcXbox`). | Reversible sin reinicio, mismo mecanismo. |
| **SvcFax** | `DisableSvc()` x2: `Fax`, `RemoteRegistry`. | 2 | Sí — pero con un criterio más laxo: `CheckSvc("Fax") \|\| CheckSvc("RemoteRegistry")` (OR, basta 1 de 2; distinto del `>=2 de 3` de Xbox). Nota si se reutiliza para el toggle. | Reversible sin reinicio, mismo mecanismo. |
| **SvcWSearch** | `DisableSvc("WSearch")` — **solo si `hasSsd`**. | 2 | **No** — ausente del health score. | Reversible sin reinicio, mismo mecanismo. Mismo matiz condicional que SvcSysMain. |

---

## 4. Resumen final

### 4.1 Total

**28 tweaks reales** (excluyendo Limpieza de Archivos). Con la decisión de arquitectura registrada en
la sección 5 (casos especiales resueltos), el universo que efectivamente necesita el patrón completo
Aplicar/Revertir/LeerEstado en Optimizar para la Fase A/B queda en **25** — ver sección 5 para el
detalle y el porqué del número.

### 4.2 Por familia

| Familia | Cantidad | Tweaks |
|---|---|---|
| 1 — Registro directo | 12 | GPUPrio, PowerThrot, Visual, MouseAccel, FastStartup, GameDVR, GameMode, Telemetry, Cortana, Notif, Nagle, DisableIPv6 |
| 2 — Servicios | 7 | SvcXbox, SvcDiag, SvcWER, SvcSysMain, SvcMaps, SvcFax, SvcWSearch |
| 3 — Tareas programadas | 1 | Tasks |
| 4 — CLI frágil | 3 | HPET, TCP, Power |
| WMI estructurado (variante, no listada en las 4 originales) | 2 | PageFile, DNS |
| Caso especial | 3 | Startup (punto de restauración), TrimDesfrag, DNSFlush — **RESUELTO, ver sección 5**: los 3 tienen decisión de destino tomada, ya no son "a decidir". |
| **Total** | **28** | |

De los 17 que ya tienen lector en el health score (`SystemInfoService.cs`), varios son **parciales**
(verifican solo una parte de lo que Apply realmente escribe): GPUPrio, Visual, MouseAccel, GameDVR,
Telemetry, TCP, Tasks. Esto importa para el toggle inmediato: un lector parcial puede mostrar "ON"
aunque falte alguna de las claves secundarias, o viceversa tras una reversión parcial externa.

### 4.3 Requieren reinicio (o tienen matiz de reinicio) para revertir

- **PageFile** — confirmado explícito en el código ("Cambio efectivo tras reinicio").
- **HPET** — probable (timers a nivel de arranque), no confirmado explícitamente en comentarios.
- **DisableIPv6** — posible, no confirmado con certeza.
- **FastStartup** — no es "requiere reinicio" en sentido estricto, pero el revert de solo-registro
  hoy es incompleto (falta re-ejecutar `powercfg /hibernate on`).

### 4.4 Casos especiales (decisión de producto antes de convertir a toggle)

**Duros (no son ON/OFF limpio) — RESUELTOS, ver sección 5 para la decisión completa:**
1. **Startup** (Punto de restauración) — acción de un solo disparo, sin estado ni operación inversa.
   → Sale de Optimizar, va a Herramientas.
2. **TrimDesfrag** — mezcla un estado togglable (tarea + flag fsutil) con una acción de TRIM
   inmediato no reversible. → Se parte: toggle queda en Optimizar, botón "Ejecutar TRIM ahora" aparte.
3. **DNSFlush** — acción pura, sin estado persistente verificable. → Sale de Optimizar, va a
   Herramientas.

**Matices menores (sí son togglables, pero con algo a decidir):**
4. **Power** — comportamiento distinto laptop/desktop (en laptop nunca activa Ultimate Performance
   ni desactiva hibernate); qué significa "toggle ON" en cada caso.
5. **SvcSysMain** / **SvcWSearch** — condicionados a `hasSsd`; qué debe mostrar/hacer el toggle en HDD.
6. **Tasks** — el lector actual solo cubre 3 de las 5 tareas que Apply toca; y no existe reversión
   hoy (hay que construirla, aunque el mecanismo COM ya existe).

### 4.5 Propuesta de piloto (5-6 tweaks)

Elegidos para cubrir cada familia + un caso de reinicio + un caso especial, con la menor cantidad
posible:

| # | Tweak | Por qué |
|---|---|---|
| 1 | **Telemetry** | Familia 1 (registro directo), peso alto en el score, ya con lector — el caso más simple para validar el patrón base. |
| 2 | **SvcDiag** (DiagTrack) | Familia 2 (servicios), 1 solo servicio, ya con lector + reversión completos — valida servicios de punta a punta. |
| 3 | **Tasks** | Familia 3 (tareas programadas). Lector parcial existente, **sin reversión** — el piloto obliga a construir el revert que falta, validando ese hueco real. |
| 4 | **TCP** (TCP/IP gaming) | Familia 4 (CLI), lector parcial pero robusto (corte 33) + reversión completa ya existente (`RestoreNetshFromSession`) — valida el patrón "CLI frágil resuelto" de punta a punta. |
| 5 | **PageFile** | Único con reinicio CONFIRMADO explícitamente + reversión completa ya existente — valida cómo se comunica "requiere reinicio" en un toggle inmediato. |
| 6 | **TrimDesfrag** (mitad toggle: TRIM/Desfrag automático semanal) | Ya NO es un caso especial híbrido (decisión tomada, ver sección 5: se partió en toggle + botón separado). El piloto ahora valida el toggle normal de la tarea programada (Familia 3 + fsutil) — el botón "Ejecutar TRIM ahora" es un elemento de UI aparte, fuera del alcance del piloto de toggles. |

---

## 5. Decisión de arquitectura — destino de los casos especiales (registrado 2026-08-21, NO implementado)

> Cierre del análisis de las secciones 3-4: los 3 "casos especiales duros" (Startup, TrimDesfrag,
> DNSFlush) ya tienen decisión de producto tomada. Esta sección SOLO registra la decisión para
> retomarla en una sesión futura sin reconstruir el razonamiento — la implementación es Fase A/B,
> todavía no arrancó.
>
> **NOTA (ver Sección 7)**: al implementarse de verdad, dos de estas decisiones CAMBIARON respecto
> a lo registrado acá. Dejalo como está por valor histórico, pero no lo tomes como el estado final.

**Principio general adoptado**: Optimizar queda reservado EXCLUSIVAMENTE a tweaks **TOGGLEABLES**
(estado persistente ON/OFF con Aplicar/Revertir/LeerEstado). Cualquier ítem que sea una **ACCIÓN DE
UN SOLO DISPARO** (sin estado ON/OFF real) NO pertenece a Optimizar — pertenece a **Herramientas**,
que pasa a ser la sección de "acciones de mantenimiento de un click".

**Resolución de los 3 casos especiales:**

- **DNSFlush** → **SALE** de Optimizar. Va a Herramientas, junto a las futuras herramientas de un
  click (Reset Network, y a futuro SFC/DISM, Reset Windows Update). **NO se crea una pestaña nueva de
  "Red y Conectividad"**: los tweaks togglables de Red (Nagle, DisableIPv6, TCP, DNS) **se quedan** en
  Optimizar, sección Red y Conectividad, sin cambios.
- **Startup** (crear punto de restauración) → **SALE** de Optimizar, mismo motivo (acción de un solo
  disparo, sin ON/OFF). Va a Herramientas, junto a las demás acciones de mantenimiento de un click.
- **TrimDesfrag** → se **PARTE en dos controles separados**:
  1. Un **toggle** para la tarea programada automática (togglable de verdad — sigue en Optimizar).
  2. Un **botón** de acción "Ejecutar TRIM ahora" aparte (no togglable — destino sin definir todavía:
     ¿Optimizar como botón suelto junto al tweak, o Herramientas? queda abierto para cuando se
     implemente).

**Consecuencia en el conteo**: con estos 3 fuera del modelo toggle, el universo de tweaks que
necesitan Aplicar/Revertir/LeerEstado individual en Optimizar queda en **25** (28 menos DNSFlush,
Startup, y TrimDesfrag como ítem combinado — su mitad togglable reaparece como un toggle nuevo y más
simple dentro de ese universo, ya no como el híbrido original; su mitad-botón queda fuera del conteo
de toggles por definición, no tiene `LeerEstado`).

**Nota importante — fuera de alcance de este documento**: el rediseño de **Herramientas** (que va a
recibir estos ítems + las futuras herramientas de un click) es su propio proyecto grande, ya
identificado por el usuario como pendiente al mismo nivel de prioridad que Optimizar. **NO se aborda
ni se planifica en detalle acá** — solo queda registrado que estos 3 ítems (o 2 y medio) tienen
destino ahí, para cuando llegue su turno.

---

## 6. Notas para la implementación (no accionar todavía)

- El mecanismo de reversión hoy vive a nivel de **sesión completa** (`BackupService`): un solo
  `.reg`/`session.json` por corrida de Optimizar, no por tweak individual. El toggle inmediato
  necesita desacoplar esto — cada tweak necesita poder guardar y restaurar su propio estado anterior
  sin depender de una "sesión" completa creada al ejecutar todo el plan.
- Varios lectores de estado son **parciales** (ver 4.2) — antes de usarlos como fuente de verdad del
  toggle, decidir si conviene completarlos (leer TODO lo que Apply escribe) o aceptar la cobertura
  parcial como suficiente señal.
- Los 3 casos especiales duros ya NO están "a decidir" (ver sección 5): DNSFlush y Startup salen a
  Herramientas; TrimDesfrag se parte en toggle (queda) + botón (aparte). El rediseño de Herramientas
  que los va a recibir es un proyecto propio, no planificado en este documento.

---

## 7. Estado real post-implementación (Fases A, B y C — cerradas 2026-08-24)

> Esta sección es la fuente de verdad actual. Las secciones 1-6 son el análisis/plan previo a
> implementar (2026-08-21) y quedan como registro histórico — varias de sus predicciones y
> decisiones NO coinciden con lo que se implementó realmente. Detalle completo corte por corte en
> `docs/CHANGELOG.md` (prompts 38 a 50); acá solo el resumen de destino final y estado de validación.

### 7.1 Arquitectura implementada

- **Modelo de datos**: `TweakDefinition` (Id, Nombre, Descripcion, Categoria, RequiereReinicio,
  AplicarAsync, RevertirAsync, LeerEstadoAsync) + enum `TweakState` (On/Off/NoAplicable) +
  `TweakStatus` (estado + motivo, para que NoAplicable viaje con explicación hasta la UI). Vive en
  `TweakRegistry.cs`.
- **Persistencia por-tweak**: `TweakStateStore.cs` (`tweak_state.json` en `%USERPROFILE%\.OptimizarPC\`),
  separado a propósito de `BackupService`/`BackupModels` (sesión completa). Protegido con `lock` tras
  un bug real de concurrencia encontrado durante la Tanda 1 (ver 7.4).
- **Segundo patrón, para lo que NO es on/off**: `QuickActionDefinition`/`QuickActionRegistry`
  (`Id`, `Nombre`, `Descripcion`, `Func<Task<string>> EjecutarAsync`), sin estado, sin
  `TweakStateStore`. Nació en el Paso 2 de la Fase C (DNSFlush) y se reusó para el punto de
  restauración en Home. **NO se usó** para TRIM/Desfrag (ver 7.3) porque esa acción ya tenía
  cancelación/progreso propios que este patrón simple no cubre.
- **Secciones de sidebar nuevas**: **Tweaks** (piloto, Fase A) y, agregadas después en la Fase C:
  **Network** y **Limpieza**. Además se sumaron acciones puntuales en **Herramientas** (TRIM/Desfrag)
  y **Home** (punto de restauración). Al principio cada una colgaba de su propio sub-header suelto en
  el sidebar (segmento propio, separado de PRINCIPAL/SISTEMA); en el **corte 78** esos 3 sub-headers
  se eliminaron y Tweaks/Network/Limpieza pasaron a vivir **dentro del grupo PRINCIPAL** junto a
  Bloatware (orden: Tweaks, Network, Limpieza, Bloatware), mientras que **Herramientas** bajó a
  **SISTEMA** (con Arranque e Historial). Reordenamiento puramente visual — los índices de `TabItem`
  y `_navButtons` no cambiaron (ver 7.9).
- El tab **Optimizar clásico** no se tocó en esta etapa (Fases A/B/C) — siguió aplicando los mismos
  tweaks + Limpieza por su cuenta, en paralelo. **Retirado completo en el corte 66** (ver 7.9), una
  vez migrado el universo completo de tweaks individuales.

### 7.2 Destino final por tweak (26 de 26 migrados — universo completo)

| Categoría original | Tweaks | Destino final |
|---|---|---|
| Sistema y Rendimiento | HPET, GPUPrio, PowerThrot, Visual, MouseAccel, FastStartup, PageFile | Sección **Tweaks** |
| Sistema y Rendimiento | TrimDesfrag | **Herramientas** (acción única, NO se partió en toggle+botón — ver 7.3) |
| Sistema y Rendimiento | Startup (punto de restauración) | **Home** (QuickAction) |
| Sistema y Rendimiento | **Power** | Sección **Tweaks** (prompt 51, texto honesto por tipo de máquina — ver 7.4) |
| Privacidad y Telemetría | GameDVR, GameMode, Telemetry, Cortana, Notif, Tasks | Sección **Tweaks** |
| Red y Conectividad | Nagle, TCP, DisableIPv6 | Sección **Network** (toggle) |
| Red y Conectividad | DNS | Sección **Network** (selector + revert real, NO es TweakDefinition) |
| Red y Conectividad | DNSFlush | Sección **Network** (QuickAction) |
| Servicios | SvcXbox, SvcDiag, SvcWER, SvcSysMain, SvcMaps, SvcFax, SvcWSearch | Sección **Tweaks** (7/7 completo) |
| Limpieza de archivos | TempUser, TempSys, Prefetch, WinUpdate, Browsers, Thumb, Recycle, EventLogs | Sección **Limpieza** (1 sola card, selección múltiple + ejecutar, sin revert — no aplica) |

> **Corte 75** (rediseño de Herramientas — fuera del alcance de este documento, ver Sección 5): en la
> card de Limpieza de archivos el checkbox `Thumb` se reemplazó por uno nuevo, **"Caché profunda"**
> (subsume esa limpieza y además reinicia el Explorador, vía `MaintenanceService.DeepCleanAsync`); la
> clave `Thumb` de `CleanupTweaks` se conserva porque los presets `-Silent` la usan. Con eso la card
> quedó en 8 checkboxes (no cambió la cantidad neta). La sección **Limpieza** dejó de ser solo esta
> card: recibió dos bloques propios movidos desde Herramientas (**Mantenimiento automático**, **Driver
> Store**). Detalle en `docs/CHANGELOG.md`.

### 7.3 Divergencias reales respecto a la Sección 5 (decisión original)

La decisión de 2026-08-21 (Sección 5) NO se cumplió tal cual en dos puntos — quede anotado para que
no confunda a quien lea este documento de ahora en más:

1. **Sí se creó una pestaña "Network"**, contra lo que decía la Sección 5 ("NO se crea una pestaña
   nueva de Red y Conectividad"). Tomy cambió de decisión durante la Fase C: todos los tweaks de Red
   (Nagle, TCP, DisableIPv6, DNS, DNSFlush) se agruparon en su propia sección, separada de Tweaks.
2. **TrimDesfrag NO se partió en toggle + botón.** Se migró completo como una única acción a
   Herramientas, reusando el mecanismo ya existente `App.Worker` (`WorkRunner.cs`) + el overlay de
   Consola (el mismo que ya usaba la optimización completa y el desinstalador de bloatware) —
   cancelación real vía el botón "Detener" ya cableado genéricamente, sin agregar UI propia. No quedó
   ningún toggle de "TRIM semanal automático" separado en Tweaks/Optimizar.

### 7.4 Bugs reales encontrados y corregidos durante la implementación

Detalle completo en `docs/CHANGELOG.md` por corte; resumen:

- **Race condition en `TweakStateStore`** (Tanda 1): `Dictionary` compartido + `File.WriteAllText`
  sin lock, perdía entradas bajo escritura concurrente (189/200 corridas en el reproductor aislado).
  Fix: `lock` envolviendo los 5 métodos del store, incluida la escritura a disco.
- **Bug de idioma en el revert de TCP** (piloto, prompt 39): el parseo de `netsh int tcp show global`
  para reconstruir el original usaba un regex en inglés, fallaba en Windows es-ES. Se corrigió
  portando el mismo criterio ya validado en `CheckTcpTuning` (token "escalado" + valor no localizado).
  **Bug idéntico sigue sin arreglar en `BackupService.RestoreNetshFromSession`** (el mecanismo viejo
  de sesión completa) — nunca se tocó porque quedó fuera de alcance de ese prompt. Agregado al
  backlog de auditoría de idioma en `PENDIENTES.md`.
- **MouseAccel — dos causas reales distintas** (prompt 43): `MouseDataQueueSize` es un parámetro de
  driver (`mouclass.sys`) que solo se relee al cargar el driver — requiere reinicio, igual que
  PageFile. `MouseSpeed`/`MouseThreshold1/2` se cachean a nivel de sesión de Windows — la escritura
  cruda al registro persiste pero no se aplica en vivo sin llamar a
  `SystemParametersInfo(SPI_SETMOUSE, ...)` (la misma API que usa el Panel de Control). Fix:
  `NativeMethods.SetMouseAcceleration` llamado tras cada escritura, en Aplicar y Revertir.
  `RequiereReinicio` quedó en `true`.
- **"Asumir default en vez de leer el original real"**, encontrado y corregido dos veces: en GPUPrio
  (Tanda 1, valores de registro que no existían de fábrica) y en HPET (Tanda 3,
  `RestoreHpetFromSession` borraba los 3 valores BCD siempre sin haber leído nada antes). Mismo
  patrón de bug, dos lugares distintos.
- **DNS — bug de adaptador sin entrada capturada** (Paso 2, Fase C): la primera versión de
  `RestoreAsync` forzaba "automático" en cualquier adaptador sin entrada en el original guardado, sin
  distinguir "nunca existía cuando se capturó" (ej. una VPN conectada después) de "sí existía y no se
  guardó nada". Corregido para saltear esos adaptadores, mismo criterio que ya usa el revert de Nagle.
- **Checkers de health-score reusados donde no correspondía**: `CheckSvcXbox` (≥2 de 3, proxy laxo) y
  `CheckSvc("Fax") || CheckSvc("RemoteRegistry")` (OR) son correctos para el score tolerante de Home,
  pero se hubieran comportado como placebo parcial en el toggle de Tweaks. Se construyeron
  `LeerEstadoAsync` dedicados con criterio estricto (AND / todos) para SvcXbox y SvcFax, sin tocar los
  checkers del audit de Home.
- **Punto de restauración — límite de 24hs de Windows** (Paso 5, Fase C): `CreateRestorePoint` no
  tirar excepción no confirma que Windows haya creado un punto nuevo (por política, no deja crear más
  de uno cada 24hs). Se resolvió comparando `Get-ComputerRestorePoint` antes/después; si no sube el
  conteo, el mensaje se lo dice explícitamente al usuario en vez de un "listo" genérico.
- **Power — el resumen previo a implementar no tenía el detalle completo de `PowerPlanTweaks`**
  (prompt 51): confirmado contra el código real que `standby-timeout-ac=0` se aplica **siempre**, en
  las dos ramas (el llamado está fuera del `if/else isLaptop`; el análisis previo daba esto como "no
  confirmado" para laptop), y que en laptop Apply **no** toca hibernación (no hay ningún
  `/hibernate` en esa rama). El hueco de reversión que el mecanismo viejo
  (`BackupService.SavePowerPlanBackup`/`RestoreSession`) nunca cubrió —
  `standby-timeout-ac` no se capturaba ni se restauraba, revertir dejaba la pantalla/espera en 0 para
  siempre — se cerró capturando los 3 valores (GUID del plan, `HibernateEnabled`,
  `standby-timeout-ac` en segundos) directo en `TweakStateStore` antes de aplicar por primera vez.
  Lectura de `standby-timeout-ac` sin parsear texto localizado: `powercfg /q` de un solo setting
  imprime siempre 5 valores hex en el mismo orden estructural fijo sea cual sea el idioma — se toma
  el 4to por posición, no por la etiqueta. **Revert confirmado con evidencia real sobre un original
  no trivial** (plan Equilibrado + hibernación encendida + `standby-timeout-ac` en 900s forzado como
  estado original, prompt 53 addendum): el original capturado en `tweak_state.json` coincidió
  exactamente con lo restaurado tras un ciclo On/Off completo.
- **Power — fallback real a "Alto Rendimiento" en desktop, diagnosticado sin encontrar bug**
  (prompt 52): `PowerPlanTweaks()` tiene una rama de fallback real a `SCHEME_MIN` ("Alto
  Rendimiento") cuando la creación/detección de "Ultimate Performance" falla — algo que el análisis
  previo a implementar no contemplaba. Se releyó el código real tal como quedó implementado en el
  prompt 51 y ya estaba bien resuelto: `LeerEstadoAsync` acepta los dos GUIDs como estados On
  válidos, el texto honesto (`Motivo`) distingue cuál de los dos quedó activo sin sugerir Ultimate
  Performance falsamente, y `AplicarAsync`/`RevertirAsync` son agnósticos al GUID resultante (nunca
  asumen cuál de las dos ramas tuvo éxito). No hizo falta ningún cambio de código.

### 7.5 Pendiente real (no resuelto, no es "decisión futura teórica" — son huecos concretos)

- **Decisión de retiro del tab Optimizar clásico — RESUELTA (corte 66).** Con los 26 tweaks
  individuales + Limpieza migrados a su propio hogar (universo completo, ver 7.2), el tab clásico
  quedó redundante en todo su contenido. Tomy decidió retirarlo: pantalla + code-behind exclusivo
  eliminados; `OptimizationService.RunAsync`/`GetPreset` preservados como motor exclusivo del modo
  `-Silent` de CLI. Detalle completo en 7.9. *(Se deja el ítem acá como registro del hueco que
  existía; ya no es un pendiente.)*
- **SvcSysMain/SvcWSearch — rama `NoAplicable` (sin SSD) implementada pero no validada en máquina
  real.** La máquina de Tomy tiene SSD; falta probarlo en una VM o equipo con disco mecánico real
  (ver CHANGELOG, Tanda 4).
- **Bug latente en `BackupService.RestoreNetshFromSession`** (ver 7.4) — mismo bug de idioma que ya
  se corrigió en el path nuevo de TCP, nunca corregido en el mecanismo viejo de sesión completa.
- **Power y FastStartup — hallazgo de incompatibilidad, sin confirmar en vivo ni corregir**
  (prompt 53). Los dos comparten el mismo `HibernateEnabled` de Windows: Fast Startup necesita
  hibernación habilitada para funcionar, Power la apaga por completo al activarse en desktop.
  Confirmado contra el código real que ninguno de los dos `LeerEstadoAsync` verifica el estado del
  otro tweak — aplicar/revertir uno puede alterar en silencio lo que el otro reporta (ej. revertir
  FastStartup con Power todavía aplicado podría reactivar hibernación y desarmar parte de lo que
  Power dejó configurado, sin que ninguna de las dos cards lo avise). Documentado a propósito sin
  arreglar — la decisión de cómo comunicarlo o resolverlo queda aparte.
- **Bloatware — reinstalación automática: evaluación futura, sin compromiso.** El mensaje de éxito
  falso del botón "Revertir" para sesiones de Bloatware ya se resolvió (cortes 68 diagnóstico / 69
  fix: botón sacado, `RestoreSession` endurecido, `btnRevertLast` también cubierto — ver 7.6 hallazgo
  3 y 7.10). Lo que queda abierto es si algún día vale construir un revert *real* (reinstalar lo
  desinstalado) para el subconjunto donde sería posible. El prompt 68 clasificó por qué no es
  trivial — **ningún camino es instantáneo ni offline** (la remoción de WinBoost es usuario + todos
  los usuarios + deprovisión de imagen → no queda payload local para re-registrar) y hay 5 grupos de
  apps con viabilidad distinta: (1) **Xbox protegidas/aprovisionadas** (Game Bar, Xbox App, Identity
  Provider, TCUI…) — la remoción ya falla seguido (`0x80070002`); cuando funciona, solo Store online.
  (2) **Store de consumo** (Candy Crush ×5, Bing News/Weather/…, WhatsApp, TikTok, Spotify,
  Solitaire, Groove, To Do, Clipchamp…) — solo reinstalación desde la Store, online, si siguen
  publicadas. (3) **winget / OEM** (HP, Dell, Lenovo, ASUS, Acer, McAfee, Norton) — `winget install`
  online, y la versión reinstalada no coincide con el bundle OEM original. (4) **appx+winget con
  casos discontinuados** (Skype, Teams personal) — Teams sí; **Skype fue discontinuado por Microsoft
  (mayo 2025)**, reinstalarlo hoy es probablemente imposible. (5) **"Microsoft Print to PDF"** — no
  es una app, es una característica opcional de Windows (se restaura por DISM /
  `Enable-WindowsOptionalFeature`), mecanismo aparte.
- **Onboarding: el paso de selección de perfil quedó pausado sin diseño real (corte 66).** Se sacó
  del wizard sin construir ningún reemplazo — hace falta diseñar de fondo cómo elegir un perfil
  podría tener un efecto real contra la arquitectura nueva antes de reintroducirlo. Detalle: 7.9.
- **Tweaks/Network sin "aplicar varios de una" (decisión de alcance, corte 66).** Se evaluó y se
  decidió no construirlo en ese corte — evaluar más adelante según uso real. Prioridad baja, sin
  fecha. Detalle: 7.9.

### 7.6 Diagnóstico de dependencias antes de retirar el tab clásico (prompt 54)

Diagnóstico de solo lectura (prompt 54, sin cambios de código) sobre qué dependía realmente del
tab Optimizar clásico y de `BackupService`, para no romper nada a ciegas al retirarlo (retiro
efectivo en el corte 66, ver 7.5 y 7.9). Cinco hallazgos reales — **todos resueltos desde entonces**
(en los cortes 56, 62/63, 66 y 68/69); cada uno lleva abajo su estado real y la referencia concreta.

1. **Historial se degrada solo parcialmente — confirmado que NO se degrada en la práctica (corte
   66).** `RefreshHistoryAsync`/`RenderHistoryItems` (`MainWindow.xaml.cs`) leen
   `App.Backup.GetBackupSessions()` sin filtrar metadata — la lista cruda y el revert por fila
   (`InvokeRevertSessionAsync` → `BackupService.RestoreSession`, que restaura contra la carpeta de
   sesión sin necesitar `session.json`) siguen funcionando siempre, incluso para sesiones "Sin
   metadata". Pero `UpdateHistoryStats`/`RenderScoreHistory` vienen de
   `HistoryService.GetSessionHistoryAsync`/`GetHistoryStatsAsync`, que sí filtran `!s.HasMeta`. Al
   momento de este diagnóstico (prompt 54), solo dos lugares llamaban
   `BackupService.SaveSessionMetadata`: `FinishOptimizationAsync` (tab clásico, `MainWindow.xaml.cs`)
   y `App.RunSilentAsync` (modo `-Silent` de CLI, `App.xaml.cs`) — la preocupación era que, sin
   ninguno de los dos corriendo, las stats agregadas y el gráfico de score quedaran congelados en el
   último valor histórico. El tab clásico se retiró en el corte 66, pero
   `OptimizationService.RunAsync`/`GetPreset` (y con ellos, `App.RunSilentAsync`/
   `SaveSessionMetadata`) **no se tocaron** — confirmado sin diff real (`git diff` sobre
   `OptimizationService.cs` solo muestra las 72 líneas eliminadas de `BuildActionPlan`;
   `App.xaml.cs` sin ningún cambio). Historial sigue recibiendo sesiones con metadata completa cada
   vez que corre `-Silent`, además de sesiones sin metadata de Bloatware — no se degrada.
2. **Tuning Avanzado ya NO depende de `BackupService` (resuelto en el corte 56).** Al momento de este
   diagnóstico (prompt 54), los dos `ui:ToggleSwitch` de Scheduler CPU y HAGS (corte 16B, previos a
   toda la arquitectura de tweaks) llamaban `TuningService.SetWin32PrioritySep`/`SetHagsState`, que a
   su vez llamaban `App.Backup.SaveRegBackup` directo y creaban sesión propia si no había una activa
   (`TuningService.EnsureBackupSession` → `App.Backup.NewBackupSession`) — no pasaban por
   `TweakRegistry`/`TweakStateStore` como los 26 tweaks migrados (ver 7.2), deuda técnica separada. El
   prompt 56 migró los 3 controles (Scheduler CPU, HAGS y Política térmica) a
   `TweakRegistry`/`TweakStateStore` y retiró la pestaña del sidebar —
   `SetWin32PrioritySep`/`SetHagsState`/`EnsureBackupSession` se eliminaron de `TuningService.cs` (sin
   caller). El mapa de dependencias de `BackupService`, **tras el retiro del tab Optimizar clásico en
   el corte 66**, queda: (a) el modo `-Silent` de CLI, (b) Bloatware (ver también el "Mapa final de
   `BackupService`" en 7.9).
3. **Bloatware: "Revertir" no reinstala nada de verdad — y además reportaba éxito falso. Resuelto en
   los cortes 68 (diagnóstico) y 69 (fix).** `SaveBloatBackup` (`BloatwareService.cs`) solo escribe
   `bloatware_removed.json` como referencia; `RestoreSession` (`BackupService.cs`) no tiene ningún
   paso que reinstale apps (sus 7 pasos son registro, servicios, red, HPET, plan de energía, PageFile
   y TCP global — ninguno de bloatware). El prompt 68 confirmó que el problema era peor que un revert
   faltante: el diálogo de confirmación prometía restaurar registro/servicios/red y, tras recorrer
   los 7 pasos en 0/0/0 (una sesión de Bloatware no tiene `session.json`), `RestoreSession` devolvía
   `true` y la app mostraba *"Sesión revertida correctamente… reinicia el equipo"* — un mensaje
   activamente falso, no un fallo silencioso. También confirmó que un revert real no es viable de
   forma consistente (5 grupos de apps con viabilidad distinta — ver 7.5). **Resolución (corte 69):**
   se sacó el botón "Revertir" de las filas de Bloatware en Historial, sin reemplazo (fila = registro
   informativo, badge "Bloatware", acción "—" inerte); `RestoreSession` se endureció con un guard
   explícito (si no hay `session.json` pero sí `bloatware_removed.json`, loguea el motivo real y
   devuelve `false` antes de recorrer los pasos); y se corrigió un segundo punto de entrada no mapeado
   acá, `btnRevertLast` ("Revertir última sesión"). Detección precisa vía
   `BackupSessionInfo.HasBloatwareRef` / `IsBloatwareOnly`, no `HasMeta` a secas. Detalle completo del
   fix en 7.10.
4. **Bug real, resuelto en los cortes 62/63 reemplazando la card entera (no con un parche de
   filtro).** Al momento de este diagnóstico (prompt 54), la card "Última optimización" del Home
   (`UpdateLastOptCardAsync`, `MainWindow.xaml.cs`) llamaba `GetBackupSessions().FirstOrDefault()` sin
   filtrar `HasMeta` — a diferencia de las stats de Historial (hallazgo 1), que sí filtran. Si
   Bloatware creaba una sesión más reciente que la última optimización real, la card mostraba esa
   sesión sin metadata como si fuera la última optimización, con 0 MB / 0 acciones / score +0 — un
   resultado engañoso, no el estado vacío real. (Antes del corte 56, Tuning Avanzado era otra fuente
   real de este mismo problema.) Antes de aplicar el fix puntual del filtro, Tomy notó el problema de
   fondo: los 4 datos de la card pertenecían por completo al mecanismo de sesión del tab clásico (que
   el proyecto terminó retirando en el corte 66) — parchear el filtro no resolvía eso. El prompt 61 diagnosticó qué hacía falta
   para un rediseño real y el prompt 62 reemplazó la card completa por un contador en vivo de "Tweaks
   activos", desacoplado por completo de `BackupService`/`BackupSessionInfo` — sin `HasMeta` que
   filtrar porque ya no lee sesiones en absoluto. Detalle completo del mecanismo nuevo en 7.8.
5. **Comparativa antes/después y reporte HTML — resuelto retirando el código, no reemplazándolo
   (corte 66, decisión de producto de Tomy).** `ShowCompareDialog` y `ExportHtmlReportAsync`
   (`MainWindow.xaml.cs`) dependían exclusivamente de `App.SnapshotBefore`/`_snapshotAfter`
   (`SnapshotService`) y de `_lastReportActions`/`_lastFreedMb`/`_scoreBefore` — los 4 campos solo se
   llenaban dentro de `OnRunOptimizationAsync`/`FinishOptimizationAsync` del tab clásico. El health
   score (`_lastAuditResult`/`RunAuditAsync`/`RecalcScoreAsync`) sí es independiente del tab clásico —
   no era parte de este hueco. La preocupación era que, al retirar el tab sin resolver esto, "Ver
   comparativa" y "Exportar reporte HTML" quedaran visibles exportando/mostrando datos vacíos o
   desactualizados en vez de desaparecer prolijamente. En vez de reconstruir un equivalente, se
   aceptó perder ambas funciones tal como existían (ver 7.9): `ShowCompareDialog`,
   `FinishOptimizationDialog`, `CompareDialog` y los 4 campos se eliminaron por completo;
   `ExportHtmlReportAsync` se eliminó y su botón (`btnExportHTML`, vive en el overlay de Consola,
   fuera del tab clásico — no desaparecía solo al retirar la pestaña) se ocultó explícito
   (`Visibility="Collapsed"`) en vez de quedar exportando datos vacíos.

Nota menor, sin relación directa con el tab clásico: `CleanupOldBackups(keepDays)`
(`BackupService.cs`) no tiene ningún caller en todo el árbol — candidato a limpieza de repo.

En el prompt 54 ninguno de los 5 hallazgos se corrigió — era diagnóstico puro. **Desde entonces se
resolvieron los 5**: hallazgo 2 en el corte 56 (Tuning Avanzado migrado, ya no toca `BackupService`);
hallazgo 4 en los cortes 62/63 (card "Última optimización" reemplazada por "Tweaks activos", ver
7.8); hallazgos 1 y 5 en el corte 66, al retirar el tab (Historial confirmado sin degradarse porque
`-Silent` sigue llamando `SaveSessionMetadata`; Comparativa/Reporte HTML eliminados en vez de quedar
mostrando datos vacíos, ver 7.9); hallazgo 3 en los cortes 68/69 (revert falso de Bloatware — botón
sacado, `RestoreSession` endurecido, ver 7.10).

### 7.7 Mapeo de "defaults seguros de Windows" para un futuro "Restablecer" (prompt 57)

Diagnóstico de solo lectura (prompt 57, sin cambios de código) disparado por un caso de borde real
expuesto en la migración de Tuning Avanzado (prompt 56): si un tweak ya está On desde antes de tocar
su toggle nuevo (configuración externa del usuario, o una sesión vieja de WinBoost con el mecanismo
de sesión), `TweakStateStore` nunca captura un original — el usuario queda sin forma de apagarlo
desde la app salvo editando el valor a mano. Esto **no es un bug**: adivinar un default sería el
mismo tipo de placebo que ya se corrigió en HAGS (`RevertirAsync` restaurando el original real en vez
de forzar un valor fijo, ver 7.2). Pero es fricción real, y antes de decidir si construir una segunda
acción — separada de "Revertir", del estilo "Restablecer a un valor predeterminado de Windows",
rotulada honestamente como best-effort y nunca como "tu original" — hacía falta este mapeo.

**Conteo real, contra el código** (no asumido — el prompt 57 partió de un supuesto de 29 y no
coincidió): **27 `TweakDefinition`** en `TweakRegistry.All`. Los 4 tweaks del tab clásico que NO
llegaron a `TweakDefinition` (TrimDesfrag → acción en Herramientas, Startup/punto de restauración →
`QuickActionDefinition` en Home, DNS → card propia de `DnsPresetService`, DNSFlush →
`QuickActionDefinition`) quedan fuera — el concepto de "default" no aplica a ellos aquí, no porque se
haya evaluado y descartado.

**Tabla completa (27/27)** — Seguro = hay un default de Windows documentado con confianza (por borrado
de valor o valor específico bien conocido); Riesgoso = no hay consenso claro o depende de la
máquina/edición de forma que un default fijo podría ser incorrecto para algunos usuarios:

| Tweak (Id) | Categoría | Detalle del default |
|---|---|---|
| Telemetry | Seguro | Borra 2 valores de política (`AllowTelemetry`) → "no configurado", el default real de Windows. |
| SvcDiag | Seguro | DiagTrack: `Automatic` de fábrica en Win10/11, sin controversia. |
| Tasks | Seguro | Las 5 tareas nacen habilitadas en instalación limpia — "habilitar todas" es el default real. |
| TCP | **Riesgoso (Grupo A)** | `netsh` no tiene "ausencia de valor" — siempre hay que escribir algo. `autotuninglevel=normal` y `rss=enabled` son default bien documentados; **Chimney Offload** está deprecado en Windows moderno (ya ni aparece en `netsh int tcp show global` en máquinas actuales, "default" no tiene sentido claro para una feature que no existe) y **TCP Fast Open** cambió su valor de fábrica entre versiones/builds de Windows. |
| PageFile | Seguro | Default universal = gestión automática (`AutomaticManagedPagefile=true`), el estado de fábrica de cualquier Windows. |
| GPUPrio | **Riesgoso (Grupo A)** | La key `...\Multimedia\SystemProfile\Tasks\Games` viene poblada de fábrica (no ausente), pero los 5 valores exactos que cita la comunidad de tuning varían levemente según fuente/versión — sin tabla oficial única de Microsoft. |
| PowerThrot | Seguro | `PowerThrottlingOff` ausente de fábrica (Windows decide caso por caso); borrar restaura eso. |
| MouseAccel | Seguro | Speed=1/Threshold1=6/Threshold2=10/MouseDataQueueSize=100 — de los defaults de registro más documentados y consensuados que existen. |
| GameDVR | **Riesgoso (Grupo A)** | Mezcla 2 mecanismos: `AllowGameDVR` (política HKLM) sí es "no configurado" por default, sin duda. Pero los 3 valores de `HKCU\System\GameConfigStore` no tienen un default público inequívoco — cambiaron entre versiones de Windows y dependen de cuándo se inicializó Game Bar en esa cuenta. |
| GameMode | Seguro | Auto Game Mode documentado por Microsoft como habilitado por default desde Win10 1903+. |
| Cortana | Seguro | Política ausente de fábrica = "no configurado", el default real. |
| Notif | Seguro | `ToastEnabled=1` es el default ampliamente documentado. |
| Nagle | Seguro | `TcpAckFrequency`/`TCPNoDelay` ausentes de fábrica en cualquier adaptador nuevo — uno de los tweaks de red más clásicos y documentados. |
| Visual | Seguro | `VisualFXSetting=0`, `FontSmoothing=2`, `EnableTransparency=1` — defaults estándar de Windows, sin ambigüedad. |
| SvcXbox | Seguro | Los 3 servicios son `Manual` de fábrica (pueden no existir en ediciones N, pero cuando existen es Manual). |
| SvcWER | Seguro | `WerSvc`: `Manual` de fábrica, bien documentado. |
| SvcMaps | Seguro | `MapsBroker`/`lfsvc`: `Manual (Trigger Start)` para ambos. |
| SvcFax | **Riesgoso (Grupo A)** | `Fax` es `Manual` de fábrica, sin duda. Pero `RemoteRegistry` cambió de default entre versiones de Windows: en Win10/11 modernos suele venir `Disabled` (endurecimiento de seguridad), en versiones más viejas era `Manual` — depende de cuándo se construyó la imagen. |
| HPET | Seguro | Los 3 elementos BCD están ausentes de fábrica (Windows decide el reloj de plataforma solo); `bcdedit /deletevalue` es la forma documentada de volver a eso. |
| FastStartup | Seguro | `HiberbootEnabled=1` es el default más conocido de Windows 10/11; `HibernateEnabled=1` es el default en la enorme mayoría de instalaciones consumer con soporte de hibernación. |
| SvcSysMain | Seguro | `Automatic` es el default histórico y más citado (Microsoft ajustó el comportamiento de SysMain en builds NVMe recientes, pero el StartType de fábrica sigue siendo Automatic). |
| SvcWSearch | Seguro | `Automatic (Delayed Start)` bien documentado en Win10/11 client. |
| DisableIPv6 | Seguro | `DisabledComponents` ausente de fábrica; borrar restaura IPv6 sin preferencia forzada. |
| Power | **Riesgoso (Grupo B)** | El plan "Equilibrado" (GUID conocido y estable) es un default razonable. Pero `standby-timeout-ac` no tiene ningún valor universal — varía enormemente por fabricante/tipo de equipo; por esto mismo el propio tweak ya captura el original real en vez de asumir uno (prompt 51). |
| Win32PrioritySep | **Riesgoso (Grupo B)** | El caso que disparó este mapeo: no hay consenso de cuál es el default exacto de fábrica (el propio registro ya reemplazó un preset por otro, "Responsividad" 0x24 → 0x28, por falta de un default único mejor). |
| HAGS | Seguro | Microsoft documenta esta característica como off/opt-in por default (`HwSchMode=1`) — hay reportes aislados de combinaciones GPU+Windows recientes que lo traen pre-activado, pero la fuente oficial es consistente. |
| PoliticaTermica | **Riesgoso (Grupo B)** | El más incierto de los 27: no existe un "default de Windows" en absoluto — cada plan de energía trae su propio `ACSettingIndex`, y los OEM lo personalizan agresivamente. Ni "restablecer a Equilibrado" resuelve nada, porque el propio Equilibrado varía por OEM. |

**Resumen: 20 Seguro / 7 Riesgoso / 0 "no aplica" dentro del registro.**

**Sub-división de los 7 Riesgoso** (propuesta original de Booster, revisada por Claude contra el
detalle tweak-por-tweak de arriba antes de escribirla acá — coincide sin ajustes):
- **Grupo A — aproximable con advertencia explícita** (hay un valor que la mayoría de fuentes coincide
  en señalar como default, aunque no sea 100% universal): **TCP, GPUPrio, GameDVR, SvcFax**. Nota de
  implementación para cuando se decida construir esto: en TCP y GameDVR el "riesgo" no es parejo
  entre los valores que cada tweak toca (ej. `AllowGameDVR` y `autotuninglevel`/`rss` son en realidad
  Seguro-grado; solo Chimney/Fast Open y el trío de `GameConfigStore` son inciertos) — si se
  implementa, vale la pena resetear con distinta confianza cada sub-valor en vez de tratar el tweak
  entero como un único "best-effort" parejo.
- **Grupo B — sin ningún valor defendible** (no existe un default único razonable, ofrecer uno sería
  inventarlo): **Power** (puntualmente `standby-timeout-ac`; el GUID de plan sí tiene un default
  razonable en Equilibrado), **Win32PrioritySep**, **PoliticaTermica**.

**Decisión de alcance — RESUELTA en el corte 71: opción A.** Cuatro opciones estaban evaluadas:
- **A.** Construir "Restablecer" solo para los 20 Seguro.  ← **elegida por Tomy**
- **B.** Sumar también el Grupo A (Riesgoso aproximable) con texto de incertidumbre explícito.
- **C.** Construir para los 27 completos, incluido el Grupo B.
- **D.** No construir la feature por ahora.

El corte 71 implementó la opción A: "Restablecer a default de Windows" solo para los 20 Seguro; los 7
Riesgoso quedan sin la acción, con el bloqueo honesto de "Revertir" sin cambios. La única divergencia
respecto de la tabla de arriba se encontró durante la implementación: **GameMode** — `AllowAutoGameMode`
no es un default de fábrica documentado de Windows (el mapeo original asumía un valor puntual), se
corrigió a *borrar* ese valor. Implementación completa en 7.11.

El mapeo de arriba (tabla de los 27, Grupos A/B) se conserva como registro histórico: es la base para
una eventual decisión futura sobre B o C.

### 7.8 Card "Tweaks activos" del Home reemplaza a "Última optimización" (cortes 61-63)

Cierra el hallazgo #4 de 7.6 (bug de `HasMeta`, ver ahí): antes de aplicar ese fix puntual, Tomy notó
que el problema de fondo no era el filtro — los 4 datos de la vieja card (MB liberados, acciones,
score, fecha) pertenecían por completo al mecanismo de sesión (`BackupSessionInfo`/`SessionMetadata`)
del tab Optimizar clásico (que el proyecto retiró después, corte 66). El prompt 61 diagnosticó qué hacía falta
para un rediseño real; el prompt 62 reemplazó la card completa; el prompt 63 confirmó y corrigió una
race condition real en el mecanismo nuevo.

**Qué se sacó** (`MainWindow.xaml` / `MainWindow.xaml.cs`): `UpdateLastOptCardAsync`, el helper
`RelativeTime`, los 4 campos (`lblHomeLastWhen`/`lblHomeLastFreed`/`lblHomeLastScore`/
`lblHomeLastActions`) y sus 2 paneles (`panelHomeLastData`/`panelHomeLastEmpty`) — confirmado que no
se usaban en ningún otro lugar de la app antes de tocarlos. El botón de la card ("Ver historial" →
Historial) se renombró a `btnHomeViewTweaks` ("Ver tweaks" → sección Tweaks) para quedar coherente
con el contenido nuevo.

**De dónde sale el número nuevo**: `UpdateActiveTweaksCardAsync` cuenta cuántos de `TweakRegistry.All`
tienen `LeerEstadoAsync() == TweakState.On` ahora mismo, sobre `App.Tweaks.All.Count` como denominador
(nunca un `27` hardcodeado — si el registro crece, el número de la card lo sigue solo). A propósito
**no** reusa `AuditResult`/`RunAuditAsync` (la malla de salud del Home, `SetHealthCard`): son 17
checks con criterios más laxos que los 27 toggles reales (confirmado en el prompt 61 — ej.
`CheckSvcXbox` tolera 2 de 3, el `TweakDefinition` exige los 3; varios tweaks del registro ni están
cubiertos por esos 17 checks). Mostrar ese número como "tweaks activos" habría sido inconsistente con
lo que el usuario ve en Tweaks/Network — son dos mediciones distintas a propósito, no intercambiables.

**Mecanismo — cache en memoria, sin persistencia en disco** (no tiene sentido conservar un dato
"ahora mismo" entre sesiones de la app):
- **Primer cómputo**: `Task.WhenAll` sobre las 27 `LeerEstadoAsync` (cada una ya es su propio
  `Task.Run`) — corre en paralelo sin bloquear el hilo UI, dominado por la lectura más lenta (Power,
  varios `powercfg.exe` por lectura) en vez de la suma de las 27. Mientras corre, la card muestra
  "Calculando..." en vez de un número momentáneamente incorrecto (0/27).
- **Cache**: `_activeTweaksCount` (`int?`). Una vez calculado, las visitas siguientes al Home lo
  reusan tal cual — el mecanismo **nunca vuelve a barrer los 27** después del primer cálculo exitoso
  durante esa sesión de la app (relevante para el fix de la race condition, ver abajo).
- **Ajuste incremental sin re-barrido**: aplicar/revertir un tweak desde cualquier card (Tweaks o
  Network) llama `AdjustActiveTweaksCache`, que compara el nuevo `TweakState` contra el último
  conocido para ese Id (`_lastKnownTweakState`, poblado gratis desde `UpdateTweakCardUi` — todo render
  de cualquier card pasa por ahí) y mueve el cache ±1 solo si hubo un cambio real. Robusto a los
  no-op del registro (revert sin original capturado, apply fallido): compara contra el estado *real*
  re-leído después de la operación, no contra la intención del click.

**Fix de la race condition (prompt 63)**: si un Aplicar/Revertir tocaba un tweak mientras el barrido
inicial todavía estaba en vuelo, el barrido podía terminar y pisar el cache con un conteo que no
reflejaba ese cambio (si `LeerEstadoAsync` de ese tweak puntual ya había leído el estado viejo antes
del cambio real) — y como el mecanismo nunca vuelve a barrer después del primer cálculo, ese
desfasaje quedaba fijo hasta reiniciar la app. Corregido con una bandera
(`_activeTweaksDirtyDuringSweep`) que se marca cada vez que un ajuste incremental corre mientras el
barrido está en vuelo; si el barrido termina con la bandera en true, se descarta y se repite desde
cero hasta que uno corra limpio de punta a punta (tope de 5 reintentos, resguardo ante un caso
patológico de toggles constantes, no algo esperable en uso real). El fix solo necesita proteger ese
primer barrido — una vez garantizado limpio, los ajustes incrementales posteriores parten de una base
correcta y se mantienen correctos por sí solos.

Ambos cortes con evidencia real: `dotnet build` 0 errores/0 advertencias y publicados
(`Publish-CSharp.ps1`) — SHA256 y detalle completo en `docs/CHANGELOG.md` (prompts 62 y 63). Sin
pendientes abiertos de este tema.

### 7.9 Retiro completo del tab Optimizar clásico (cortes 54, 65, 66)

**Aclaración de alcance** (para no confundir con otro retiro distinto): esto es el retiro de la
pestaña **"Optimizar" dentro de la app C#/WPF** (la pantalla clásica de la migración nueva,
`<TabItem Header="Optimizar">` en `MainWindow.xaml`). NO es lo mismo que jubilar
`legacy/OptimizarPC_App.ps1` (el PowerShell 5.1, ya congelado en `legacy/` desde el corte 6.3, sin
relación con este corte — ver `CLAUDE.md`, sección "Código legacy"). Dos retiros distintos, de dos
código bases distintas.

Diagnóstico previo en el prompt 54 (7.6) y el prompt 65 (inventario final + confirmación de
`-Silent`); este corte (66) fue la implementación completa, probada por Tomy sobre el .exe
publicado.

**Qué se retiró**: la pestaña completa (XAML: presets + 36 checkboxes en 5 categorías + selector
de DNS, ~260 líneas) y el `footerBar` anidado adentro (`btnRun`/`btnSelAll`/`btnSelNone`/
`btnCancelOpt`/`lblSpaceFreed`/`lblPlanSummary`/`lblPlanWarning`), `navOptimizar` del sidebar, y el
code-behind exclusivo sin otro caller: `OnRunOptimizationAsync`, `FinishOptimizationAsync`,
`ShowCompareDialog`, `ApplyPreset`, `AllOptCheckboxes`, `GetCurrentSel`, `SelectAll`,
`UpdateDnsHint`, `UpdatePlanSummary`, `SaveProfile`/`LoadProfile`, y
`OptimizationService.BuildActionPlan` (2 únicos callers, ambos del tab clásico; el helper
compartido `G(sel, key)` que usa internamente no se tocó, lo sigue usando `RunAsync`). Las clases
`FinishOptimizationDialog` y `CompareDialog` (archivos `.xaml`/`.xaml.cs` completos) se verificaron
sin ningún otro caller — con el mismo rigor que ya se había aplicado a `ConfirmOptimizationDialog`
(que sí resultó compartido, ver abajo) — y se eliminaron.

**Qué se preservó intacto, y por qué**: `OptimizationService.RunAsync`/`GetPreset` — motor
exclusivo de `App.RunSilentAsync` (modo `-Silent` de CLI, `App.xaml.cs`) desde este corte.
Confirmado en el prompt 65, antes de tocar nada: `App.RunSilentAsync` nunca instancia
`MainWindow` ni llama ninguno de sus métodos, llama directo a `GetPreset`/`RunAsync` — un camino
100% independiente de la pantalla. Confirmado después de implementar (prompt 66): `git diff` sobre
`OptimizationService.cs` solo muestra las 72 líneas eliminadas de `BuildActionPlan`; `App.xaml.cs`
sin ningún cambio. `ConfirmOptimizationDialog` tampoco se tocó — Limpieza lo reusa
(`RunLimpiezaAsync`, ver 7.2), solo se retiró el llamado que hacía el tab clásico.

**Hallazgo no anticipado en el diagnóstico previo: el banner de trial.**
`bannerTrial`/`lblTrialText`/`btnTrialUpgrade` (`UpdateTrialBanner`) vivían anidados dentro de
`footerBar` — no por ser exclusivos del tab clásico (es la feature de trial/licencias de toda la
app), simplemente estaban ubicados ahí. Se detectó recién al fallar la compilación tras borrar
`footerBar`, no en los diagnósticos de los prompts 54/65. Se reubicó en **Home** (la entrada de la
app hoy, mismo criterio de "pantalla más visitada" que justificaba la ubicación original) en vez de
perderse — mismo `x:Name`, sin cambios en `UpdateTrialBanner`.

**Efecto colateral limpiado**: `DownloadAndApplyAsync` (auto-updater) tenía un `SetActiveNav(0)`
con el comentario "mostrar footer con la progressBar" — confirmado que ya no cumplía ninguna
función real desde el fix 28.3 (la progress bar de `footerBar` se había sacado hace varios cortes;
`App.Progress` apunta solo a `progressBarConsole`, en el overlay de Consola). Se eliminó el llamado
en vez de renumerarlo.

**Tercer mecanismo de persistencia retirado**: `SaveProfile`/`LoadProfile` guardaban la selección
de checkboxes del tab clásico en `opt_profile.json` (`%USERPROFILE%\.OptimizarPC\`) — un mecanismo
propio, separado de `BackupService` (sesión completa) y `TweakStateStore` (por-tweak). Eliminado
por completo junto con el tab.

**`btnExportHTML`**: sin otro caller, pero el botón vive en el overlay de Consola (visible desde
cualquier pantalla), no en el tab clásico — no desaparecía solo. Se ocultó explícito
(`Visibility="Collapsed"`, `x:Name` preservado por si se reconstruye este reporte contra la
arquitectura nueva más adelante) y `ExportHtmlReportAsync` se eliminó (sin caller tras ocultarlo).
Detalle completo en 7.6, hallazgo 5.

**Renumeración completa del sidebar** — único caso hasta ahora donde se retira el índice 0 (a
diferencia del retiro de Tuning Avanzado, que solo movió 3 índices): `_navButtons`, todos los
`SetActiveNav(N)` (sidebar, `btnHomeOptimize`, `btnHomeViewTweaks`, `btnTrialUpgrade`, el arranque
de la app, Bloatware post-desinstalación) y los guards de carga lazy
(`mainTabs.SelectedIndex == N`). Orden final: 0=Herramientas, 1=Home (entrada de la app),
2=Arranque, 3=Bloatware, 4=Historial, 5=Ajustes, 6=Licencia, 7=Tweaks, 8=Network, 9=Limpieza. Se
prestó atención especial a colecciones compartidas entre pestañas que asumieran un orden fijo
(precedente real del corte de Tuning Avanzado, `_tweakCardRefs`) — no se encontró ninguna otra
aparte de `_navButtons` mismo. **Corte 78**: el sidebar se reordenó *visualmente* (Tweaks/Network/
Limpieza dentro de PRINCIPAL, Herramientas a SISTEMA, sub-headers sueltos eliminados; ver 7.1) —
estos índices de `TabItem` y `_navButtons` NO cambiaron, solo el orden de los `<Button>` en el
`StackPanel` del sidebar. `SetActiveNav(N)` y sus callers siguen resolviéndose por índice de
`TabItem`.

**`btnHomeOptimize`**: pasó de `SetActiveNav(0)` (el tab clásico) a navegar directo a **Tweaks**
(índice 7).

**Onboarding — paso de perfil pausado, no resuelto (ver 7.5).** `ApplyPreset` se eliminó junto con
el tab clásico. El paso "Selecciona tu perfil de uso" del `OnboardingDialog` se sacó del wizard (4
pasos → 3: hardware, score, listo) sin construir ningún reemplazo ni cambiar el mensaje para
"venderlo" de otra forma — queda como pendiente real (7.5), no resuelto de fondo.
`OnboardingDialog.ChosenPreset` (string) se reemplazó por `Completed` (bool): el wizard ya no
elige ni aplica ningún preset, solo confirma que el usuario lo completó.

**Mapa final de `BackupService`**: solo Bloatware y `-Silent` (vía `OptimizationService.RunAsync`)
siguen creando sesiones activamente. Historial confirmado sin degradarse (7.6, hallazgo 1).

Evidencia real: `dotnet build` 0 errores/0 advertencias, publicado (SHA256 y timestamp en
`docs/CHANGELOG.md`, prompt 66), y probado por Tomy sobre el .exe publicado (navegación de los 10
tabs en más de un orden, banner de trial en Home, `btnHomeOptimize` → Tweaks, `btnExportHTML`
oculto sin crashear, onboarding sin el paso de perfil, Historial funcionando con sesiones viejas y
nuevas de Bloatware/`-Silent`).

### 7.10 Fix del "Revertir" falso de Bloatware en Historial (cortes 68-69)

Cierra el hallazgo 3 de 7.6. Diagnóstico en el prompt 68 (solo lectura), fix en el prompt 69, probado
por Tomy sobre el .exe publicado (SHA256 y detalle en `docs/CHANGELOG.md`, corte 69).

**El hallazgo (prompt 68).** Para una sesión de Bloatware, el botón "Revertir" de Historial (y
"Revertir última sesión") no solo no reinstalaba nada — reportaba éxito. Cadena real:

1. `InvokeRevertSessionAsync` (`MainWindow.xaml.cs`) mostraba un diálogo que prometía restaurar *"los
   valores de registro, servicios y red al estado anterior a esa optimización"*.
2. Una sesión de Bloatware no tiene `session.json` (solo `bloatware_removed.json`, que
   `RestoreSession` nunca lee). `RestoreSession` cargaba `meta = null`, ejecutaba su paso 1 (registro:
   0 archivos `reg_*.reg` → 0/0/0) y salteaba los pasos 2-7 (todos detrás de `meta?.…`).
3. `totalFailed == 0` → `return true` → popup verde *"Sesión revertida correctamente… Reinicia el
   equipo para que todos los cambios tomen efecto"*.

`bloatware_removed.json` siempre fue solo un registro de referencia para Historial (heredado del PS1,
`Save-BloatBackup`) — nunca existió un camino de reinstalación, ni en el PS1 ni en C#. El prompt 68
además confirmó que un revert real no es viable de forma consistente (5 grupos de apps con viabilidad
distinta, ninguno instantáneo ni offline — ver 7.5).

**Decisión de producto (Tomy).** Se saca el botón "Revertir" para las sesiones de Bloatware, sin
reemplazo. No se construye ninguna reinstalación automática en este corte (queda como evaluación
futura, 7.5).

**Mecanismo de detección — por qué NO `HasMeta` solo.** `BackupSessionInfo` (`BackupModels.cs`) gana
dos miembros:

- `HasBloatwareRef` (`bool`, seteado en `GetBackupSessions()` por
  `File.Exists(<carpeta>/bloatware_removed.json)`).
- `IsBloatwareOnly => HasBloatwareRef && !HasMeta` (propiedad calculada).

Se descartó reusar `!HasMeta` a secas: eso solo significa "no hay `session.json` por el motivo que
sea". Hoy en la práctica coincide con "es Bloatware", pero un `-Silent` que muriera entre
`NewBackupSession()` y `SaveSessionMetadata()` también daría `HasMeta == false` sin ser una sesión de
Bloatware, y a futuro podría haber otros tipos de sesión sin metadata. `IsBloatwareOnly` exige la
presencia del archivo específico. Si alguna vez una carpeta tuviera **ambos** (`session.json` +
`bloatware_removed.json`), `session.json` manda (`IsBloatwareOnly` da `false`) y sí hay acciones
reales que revertir.

**Los 2 puntos de entrada corregidos.** El diagnóstico del prompt 68 solo mapeó el botón por-fila; el
prompt 69 encontró el segundo al implementar.

1. **Botón por-fila** (`RenderHistoryItems`, `MainWindow.xaml.cs`): para filas `IsBloatwareOnly` no se
   pinta el `Button` "Revertir" (`BtnDanger`) — en su lugar, un placeholder inerte "—" (gris
   `#555555`, centrado). La columna "Estado" muestra **"Bloatware"** (badge neutro gris) en vez del
   genérico "Sin metadata", para que la fila se lea como un registro coherente y el hueco de "Acción"
   tenga sentido.
2. **"Revertir última sesión"** (`btnRevertLast` → `RevertLastSessionAsync`): revierte `sessions[0]`
   (la más reciente). Si esa es `IsBloatwareOnly`, ahora muestra un aviso honesto (*"…las apps
   desinstaladas no se pueden reinstalar automáticamente desde WinBoost, así que esa sesión no se
   puede revertir"*) y corta, en vez de mandarla al flujo de confirmación engañoso.

**Endurecimiento de `RestoreSession` (`BackupService.cs`) — defensa en profundidad.** Guard nuevo
justo después de cargar `meta`: si `meta is null && File.Exists(<carpeta>/bloatware_removed.json)`,
loguea *"Es un registro de desinstalación de Bloatware: WinBoost no reinstala apps, no hay nada que
revertir"* (tipo `err`) y devuelve `false` **antes** de recorrer los 7 pasos. Con `false`, el caller
muestra "Restauración con errores" + apunta al log — ya no el "Restauración completada" con éxito
genérico. Cubre cualquier caller futuro que llegue a `RestoreSession` con una carpeta así, más allá
de los 2 puntos de entrada de arriba (que con el fix ya ni llegan).

**Confirmado que no hay otro camino.** `RestoreSession` tiene un único caller
(`InvokeRevertSessionAsync`), alcanzado solo desde los 2 puntos de entrada de arriba. No hay atajos de
teclado ni `InputBindings` en toda la app, ni menú contextual en `icHistory`, ni acción en lote. El
punto de restauración de Windows (`QuickActionRegistry`), `SnapshotService` y el revert por-tweak
(`TweakStateStore`) son mecanismos separados, ninguno toca sesiones de Bloatware.

**Nota pre-existente, fuera de alcance (no introducida por este corte).** Una carpeta de sesión
totalmente vacía —sin `session.json` **ni** `bloatware_removed.json`— seguiría dando el "éxito
genérico" de `RestoreSession` (recorre los pasos en 0/0/0 → `return true`). Caso extremadamente
improbable: solo si `SaveBloatBackup` fallara justo después de que `NewBackupSession()` creó el
directorio (disco lleno, permisos). No se tocó — el guard nuevo es específico para
`bloatware_removed.json`, como pidió el prompt 69.

**Detalle menor corregido acá (no en el corte 69):** la entrada del CHANGELOG del corte 69 y el
comentario en `BackupService.cs` dicen "los 6 pasos" de `RestoreSession`; el código real (y 7.6
hallazgo 3) tiene **7** pasos numerados (registro, servicios, red, HPET, plan de energía, PageFile,
TCP global). Inexactitud cosmética del corte 69, no afecta el comportamiento; esta sección usa el
número real.

### 7.11 "Restablecer a default de Windows" — implementación (corte 71)

Cierra la decisión de alcance de 7.7 (opción A: los 20 Seguro). Mapeo en el prompt 57 (validado en el
58), datos de testeo manual en el prompt 72, implementación y prueba en el prompt 71 (Tomy forzó el
escenario "On sin captura" en varios de los 20 sobre el .exe publicado y confirmó el comportamiento).
El mecanismo por tweak está detallado en `docs/CHANGELOG.md` (entrada del corte 71) — acá va la
arquitectura y las decisiones.

**Qué resuelve.** Un tweak que ya está On antes de que el usuario toque su toggle nuevo (config
externa, o remanente de una versión vieja de WinBoost) no tiene `Original` en `TweakStateStore`, así
que "Revertir" se bloquea honestamente (no-op + *"WinBoost no tiene un valor original guardado"*). Es
correcto — adivinar un default sería el mismo placebo que ya se corrigió en HAGS (7.2) — pero deja al
usuario sin forma de apagar el tweak desde la UI. La acción nueva es la vía de escape, rotulada
honestamente: escribe el valor de **fábrica de Windows** (best-effort documentado), **no** "tu
original de esta máquina". Confirmación explícita antes de ejecutar.

**Arquitectura.**
- `TweakDefinition` gana un 9º parámetro opcional `Func<Task>? RestablecerDefaultAsync = null`. Los
  call-sites usan args nombrados, así que agregar el parámetro no tocó ninguno. `!= null` solo en los
  20 Seguro; `null` en los 7 Riesgoso y en cualquier cosa que no sea `TweakDefinition` (DNS del
  `DnsPresetService`, quick actions).
- Helpers nuevos en `TweakRegistry.cs`, todos **sin tocar `TweakStateStore`** (no es un original
  real): `RegDefault` + `WriteRegDefaultsAsync` (`DefaultValue == null` = borrar el valor, y solo abre
  la key si el valor existe — no la crea de la nada; `!= null` = escribirlo),
  `SetServiceStart`/`RestablecerSvcDefaultAsync` (escribe `Start` DWORD directo; con Automatic además
  intenta arrancar el servicio, best-effort, igual que `RevertSvcEntriesAsync`). Los tweaks con
  Apply/Revert propios (MouseAccel, Visual, Nagle, Tasks, HPET, PageFile, FastStartup) tienen su
  `Restablecer*DefaultAsync` dedicado.

**Cuándo se muestra el botón — reusa la detección existente, sin duplicar lógica.** La UI
(`BuildTweakCard`/`UpdateTweakCardUi`, `MainWindow.xaml.cs`) muestra "Restablecer a default de
Windows" solo cuando se cumplen las 3 condiciones a la vez:
1. El tweak lo soporta — `def.RestablecerDefaultAsync != null`. El panel del botón se crea en
   `BuildTweakCard` solo en ese caso; su mera existencia (`_tweakCardRefs` pasó de tupla de 2 a 3:
   `Switch`/`Status`/`ResetPanel?`) encapsula "es uno de los 20".
2. El tweak está On.
3. `!App.TweakState.HasEntry(id)` — **el mismo check** que ya usa cada `Revertir*Async` para decidir
   que es no-op. Si hay `Original` real, "Revertir" ya resuelve el caso y el botón no se muestra (no
   duplica acciones).

`UpdateTweakCardUi` ya corría tras cada lectura de estado; solo se le agregó la línea de visibilidad
(`state == On && !HasEntry(id)`).

**Al ejecutar (`ResetTweakToDefaultAsync`).** Confirmación honesta → `def.RestablecerDefaultAsync()`
→ `LeerEstadoAsync` → `AdjustActiveTweaksCache` → `UpdateTweakCardUi` (mismo patrón que
`RevertTweakAsync`). **No escribe ningún `Original`**: el ciclo normal de captura-en-el-primer-toggle
sigue igual — la próxima vez que el usuario prenda el toggle desde ese punto, `AplicarAsync` captura
un `Original` real (= el default que dejó el botón). Si tras restablecer el tweak **no** queda en
Off/NoAplicable (ej. clave HKLM protegida que no se pudo tocar), lo dice — no afirma un éxito que no
pasó.

**Corrección encontrada durante la implementación — GameMode.** El mapeo del prompt 57 (7.7) asumía
un valor puntual para `AllowAutoGameMode`. Confirmado contra el código real que ese valor **no es un
default de fábrica documentado de Windows** (el tweak lo pone en 0 junto con `AutoGameModeEnabled`,
pero Windows no lo escribe de fábrica). Se corrigió: el default de GameMode escribe
`AutoGameModeEnabled=1` (documentado desde Win10 1903+) y **borra** `AllowAutoGameMode`. Es la única
divergencia respecto del mapeo de 7.7 — los otros 19 coincidieron sin ajustes.

**Estado resultante — confirmado en los 20, sin excepciones.** Tras restablecer, el `LeerEstadoAsync`
de cada uno devuelve Off limpiamente sin ningún caso especial: el valor de fábrica nunca coincide con
lo que ese `LeerEstadoAsync` exige para reportar On (Visual exige `VisualFXSetting==2`, default 0;
HAGS exige `HwSchMode==2`, default 1; los servicios exigen `StartType==Disabled`, default
Manual/Automatic; Tasks exige las 5 deshabilitadas, default habilitadas; etc.). No hizo falta forzar
ningún estado ni agregar ninguna rama.

**Nota (no un hallazgo de este corte).** FastStartup mantiene la incompatibilidad con Power ya
documentada en 7.5 — restablecer FastStartup pasa por habilitar hibernación (`HiberbootEnabled=1` +
`powercfg /hibernate on`), el mismo mecanismo que su `Aplicar`/`Revertir` normal, no un riesgo nuevo.
