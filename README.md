# WinBoost

Optimizador de rendimiento para Windows 10/11 con interfaz WPF: tweaks reversibles uno
por uno, limpieza de archivos, score de salud verificable, quita de bloatware, sistema
de licencias y modo CLI.

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

### Home
- Pantalla de entrada de la app: medidores en vivo de CPU / RAM / GPU (uso %), malla de
  salud y contador de tweaks activos
- Overlay System Info: hardware del equipo y detalle de componentes — CPU (nucleos/hilos/
  cache), RAM (velocidad/slots), GPU (VRAM real, driver) y estado de HAGS
- Accesos rapidos: crear punto de restauracion, abrir System Info, ir a Tweaks

### Tweaks
- 24 tweaks de sistema con toggle individual: activarlo aplica al instante, desactivarlo
  revierte — cada tweak captura el valor original de la maquina antes del primer cambio y
  restaura ese valor exacto (no un default asumido) al desactivarse
- Registro: GPU priority, telemetria, Cortana, Game DVR, aceleracion del mouse, efectos
  visuales, scheduler de CPU (Win32PrioritySeparation), HAGS (Hardware-Accelerated GPU
  Scheduling), Power Throttling
- Servicios: Xbox, DiagTrack, Windows Error Reporting, Maps, Fax, y SysMain / Windows
  Search (estos dos ultimos solo se ofrecen en equipos con SSD)
- Sistema: plan de energia segun tipo de equipo (laptop/desktop), HPET, Fast Startup,
  PageFile, politica termica
- "Restablecer a default de Windows": para los tweaks seguros que ya estaban activos sin
  que WinBoost tenga un original capturado (config externa, o una version vieja de la
  app), escribe el valor de fabrica de Windows
- El estado de cada tweak se lee en vivo del sistema; los que no aplican a la maquina se
  marcan como tal con el motivo

### Red
- Nagle, TCP autotuning y preferencia de IPv4 sobre IPv6 como toggles reversibles
- Selector de DNS con 4 proveedores (Cloudflare, Google, Quad9, AdGuard), con captura y
  restauracion del valor original por adaptador
- Flush de la cache DNS como accion de un click

### Limpieza
- Limpieza de archivos: 8 items seleccionables con checkbox (temporales de usuario y
  sistema, Prefetch, cache de Windows Update, cache de navegadores, papelera, logs de
  eventos, cache profunda) ejecutados juntos, con modal de confirmacion que marca los de
  impacto alto. "Cache profunda" detiene el Explorador para vaciar icon/thumbnail cache,
  WER, logs CBS/DISM y shader cache. Sin revert (borrar temporales no es reversible)
- Mantenimiento automatico: tarea programada configurable (diario/semanal/al inicio),
  ciclo standalone (temp, papelera, flush DNS, TRIM) y log JSON de los ultimos 30 runs
- Limpieza del Driver Store: detecta paquetes de driver duplicados obsoletos, exige
  exportar un backup antes de eliminar

### Seguridad y backup
- Revert por tweak: cada toggle guarda el valor original de la maquina en su propio
  almacen (`tweak_state.json`) y lo restaura al desactivarse, independiente del resto
- Punto de restauracion de Windows a un click desde Home, con aviso honesto cuando
  Windows no deja crear otro dentro de la ventana de 24 h
- Backup por sesion en las corridas completas (modo `-Silent` y quita de bloatware):
  claves de registro (.reg), servicios, red, PageFile, netsh
- El tab Historial revierte las sesiones de optimizacion; las de bloatware quedan como
  registro informativo (WinBoost no reinstala apps)
- Soporte de Delayed Start en servicios (flag `AutoDelayed` en registro)

### Score de salud
- 17 checks en 4 categorias: Rendimiento, Privacidad, Red, Servicios
- Score 0-100 con animacion de contador, recalculable a demanda
- Malla de salud en Home: una card por categoria con la fraccion de checks cumplidos y un
  insight derivado del estado real del sistema

### Detector de bloatware
- Base de datos de 55 apps en 5 categorias: Juegos, Comunicacion, Telemetria, OEM, Utilidades
- Desinstalacion via AppX y winget, con registro de lo desinstalado (sin reinstalacion
  automatica: varias apps no tienen un camino de vuelta fiable)
- Filtro por categoria, badges de riesgo (seguro/precaucion)

### Herramientas
- Liberador de RAM: comprime los working sets accesibles y purga la Standby List del
  kernel via `NtSetSystemInformation`
- Procesos pesados: CPU% real (sin Sleep), RAM, botones Terminar con triple validacion de seguridad
- Dispositivos con problemas (Win32_PnPEntity con error de configuracion)
- TRIM / desfragmentacion: en SSD re-habilita TRIM y corre `Optimize-Volume -ReTrim`; en
  HDD activa la desfragmentacion semanal automatica de Windows

### Sistema de licencias
- **Free:** limpieza y diagnostico basico
- **Pro:** todos los tweaks, backups, bloatware, mantenimiento automatico
- **Tecnico:** Pro + modo CLI + multi-PC
- Trial de 14 dias con banner de estado en Home
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
