# WinBoost

Optimizador de rendimiento para Windows 10/11 con interfaz WPF: limpieza, tweaks con
backup y restauracion por sesion, score de salud verificable, sistema de licencias y
modo CLI.

**[Descargar la ultima version](https://github.com/tDallagio/PC-optimizer/releases/latest)** · Windows 10 / 11 · Requiere ejecutar como Administrador

---

## Instalacion

1. Descarga el instalador desde la [pagina de releases](https://github.com/tDallagio/PC-optimizer/releases/latest) (`WinBoost_Setup_x.x.exe`).
2. Ejecutalo y segui el asistente. La app se instala en `Program Files` y crea accesos directos.
3. Al abrir, WinBoost solicita permisos de administrador (necesarios para aplicar tweaks del sistema).

WinBoost incluye un trial de 14 dias con todas las funciones Pro habilitadas.

> **Nota sobre antivirus:** el ejecutable es un .exe C#/.NET 8 nativo (self-contained
> single-file), lo que elimina el falso positivo que daba la version PowerShell anterior
> (empaquetada con `ps2exe`, detectada como Wacatac). SmartScreen todavia puede mostrar una
> advertencia de "editor desconocido" hasta que el instalador tenga firma de codigo (en
> progreso, ver `docs/PENDIENTES.md`). No es malware.

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

### Tuning avanzado
- Win32PrioritySeparation expuesto solo en esta seccion, con los unicos valores cuyo
  efecto es real y cada trade-off explicado honestamente. WinBoost no ofrece valores
  placebo: los ajustes sin efecto medible fueron removidos tras una auditoria interna.
- HAGS (Hardware-Accelerated GPU Scheduling): activar/desactivar con alerta de reinicio
- Politica termica: activa/pasiva via powercfg
- Informacion detallada de CPU, RAM, GPU y HAGS

### Reporte HTML
- Reporte standalone con CSS inline: score antes/despues, metricas medibles, acciones aplicadas
- Seccion hero con 4 cards (score, RAM, procesos, arranque) screenshot-friendly
- Se guarda en Documentos y abre en el navegador automaticamente

### Sistema de licencias
- **Free:** limpieza y diagnostico basico
- **Pro:** todos los tweaks, backups, bloatware, mantenimiento automatico
- **Tecnico:** Pro + modo CLI + multi-PC
- Trial de 14 dias con banner de estado en el footer
- Activacion por clave con firma RSA-2048 (Pro atada a hardware, Tecnico multi-PC)

### Modo CLI / silencioso
```
WinBoost.exe -Silent -Preset Gaming
WinBoost.exe -Silent -Preset Safe
WinBoost.exe -Silent -Preset Prod
```
Genera log en `%USERPROFILE%\.OptimizarPC\logs\` y notifica via toast al terminar.

### Auto-actualizacion
- Chequea `version.json` en GitHub al iniciar y avisa si hay una version mas nueva
- Descarga el instalador con barra de progreso y verificacion de integridad SHA256
- Aplica la actualizacion ejecutando el instalador en modo silencioso y relanza la app
- Si la verificacion falla o el antivirus interfiere, abre la pagina del release como respaldo

---

## Requisitos

- Windows 10 / 11 (x64)
- Permisos de administrador

No requiere tener .NET instalado: el ejecutable es self-contained (incluye el runtime).

---

## Desarrollo

```powershell
# Compilar (dotnet build valida que compila, no reemplaza la validacion funcional)
dotnet build src-csharp\WinBoost\WinBoost.csproj

# Publicar el .exe self-contained single-file + instalador (Inno Setup)
.\src-csharp\Publish-CSharp.ps1
.\src-csharp\Publish-CSharp.ps1 -SkipInstaller   # solo el .exe
```

La validacion funcional de una release candidate se hace siempre sobre el `.exe` publicado
por `Publish-CSharp.ps1`, nunca solo sobre `dotnet build`/`dotnet run` (ver `CLAUDE.md`). El
instalador se genera con Inno Setup 6 a partir de `src-csharp\installer\WinBoost.iss`.

---

## Estructura del proyecto

```
src-csharp\WinBoost\            proyecto C#/.NET 8 WPF (unica version oficial)
src-csharp\Publish-CSharp.ps1   publish self-contained single-file + instalador
src-csharp\installer\WinBoost.iss  script Inno Setup 6
Create-Icon.ps1                 genera WinBoost.ico
Gen-License.ps1                 emision de licencias (uso interno, no trackeado)
version.json                    metadata para auto-actualizacion
docs\CHANGELOG.md               historial de implementaciones
docs\PENDIENTES.md              estado del roadmap
legacy\                         version PowerShell descontinuada (ver legacy\README.md)
```

---

## Stack tecnico

- C# / .NET 8, WPF
- async/await + `Task.Run` para trabajo pesado — la UI no se bloquea
- `System.Management` (WMI) para info de sistema, P/Invoke nativo (`NativeMethods`) para el resto
- Publish self-contained single-file (win-x64), elevacion UAC via `app.manifest`
  (`requireAdministrator`)
