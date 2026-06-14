# WinBoost — PENDIENTES (reestructurado para lanzamiento)

> **Instruccion para Claude Code:** Leer este archivo al arrancar cada sesion.
> Implementar los items EN ORDEN, de arriba hacia abajo.
> Marcar [x] al completar cada item. No saltear items sin marcar.
> Al terminar un item, actualizar tambien CHANGELOG.md.
>
> Items con prefijo [AUDIT] provienen de la auditoria externa (Fable, jun 2026).

---

## FASE 0 — Prerequisitos y bugs criticos ✅ COMPLETA

- [x] **F0.1** Windows Restore Point antes de optimizar
- [x] **F0.2** Trial de 14 dias
- [x] **F0.3** Metricas externas verificables (boot time, RAM idle, conteo procesos)
- [x] **F0.4** Audit de memory leaks (timers detenidos en Add_Closing)
- [x] **F0.5** Auto-refresh de procesos: default OFF
- [x] **F0.6** Fix barra de disco (closure roto en add_SizeChanged)
- [x] **F0.7** Rediseno tab Info del sistema en layout 2x2
- [x] **F0.8** Temperatura CPU/GPU "N/D" sin errores
- [x] **F0.9** Footer "listo para optimizar" colapsa en otras pestanas
- [x] **F0.10 [AUDIT C1]** Cerrar 4 brechas criticas de undo: PageFile (orden invertido + rollback + backup), Plan de energia (GUID exacto + hibernacion), Nagle (enrutado por Set-Reg), TCP global (netsh_backup.txt + accion type="netsh")
- [x] **F0.11 [AUDIT C4]** Stop-Process explorer con reinicio garantizado via try/finally
- [x] **F0.12 [AUDIT C2]** TRIM async via Start-Job + DispatcherTimer; Checkpoint con mensaje de progreso

---

## FASE 1 — Para el lanzamiento v1.0

- [x] **F1.1** Notificacion toast al terminar optimizacion
- [x] **F1.2** Reporte HTML mejorado (seccion "Resultados medibles")
- [x] **F1.3** Verificar timeout winget en PCs lentos
- [x] **F1.3-fix** Write-Log de timeout en Get-WingetInstalledMap
- [x] **F1.4 [AUDIT M1]** Auditoria New-Brush completa — 0 instancias de ColorConverter directas fuera de New-Brush
- [x] **F1.5 [AUDIT M4]** Tweaks placebo removidos: Win32PrioritySeparation (bug hex/decimal + placebo), LargeSystemCache, DisablePagingExecutive. Score redistribuido. Texto de changelog honesto incluido.

- [x] **F1.6** Icono WinBoost.ico creado

- [x] **F1.7** Deteccion de dispositivos con problemas (Drivers tab) — `Get-ProblemDevices`: `Get-PnpDevice | Where-Object { $_.Status -ne "OK" }`, devolver lista con Name/Status/ConfigManagerErrorCode. UI: tabla Dispositivo/Estado/Codigo, badge amarillo `#F59E0B` en `navHerramientas` si hay problemas, boton "Abrir Administrador de dispositivos" (`devmgmt.msc`). Solo lectura, sin modificar drivers.

- [x] **F1.8** Inventario de drivers — en la misma tab de F1.7: `Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -ne $null }`. Tabla DeviceName/DriverVersion/DriverDate/IsSigned. Filas rojas si `IsSigned=$false`, amarillas si `DriverDate` >2 anos, verdes si OK. ComboBox filtro por `DeviceClass`. Sin actualizacion automatica.

---

## FASE 2 — Post-lanzamiento / v1.1+

### Calidad y robustez (de la auditoria)

- [x] **F2.1 [AUDIT A4]** `EventLogs` borra TODOS los logs sin advertencia proporcional (Seguridad/Sistema/Aplicacion — registros forenses). Fix: marcar `impact="high"` con descripcion explicita. Excluir Security log o destacarlo en rojo en el modal. "Seleccionar todo" no debe activarlo silenciosamente.

- [x] **F2.2 [AUDIT A3]** Race condition monitor timer vs Dispose — en `Add_Closing` se hace `.Dispose()` mientras el tick puede estar en `NextValue()`. Fix: llamar `$script:monitorTimer.Stop()` ANTES de los `.Dispose()` + flag `$script:shuttingDown` que el tick chequee al inicio.

- [ ] **F2.3 [AUDIT C3]** Mejorar proteccion de licencia — salt hardcodeado `OptPC40_LicSalt_v1` es trivialmente crackeable. BAJA PRIORIDAD REAL: optimizacion prematura sin usuarios. Fix futuro: firma asimetrica RSA/ECDSA. NO priorizar para v1.0.

- [x] **F2.4 [AUDIT A1]** Fusionar los dos `$mainTabs.Add_SelectionChanged` (lineas ~4165 y ~4378) en un unico handler. Actualmente WPF los acumula y ambos corren en cada cambio de tab.

- [x] **F2.5 [AUDIT M2]** Refactor de funciones gigantes — `btnRun` (~340 lineas) y `Show-ConfirmDialog` (~257 lineas). Extraer `Invoke-CleanupTweaks`, `Invoke-RegistryTweaks`, `Invoke-NetworkTweaks`, `Invoke-ServiceTweaks`. Habilita el resumen "que se aplico / que fallo" (ver F2.6).

- [x] **F2.6** Resumen post-optimizacion "que se aplico / que fallo" — panel tipo "23 cambios aplicados, 2 omitidos". Depende parcialmente de F2.5.

- [x] **F2.7 [AUDIT M3]** `DisableIPv6` con `0xFF` puede cortar conectividad en redes IPv6-nativas. Fix: cambiar a `0x20` (preferir IPv4 sin deshabilitar del todo) o etiquetar como "avanzado, puede cortar conectividad en redes modernas".

- [x] **F2.8 [AUDIT M5]** `Get-HeavyProcesses` hace `Start-Sleep 600ms` en hilo UI. Fix: usar `Get-Counter '\Process(*)\% Processor Time'` (lectura instantanea) o Start-Job + DispatcherTimer poll.

- [x] **F2.9 [AUDIT A2]** Inconsistencia Get-Service vs CIM en servicios — `Get-Service` no expone bien "Automatic (Delayed Start)". Fix: leer StartMode via CIM + detectar delayed-start via `HKLM:\SYSTEM\CCS\Services\<name>\DelayedAutoStart`.

- [x] **F2.10 [AUDIT B-varios]** Pulidos menores: (a) `Apply-Update` sin notificacion si `Copy-Item` falla. (b) Mensajes de error crudos `"Error: $_"` en labels UI. (c) `version.json` apunta a `TU_USUARIO` placeholder. (d) Falta `.Owner = $window` antes de `ShowDialog` en modales.

### UX (de la auditoria)

- [x] **F2.11 [AUDIT U1]** PageFile pregunta a mitad de optimizacion via `MessageBox YesNo`. Fix: mover la pregunta al modal de confirmacion inicial.

- [x] **F2.12 [AUDIT U2]** No se puede cancelar una optimizacion en curso. Fix: boton "Cancelar" con flag chequeado entre categorias. Depende de F2.5.

### Features nuevas

- [x] **F2.13** Modo "solo lectura / analisis" — escanear y mostrar score + recomendaciones SIN tocar nada. Convierte escepticos, mejora conversion de trial.

- [x] **F2.14** Analisis de espacio en disco — `Get-TopFolders`: top 10 carpetas mas pesadas, barras proporcionales. Excluir `Windows\WinSxS`.

- [x] **F2.15** Modo silencioso / CLI — parametro `-Silent` + `-Preset`, sin ventana, log a archivo, toast al terminar, exit code 0/1. Habilita mercado tecnico/multi-PC.

- [x] **F2.16** Licencia Tecnico multi-PC — tier "Tecnico" ($45): Pro + CLI + reporte con campo "Tecnico:" customizable. Requiere F2.15.

- [x] **F2.17** Detector de optimizadores previos — detectar CCleaner/IObit/Wise/AVG en registro, banner informativo no-bloqueante. Sin desinstalar.

- [x] **F2.18** Tab Tuning Avanzado — nueva tab, actualizar `Set-ActiveNav` 0-9. MVP: Turbo Boost, XMP, cooling policy, info de componentes.

  **Win32PrioritySeparation — criterio para esta tab (auditoria Fable + analisis jun 2026):** si se expone este parametro, los unicos dos valores honestos son:
  - `22` (0x16) — "Consistencia bajo carga pesada de CPU — puede reducir responsividad del resto del sistema"
  - `36` (0x24) — "Responsividad bajo carga — elimina la ventaja de CPU del juego en favor del desktop"
  El `38` (0x26) es el default de Windows disfrazado. El `40` es el `36` con extra folklore. El `26` que tenia el codigo original era el error hex/decimal (decimal 26 = 0x1A = modo Windows Server). Nunca ofrecer estos valores en presets automaticos — solo en seccion Avanzado con explicacion honesta para cada uno.

  **Para input lag real y medible** (si WinBoost quiere vender este beneficio, aqui esta la mercaderia con evidencia): polling rate del mouse, frame limiting + NVIDIA Reflex/AMD Anti-Lag, plan de energia que evite C-states profundos, HAGS (Hardware-Accelerated GPU Scheduling), frecuencia y tiempo de respuesta del monitor. Estas son las palancas con efecto medible — no el scheduler.

- [x] **F2.19** Limpieza del Driver Store — `Get-ObsoleteDriverPackages` via `pnputil /enum-drivers`, backup con `Export-WindowsDriver` antes de `pnputil /delete-driver`.

- [x] **F2.20** Afinidad de CPU automatica en Game Focus Mode — toggle `chkGameAffinity`, mascara de nucleos fisicos si SMT activo, restaurar al salir. Persistir en `settings.GameAffinityEnabled`.

---

## Descartado / No implementar en v1.x

- **4.1** Selector de idioma EN/PT — lanzar solo en espanol.
- **3.4** Benchmark de disco — CrystalDiskMark existe y es gratis.
- **6.2** Verificacion SHA256 del XAML — optimizacion prematura.
- **6.3** Ofuscacion del PS1 — optimizacion prematura sin usuarios.
- **9.4** Verificacion online de versiones de drivers — fragil desde PS5.1.
- **8.1** Runspace completo — evaluar para v2.0 (reescritura C#/WPF).

---

## Externo a Claude Code (tareas de Tomy)

- **Code signing** — certificado Authenticode OV real (~100-200 USD/ano). Sin esto SmartScreen/AV bloquean la descarga. NO lo hace Claude Code.
- **Testing en PC limpio** — Win11 y Win10 reales antes del lanzamiento.

---

## Resumen de estado

| Fase | Items | Hecho | Pendiente |
|------|-------|-------|-----------|
| F0 — Prerequisitos y bugs criticos | 12 | 12 | 0 |
| F1 — Lanzamiento | 9 | 9 | 0 |
| F2 — Post-launch | 20 | 19 | 1 |
| **TOTAL** | **41** | **40** | **1** |

**FASE 1 COMPLETA. Proximo a implementar:** F2.3 (Mejorar proteccion de licencia — BAJA PRIORIDAD).

---

## Completados (historico)

Ver `CHANGELOG.md` para detalle de implementacion de cada uno.

- [x] Todos los items 1.1 a 1.7 (Estetica y UX completa)
- [x] 2.3 Badge de errores en sidebar
- [x] 2.6 Validacion .reg corrupto antes de restaurar
- [x] 3.1 Purga Standby List tras liberar RAM
- [x] 3.2 Limpieza profunda de cache (4 categorias)
- [x] 4.3 Preferencias de comportamiento en Settings
- [x] 4.4 Ruta personalizada de backups
- [x] 4.5 Retencion de backups configurable
- [x] 6.1 No distribuir PS1 (Build.ps1 compila a exe)
- [x] 6.4 Licencias atadas a hardware (SHA256 HardwareID)
- [x] 7.1 Nombre WinBoost definido
- [x] Fix ComboBox ilegibles (ControlTemplate custom)
- [x] Rediseno tab Herramientas (grilla 2x2 + procesos full width)
- [x] Fix crash #FF1A1A1A (pipeline pollution en New-Brush, jun 2026)
- [x] Roadmap completo 15 modulos (1A/1B/1C, 2, 3A/3B, 4A/4B/4C, 5A/5B, 6A/6B, 7A/7B, 8A/8B, 9A/9B/9C, 10, 11A/11B, 12A/12B/12C, 13, 14, 15A/15B)
