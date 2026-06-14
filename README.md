# WinBoost v4.0

Optimizador de rendimiento para Windows 10/11 con interfaz WPF, sistema de backup/restore, licencias y modo CLI.

---

## Caracteristicas principales

### Optimizacion
- Limpieza de archivos temporales, cache de exploradores, logs de eventos y WER
- Tweaks de registro: GPU priority, telemetria, Cortana, GameDVR, aceleracion del mouse
- Red: desactivar algoritmo de Nagle, TCP autotuning, flush DNS, preferir IPv4
- Servicios: deshabilitar Xbox, diagnosticos, WER, Maps, Fax, Windows Search (solo en SSD)
- Plan de energia de alto rendimiento, HPET, FastStartup, PageFile optimizado, TRIM async
- Modal de confirmacion pre-ejecucion con lista de acciones por impacto (alto/medio/bajo)
- Boton Detener para cancelar la optimizacion en curso entre fases
- Resumen post-optimizacion: cambios aplicados vs. condiciones no cumplidas

### Seguridad y backup
- Punto de restauracion de Windows creado automaticamente antes de cada optimizacion
- Backup automatico por sesion: claves de registro (.reg), servicios, red, PageFile, netsh
- Motor de restauracion completo: revertir cualquier sesion desde el tab Historial
- Soporte de Delayed Start en servicios (flag `AutoDelayed` en registro)

### Score de salud
- 19 checks en 4 categorias: Rendimiento, Privacidad, Red, Servicios
- Score 0-100 con delta antes/despues, barras por categoria y animacion de contador
- Analisis de sistema: detecta que opciones mejorarian el score y permite aplicarlas con un click
- Snapshot antes/despues con comparativa en modal (7 metricas: CPU, RAM, disco, procesos, arranque)

### Detector de bloatware
- Base de datos de 55 apps en 5 categorias: Juegos, Comunicacion, Telemetria, OEM, Utilidades
- Desinstalacion via AppX y winget con backup de lo eliminado
- Filtro por categoria, badges de riesgo (seguro/precaucion)

### Herramientas
- Monitor en tiempo real: CPU, RAM, disco, temperatura CPU/GPU (barras verticales)
- Procesos pesados: CPU% real (sin Sleep), RAM, botones Terminar con triple validacion de seguridad
- Analisis de espacio en disco: top 10 carpetas mas pesadas con barras proporcionales (async)
- Benchmark rapido de disco
- Dispositivos con problemas y inventario de drivers con filtro por clase
- Limpieza profunda: Explorer cache, WER, logs CBS/DISM, shader cache (NVIDIA/AMD)
- Limpieza del Driver Store: detecta duplicados obsoletos, exporta backup antes de eliminar
- Liberador de RAM con purga de Standby List via `NtSetSystemInformation`

### Mantenimiento automatico
- Tarea programada configurable (diario/semanal/al inicio)
- Ciclo standalone: temp, recycle, DNS flush, TRIM
- Log JSON con historial de los ultimos 30 runs

### Game Focus Mode
- Deteccion automatica de proceso fullscreen cada 5s
- Eleva prioridad, silencia notificaciones, restaura al salir del juego
- Afinidad de CPU opcional: restringe el proceso a nucleos fisicos (sin SMT)
- 39 juegos conocidos en la lista de deteccion

### Tuning avanzado (tab oculto)
- Win32PrioritySeparation: 3 valores honestos con descripcion del efecto real
- HAGS (Hardware-Accelerated GPU Scheduling): activar/desactivar con alerta de reinicio
- Politica termica: activa/pasiva via powercfg
- Informacion detallada de CPU, RAM, GPU y HAGS

### Reporte HTML
- Reporte standalone con CSS inline: score antes/despues, metricas medibles, acciones aplicadas
- Seccion hero con 4 cards (score, RAM, procesos, arranque) screenshot-friendly
- Se guarda en Documentos y abre en el navegador automaticamente

### Sistema de licencias
- Free: limpieza y diagnostico basico
- Pro ($25): todos los tweaks, backups, bloatware, mantenimiento automatico
- Tecnico ($45): igual que Pro + modo CLI + multi-PC (sin atadura de hardware)
- Trial de 14 dias con banner de estado en el footer
- Activacion por clave HWID-bound (Pro) o salt-only (Tecnico)

### Modo CLI / silencioso
```
WinBoost.exe -Silent -Preset Gaming
WinBoost.exe -Silent -Preset Safe
WinBoost.exe -Silent -Preset Prod
```
Genera log en `%USERPROFILE%\.OptimizarPC\logs\` y notifica via toast al terminar.

### Auto-updater
- Chequea `version.json` en GitHub al iniciar
- Descarga async con barra de progreso
- Script helper `do_update.ps1` reemplaza el exe y relanza automaticamente

---

## Requisitos

- Windows 10 / 11
- PowerShell 5.1
- Ejecutar como Administrador

---

## Uso en desarrollo

1. Clonar el repositorio
2. Ejecutar `EJECUTAR_COMO_ADMIN.bat` como administrador

---

## Compilar a .exe

```powershell
.\Build.ps1          # compilar + firmar con cert autofirmado
.\Build.ps1 -SkipSign  # solo compilar
```

Requiere el modulo `ps2exe` (se instala automaticamente si no esta presente).  
El instalador se genera con Inno Setup 6 usando `installer\WinBoost.iss`.

---

## Estructura del proyecto

```
OptimizarPC_App.ps1     logica principal (7100+ lineas)
OptimizarPC_UI.xaml     interfaz WPF (2100+ lineas)
Build.ps1               compilar a exe + firmar
Create-Icon.ps1         genera WinBoost.ico
EJECUTAR_COMO_ADMIN.bat launcher para desarrollo
version.json            metadata para auto-update
installer\WinBoost.iss  script Inno Setup 6
docs\CHANGELOG.md       historial de implementaciones
docs\PENDIENTES.md      features pendientes
```

---

## Stack

- PowerShell 5.1 — sin operadores PS7
- WPF + XAML cargado desde archivo externo
- `Get-CimInstance` (no WMI legacy)
- Sin threading — todo en hilo UI con `Flush-UI` entre pasos
- `ps2exe` para compilar a exe nativo con UAC elevation (`requireAdmin`)
