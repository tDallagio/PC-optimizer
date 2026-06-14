# OptimizarPC — Roadmap de implementación

> **Estado actual:** Fase 5 COMPLETADA — todos los modulos implementados

---

## Workflow — cómo trabajar con este archivo

1. **Un módulo por vez** — nunca empezar el siguiente sin terminar el actual
2. **Verificar antes de avanzar** — ejecutar `EJECUTAR_COMO_ADMIN.bat` y confirmar que funciona
3. **Marcar con ✅** — cuando un módulo está completo y verificado, actualizar este archivo
4. **Indicar el módulo activo** — siempre debe haber exactamente un módulo marcado como `🔄 EN PROGRESO`
5. **Un sub-módulo a la vez dentro de cada módulo** — ej: primero 6A, luego 6B, no juntos
6. **Si un módulo toca XAML + PS1** — modificar primero el XAML, verificar que carga, luego agregar la lógica en el PS1

### Cómo arrancar cada sesión en Claude Code
```
Leé el ROADMAP.md, identificá el módulo activo y continuá desde donde quedó.
```

### Leyenda de archivos afectados
- `[PS1]` = solo `OptimizarPC_App.ps1`
- `[XAML+PS1]` = ambos archivos, empezar por el XAML
- `[XAML]` = solo `OptimizarPC_UI.xaml`
- `(*)` = módulo crítico para comercialización
- `✅` = completo y verificado
- `🔄` = en progreso actualmente
- `⬜` = pendiente

---

## Estado implementado (Fases 1 y 2 parcial)

### Fase 1 — Fundamentos ✅
- ✅ Módulo 1A — Infraestructura de backup
- ✅ Módulo 1B — Motor de restauración
- ✅ Módulo 1C — UI historial
- ✅ Módulo 2A — Modal de confirmación
- ✅ Módulo 3A — Motor de score
- ✅ Módulo 3B — UI score animada

### Fase 2 — Features visibles (parcial)
- ✅ Módulo 4A — Motor de bloatware
- ✅ Módulo 4B — UI bloatware
- ✅ Módulo 4C — Desinstalador
- ✅ Módulo 5A — Motor de procesos
- ✅ Módulo 5B — UI procesos

---

## Fase 2 — Features visibles (módulos pendientes)

### ✅ Módulo 6A — Motor de temperatura `[PS1]`

**Funciones a implementar:**

- `Get-CPUTemperature`
  - Lee `MSAcpi_ThermalZoneTemperature` via CIM (nativo, sin dependencias)
  - Maneja múltiples zonas térmicas, calcula promedio y máximo
  - Convierte de décimos de Kelvin a Celsius
  - Retorna: `TempC`, `TempMax`, `ZoneCount`, `Status` (normal/warning/critical)

- `Get-GPUTemperature`
  - Intenta primero `Win32_PerfFormattedData_GPUPerformanceCounters`
  - Fallback a WMI `MSAcpi_ThermalZoneTemperature` filtrando zona GPU
  - Si LibreHardwareMonitor está instalado, lo usa via COM/WMI
  - Retorna: `TempC`, `Source` (wmi/lhm/unavailable), `Status`

- `Get-ThermalStatus`
  - Función principal: llama CPU y GPU, devuelve objeto unificado
  - Thresholds: normal `<70°C`, warning `70–85°C`, critical `>85°C`

---

### ✅ Módulo 6B — UI de temperatura `[XAML+PS1]`

**XAML — agregar en tab "Info del sistema":**
- Dos filas nuevas en el monitor en tiempo real (después de las barras CPU/RAM/Disco)
- Fila CPU temp: label "CPU Temp" + ProgressBar (0–100°C) + TextBlock valor
- Fila GPU temp: igual, con badge "N/D" si no hay sensor disponible
- Colores reactivos: verde `<70°C`, amarillo `70–85°C`, rojo `>85°C`
- `x:Names`: `pbCPUTemp`, `lblCPUTemp`, `pbGPUTemp`, `lblGPUTemp`, `lblGPUTempSource`

**PS1:**
- Registrar los 5 controles nuevos con `Get-Ctrl`
- Extender el `monitorTimer` existente (tick de 1s) para leer temperatura
- `Update-ThermalDisplay`: actualiza las dos filas con color reactivo
- Manejo graceful si el sensor no está disponible (label "N/D", barra gris)

---

## Fase 3 — Automatización

### ✅ Módulo 7A — Motor de tareas programadas `[PS1]` `(*)`

- `New-MaintenanceTask`
  - Registra tarea en el Task Scheduler de Windows
  - Parámetros: nombre, frecuencia (daily/weekly), hora, acciones a ejecutar
  - Usa `Register-ScheduledTask` con `-ScriptBlock` serializado
  - La tarea corre el `.ps1` con `-WindowStyle Hidden` y flag `-maintenance`

- `Get-MaintenanceTask` / `Remove-MaintenanceTask`
  - Lee el estado actual de la tarea (existe, habilitada, último run)
  - `Remove-MaintenanceTask` borra la tarea del scheduler

- `Invoke-MaintenanceCycle`
  - Limpieza de temp, recycle, DNS flush, TRIM si SSD
  - Genera log en `%USERPROFILE%\.OptimizarPC\maintenance_log.json`
  - Notificación toast al terminar (`New-BurntToastNotification` o fallback a `[Windows.UI.Notifications]`)

---

### ✅ Módulo 7B — UI de mantenimiento automático `[XAML+PS1]`

- Nueva sección en tab "Herramientas" (después de Liberador de RAM)
- Toggle ON/OFF para activar el mantenimiento automático
- ComboBox de frecuencia: Diario / Semanal / Al iniciar Windows
- TimePicker simple (ComboBox hora) para la hora de ejecución
- Checkboxes de qué limpiar: Temp / Recycle / DNS / TRIM
- Label "Último mantenimiento: fecha" y "Próximo: fecha"
- Botón "Ejecutar ahora" para prueba inmediata
- `x:Names`: `tglMaintenance`, `cboMaintFreq`, `cboMaintHour`, `chkMaintTemp`, `chkMaintRecycle`, `chkMaintDNS`, `chkMaintTRIM`, `lblLastMaint`, `lblNextMaint`, `btnRunMaintNow`, `lblMaintStatus`

---

### ✅ Módulo 8A — Motor de historial enriquecido `[PS1]`

- `Get-SessionHistory`
  - Lee todos los `session.json` de `%USERPROFILE%\.OptimizarPC\backups\`
  - Parsea: `scoreBefore`, `scoreAfter`, `freedMB`, `preset`, `actionCount`
  - Retorna lista ordenada por fecha descendente
  - Calcula tendencia: mejora promedio por sesión

- `Get-HistoryStats`
  - Estadísticas agregadas: total MB liberados, sesiones totales, mejora de score acumulada, fecha primera sesión

---

### ✅ Módulo 8B — UI de historial enriquecido `[XAML+PS1]`

- Sección de stats en el header del tab Historial (encima de la lista)
- 4 cards: Total sesiones / Total MB liberados / Mejora score promedio / Días desde primera sesión
- Mini gráfico de barras de score por sesión (últimas 8) usando `Canvas` o `ItemsControl` con rectángulos de altura proporcional
- `x:Names`: `lblHistTotalSessions`, `lblHistTotalMB`, `lblHistAvgImprovement`, `lblHistDaysSince`, `icScoreHistory`

---

### ✅ Módulo 9A — Motor de detección fullscreen `[PS1]`

- `Add-Type` con P/Invoke: `GetForegroundWindow` + `GetWindowRect` + `MonitorFromWindow`
- `Test-FullscreenProcess`: retorna el proceso activo fullscreen o `$null`
- Lista configurable de juegos conocidos (nombres de proceso): `csgo`, `valorant`, `fortnite`, `minecraft`, `steam`, `epicgameslauncher`, etc.

---

### ✅ Módulo 9B — Motor de optimización en foco `[PS1]`

- `Apply-GameFocusMode`
  - Eleva prioridad del proceso a `High` via `.PriorityClass`
  - Suprime notificaciones (`ToastEnabled=0`)
  - Guarda estado previo para restaurar al salir

- `Restore-GameFocusMode`
  - Restaura prioridad y notificaciones al estado anterior

---

### ✅ Módulo 9C — DispatcherTimer de detección `[PS1]`

- Timer cada 5 segundos que llama `Test-FullscreenProcess`
- Si detecta juego: llama `Apply-GameFocusMode` (solo una vez)
- Si ya no hay juego fullscreen: llama `Restore-GameFocusMode`
- Log en consola cuando activa/desactiva
- Badge "Gaming Mode" visible en header o footer de la app

---

## Fase 4 — Reportes y exportación

### ✅ Módulo 10 — Exportar reporte HTML `[PS1]`

- `Build-HTMLReport`
  - Genera HTML completo con: info del sistema, score antes/después, acciones aplicadas, MB liberados, bloatware removido, timestamp y versión
  - CSS inline para que sea standalone

- `Export-HTMLReport`
  - Guarda en `Documentos\OptimizarPC_Reporte_YYYY-MM-DD.html`
  - Abre en el browser por defecto

- Botón "Exportar reporte" en el footer de la consola (junto a Limpiar y Exportar .txt)
- `x:Name`: `btnExportHTML`

---

### ✅ Módulo 11A — Captura de estado del sistema `[PS1]`

- `Get-SystemSnapshot`
  - Captura: CPU idle%, RAM libre MB, servicios activos, score de salud, procesos en ejecución, espacio libre disco C:
  - Se llama automáticamente al inicio de `btnRun`

- `Compare-Snapshots`
  - Recibe snapshot antes y después
  - Calcula deltas: +X% CPU libre, +X MB RAM, -X servicios, +X score
  - Clasifica cada delta como mejora/neutro/empeoramiento

**Variables globales agregadas:**
- `$script:snapshotBefore`, `$script:snapshotAfter` — snapshots capturados en btnRun
- `$script:snapshotCompare` — resultado de Compare-Snapshots, array de 6 filas listo para 11B

---

### ✅ Módulo 11B — Modal de comparativa `[PS1]`

- `Show-CompareDialog`
  - Ventana WPF secundaria
  - Se muestra automáticamente al terminar la optimización
  - Dos columnas: ANTES / DESPUÉS
  - Filas: Score / RAM libre / CPU idle / Servicios activos / Espacio disco / MB liberados
  - Cada fila con ícono verde (mejora) o gris (sin cambio)
  - Botones: "Reiniciar ahora" / "Reiniciar después" / "Ver log"

---

## Fase 5 — Empaquetado y monetización `(*)`

### ✅ Módulo 12A — Generación y validación de hardware ID `[PS1]` `(*)`

- `Get-HardwareID`
  - Combina `ProcessorId` + `SerialNumber (Win32_BIOS)`
  - Hashea con SHA256 → ID único de 16 chars

- `Test-LicenseKey`
  - Valida clave formato `XXXX-XXXX-XXXX-XXXX` contra hardware ID
  - Hash derivado: `SHA256(hardwareID + salt secreto)`
  - Validación completamente offline

- `Get-LicenseStatus`
  - Lee `%USERPROFILE%\.OptimizarPC\license.key`
  - Retorna: `IsActivated`, `HardwareID`, `ExpiryDate`

---

### ✅ Módulo 12B — Modo Free vs Pro `[PS1]` `(*)`

- `$script:IS_PRO` — variable global seteada al arrancar
- `Lock-ProFeature` — bloquea feature si no es Pro con MessageBox
- **Features bloqueadas en Free:**
  - Tweaks de registro y servicios
  - Desinstalar bloatware (ver lista sí, desinstalar no)
  - Mantenimiento automático
  - Exportar reporte HTML
  - Revertir desde historial (ver sí, revertir no)

---

### ✅ Módulo 12C — UI de activación `[XAML+PS1]` `(*)`

- Campo de texto para ingresar clave + botón Activar
- Badge en header: "FREE" (gris) o "PRO" (azul/dorado)
- Link "Obtener licencia" que abre URL de compra
- `x:Names`: `lblLicenseStatus`, `badgeLicenseFree`, `badgeLicensePro`, `btnActivateLicense`

---

### ✅ Módulo 13 — Compilado a .exe `[fuera del PS1]`

```powershell
Install-Module ps2exe -Scope CurrentUser
ps2exe OptimizarPC_App.ps1 OptimizarPC.exe `
  -iconFile OptimizarPC.ico `
  -title "OptimizarPC Universal" `
  -description "Optimizador de rendimiento para Windows" `
  -version "4.0.0.0" `
  -requireAdmin `
  -noConsole
```

- Firma con certificado autofirmado (`New-SelfSignedCertificate` + `Set-AuthenticodeSignature`)
- Empaquetar con Inno Setup o NSIS:
  - Instala `.exe` + `.xaml` en `%ProgramFiles%\OptimizarPC`
  - Acceso directo en escritorio y menú inicio
  - Entrada en "Agregar o quitar programas"

---

### ✅ Módulo 14 — Auto-updater mejorado `[PS1]`

- Extender `Check-ForUpdates` (ya existe la base):
  - Descargar nuevo `.ps1`/`.exe` a `%TEMP%\OptimizarPC_update\`
  - Verificar hash SHA256 antes de reemplazar
  - Mostrar changelog en ventana secundaria

- `Download-Update`
  - `Invoke-WebRequest` con progress hacia `%TEMP%`
  - Reutilizar `progressBar` existente para mostrar descarga
  - Verificar integridad SHA256

- `Apply-Update`
  - Copia el nuevo archivo sobre el actual
  - Lanza el nuevo proceso y cierra el actual con `Start-Process + exit`

---

### ✅ Módulo 15A — Detección de primer uso `[PS1]`

- Flag `firstRun` en `%USERPROFILE%\.OptimizarPC\profile.json`
- Al abrir por primera vez: `firstRun = true` → mostrar onboarding
- Al completar: `firstRun = false` → nunca más mostrar

---

### ✅ Módulo 15B — Ventana de bienvenida `[XAML+PS1]`

- `Show-OnboardingDialog` — ventana WPF secundaria de 600×500
- **4 pasos:**
  - Paso 1: Bienvenida + detección de hardware (CPU/GPU/RAM/disco)
  - Paso 2: Score inicial con explicación
  - Paso 3: Sugerencia de preset según hardware (laptop → Productividad, gaming → Gaming)
  - Paso 4: "Listo para optimizar" con botón Empezar
- Navegación con botones Siguiente/Anterior
- Sin cierre forzado: el usuario debe completar los 4 pasos

---

## Orden de implementación sugerido

| Prioridad | Fase | Módulos | Estado |
|-----------|------|---------|--------|
| 1 | Fase 2 | ✅ 6A ✅ 6B | ✅ Completo |
| 2 | Fase 3 | ✅ 7A → 7B → 8A → 8B → 9A → 9B → 9C | ⬜ En progreso |
| 3 | Fase 4 | ✅ 10 → 11A → 11B | ⬜ En progreso |
| 4 | Fase 5 | 12A → 12B → 12C → 13 → 14 → 15A → 15B | ⬜ Pendiente |

---

## Resumen de progreso

| Fase | Total | Completos | Pendientes |
|------|-------|-----------|------------|
| Fase 1 | 6 | ✅ 6 | 0 |
| Fase 2 | 8 | ✅ 7 | ⬜ 0 |
| Fase 3 | 7 | ✅ 7 | ⬜ 0 |
| Fase 4 | 3 | ✅ 1 | ⬜ 2 |
| Fase 5 | 7 | 0 | ⬜ 7 |
| **Total** | **31** | **21** | **⬜ 9** |

