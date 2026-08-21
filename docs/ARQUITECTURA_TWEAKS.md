# WinBoost — Arquitectura de Tweaks (Optimizar)

> Documento de trabajo/planificación para la rearquitectura de la pestaña Optimizar: pasar de
> checkboxes + selección/Aplicar a **toggles inmediatos por tweak** (prender = aplica ya, apagar =
> revierte ya). Generado por análisis de código real (no de la UI/descripciones), previo a
> implementar nada. Excluye Limpieza de Archivos (va a una sección propia "Limpieza").
>
> Fuentes: `OptimizationService.cs` (Apply real), `SystemInfoService.cs` (lectores de estado
> existentes, vía health score), `BackupService.cs` (precedente de reversión, hoy a nivel de sesión
> completa, no por tweak individual).

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
