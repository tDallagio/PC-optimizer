# WinBoost — PENDIENTES

> **Instruccion para Claude Code:** Leer este archivo al arrancar cada sesion.
> El desarrollo v4.x en PowerShell esta COMPLETO (41/41) y jubilado a `legacy/` (corte 6.3).
> La migracion a C#/WPF (carpeta `src-csharp/`) tambien esta COMPLETA: es la unica version
> oficial y distribuida. El trabajo ACTIVO ahora es la seccion "Pendientes de producto /
> distribucion" mas abajo (code signing, rediseno del modelo de licencias, pre-lanzamiento).
> Marcar [x] al completar. Al terminar un item, actualizar tambien CHANGELOG.md. Reglas C# en
> CLAUDE.md.

---

## Migracion a C# / WPF — COMPLETA (corte 6.3)

El `.ps1` original (10.400 lineas) migro a C#/WPF de forma incremental y la migracion cerro
con el corte 6.3: `src-csharp/` es la unica version oficial y distribuida, el `.ps1` fue
jubilado a `legacy/`. Fases historicas de la migracion (referencia, todas completas):

### FASE 0 — Andamiaje + infraestructura
- [x] 0.1 Proyecto C# WPF (.NET 8) en `src-csharp/`
- [x] 0.2 MainWindow carga el XAML actual (compilado); x:Name -> campos tipados (mueren los Get-Ctrl)
- [x] 0.3 NativeMethods: portar los dos bloques P/Invoke (ntdll/psapi/advapi32/kernel32 + user32)
- [x] 0.4 Infraestructura base: logging, Set-Progress, toasts, settings (JSON), theme
- [x] 0.5 Patron async base (servicio para correr trabajo fuera del hilo UI)
- **Meta de cierre:** la app abre, el sidebar navega, los settings cargan

### FASE 1 — Nucleo de seguridad (backup/restore)
- [x] 1.1 BackupService: New-BackupSession + Save-*Backup (Reg/Svc/Net/PowerPlan/PageFile/Netsh)
- [x] 1.2 Restore-* completos + Get-BackupSessions + Cleanup
- [x] 1.3 Validar contra el motor de backup del PS1

### FASE 2 — Diagnostico read-only (valida la fluidez async)
- [x] 2.1 System info + score + auditoria
- [x] 2.2 Snapshots (boot time, RAM idle, conteo procesos) + Compare
- [x] 2.3 Temperaturas CPU/GPU/thermal
- [x] 2.4 Procesos pesados (async, sin Sleep en hilo UI)
- [x] 2.5 Dispositivos con problemas + inventario de drivers
- **Meta de cierre:** confirmar que la UI no se congela en ninguna de estas operaciones

### FASE 3 — Motor de optimizacion
- [x] 3.1 OptimizationService: Apply-Preset + Invoke-*Tweaks (cleanup/registry/network/service)
- [x] 3.2 Build-ActionPlan + modelo de action plan
- [x] 3.3 Dialogos de confirmacion / analisis
- [x] 3.4 Invoke-OptimizeFinish + resumen aplicado/omitido
- [x] 3.5 Modo silencioso CLI (-Silent -Preset)

### FASE 4 — Features independientes (paralelizable)
- [x] 4.1 Bloatware (AppX + winget)
- [x] 4.2 Startup manager
- [x] 4.3 Mantenimiento (tarea programada)
- [x] 4.4 Game Focus Mode (P/Invoke user32 + afinidad de CPU)
- [x] 4.5 Purga de RAM (Standby List)
- [x] 4.6 Historial + score history
- [x] 4.7 Reporte HTML
- [x] 4.8 Dialogo de comparacion

### FASE 5 — Licencias + onboarding + updater
- [x] 5.1 Licencias: RSA-2048, trial, lock Pro, badge
- [x] 5.2 First-run / onboarding / changelog
- [x] 5.3 Auto-updater (Check / Download / Apply) en C#

### FASE 6 — Tuning tab + pulido estetico + corte
- [x] 6.1 Tuning tab: reconstruir como XAML declarativo (achica el Build-TuningTab de 1.200 lineas)
- [x] 6.2 Sistema de diseno: tokens de espaciado/tipografia, acento unico, estados hover/pressed/disabled, transiciones
- [x] 6.3 Corte: jubilar el `.ps1`, actualizar README e instalador
      `.ps1` + cadena legacy (`OptimizarPC_App.ps1`, `OptimizarPC_UI.xaml`, `Build.ps1`,
      `installer/WinBoost.iss`, `EJECUTAR_COMO_ADMIN.bat`, `dist/`) movidos a `legacy/` (con
      `legacy/README.md` documentando el descontinuo y la clave RSA vieja embebida, ya rotada).
      C# (`src-csharp/`) queda como unica version oficial y distribuida. README.md principal y
      CLAUDE.md reescritos para describir la app C#. Detalle completo en CHANGELOG.md.
      Nota: el item decia estar supeditado tambien a "code signing", que sigue pendiente (ver
      Bloqueante de distribucion, mas abajo, todavia sin resolver) — el corte del PS1 se ejecuto
      igual porque es independiente de la firma (retira el binario viejo y la clave RSA
      comprometida asociada; no afecta ni resuelve la advertencia de SmartScreen del instalador
      C#, que sigue abierta).

---

## Pendientes de producto / distribucion

### Bloqueante de distribucion
- [ ] **Code signing** — certificado OV (~100-200 USD/ano; Sectigo, DigiCert o GlobalSign).
      La migracion a C# elimina el falso positivo de Defender (Wacatac), pero SmartScreen
      sigue necesitando firma para reputacion. Integrar en Build.ps1 cuando se obtenga.
      - [ ] Verificacion de firma Authenticode en el updater. Tras descargar el instalador y antes de
            ApplyUpdate, verificar que este firmado con el certificado de WinBoost (p. ej.
            Get-AuthenticodeSignature en el helper, o WinVerifyTrust), y abortar si la firma no es
            valida o el firmante no es el esperado. Depende de: code signing (item padre). Motivo:
            hoy la integridad del update se apoya solo en el SHA256, que sale del mismo version.json
            que el DownloadUrl y por lo tanto no protege contra un repo comprometido; el instalador
            se ejecuta en silencio y elevado. Archivo afectado: Services/UpdateService.cs
            (ApplyUpdate) y el flujo de MainWindow que orquesta Check/Download/Verify/Apply. Resto
            del ciclo (Check, Download, gate SHA256, Apply+relaunch) validado OK en la regresion
            sobre el .exe publicado — lo unico pendiente aca es la verificacion de firma.

### Resuelto
- [x] Bug del single-file publicado: `FileNotFoundException` de `System.Text.RegularExpressions`
      al primer Regex ejecutado (`BackupService.SaveRegBackup`), tumbaba todas las escrituras de
      registro y el backup del plan de energia en el .exe publicado (no en `dotnet build`
      Debug). Causa raiz: cache de extraccion parcial de `IncludeAllContentForSelfExtract`
      (confirmado con evidencia real, no trimming). Fix: se saco ese flag del pubxml
      (`win-x64-selfcontained.pubxml`) y se reemplazo el Regex de `SaveRegBackup` por
      `SanitizeFileName` sin dependencia de `System.Text.RegularExpressions`. Detalle completo
      en CHANGELOG.md.

### Modelo de licencias (rediseño pendiente)
Hallazgos de la regresion de licencias sobre el .exe publicado (parte criptografica validada OK:
firma RSA-2048, Pro atado a HWID, rechazo de claves invalidas/HWID ajeno, persistencia tras
reinicio). Dos debilidades de DISEÑO del modelo actual, no se arreglan ahora — el modelo de
licencias no es el definitivo, se va a redisenar antes del lanzamiento final. Quedan registradas
para que el rediseño no repita los patrones:

- [ ] Trial sin proteccion de integridad (validacion client-side burlable). El estado del trial
      vive en settings.json (TrialStartDate / TrialExpired) en texto plano, sin firma ni anclaje.
      Vectores confirmados en testeo: (a) fecha futura -> cientos de dias de trial; (b) borrar
      settings.json -> trial nuevo repetible; (c) resetear la fecha a hoy -> trial eterno; (d)
      atrasar el reloj del sistema -> el trial no avanza. Un trial client-side es intrinsecamente
      burlable sin servidor. Resolucion objetivo: anclar la integridad del trial al proxy backend
      (el mismo previsto para la IA) cuando exista; como mitigacion intermedia sin servidor, HMAC
      del estado + anclaje redundante (registro/archivo) + anti-rollback de reloj. Decision de
      alcance pendiente para el modelo definitivo.
- [ ] Clave Tech es una llave maestra global (firma sobre constante, sin variable). La firma RSA
      de la clave Tech es sobre la constante "WINBOOST-TECH", sin HWID ni identificador de
      comprador, por lo que Gen-License.ps1 genera SIEMPRE la misma cadena: una sola clave
      desbloquea la app en cualquier PC, para siempre, sin revocacion posible. Si se filtra o se
      revende, se pierde el tier entero. Regla de diseno a adoptar en el modelo definitivo: toda
      clave que valga dinero firma sobre algo UNICO (minimo el HWID, idealmente HWID +
      comprador/ID de compra); una firma sobre constante solo es aceptable para uso
      interno/testing. Destino previsto de Tech: degradar a clave de testing interna, O
      reconstruir como tier de pago unico ("lifetime"/ULTRA) firmando sobre
      WINBOOST-<TIER>-<HWID>(-<comprador>) en vez de una constante. Decidir en el rediseño.

  Nota (direccion tentativa, no accionable todavia): degradar Tech (ver arriba), posible tier
  nuevo por encima de Pro (nombre tentativo ULTRA) — requiere pasar el gating de booleanos
  IS_PRO/IS_TECH a niveles ordenables y un mensaje de firma propio por tier —, y bajar el trial de
  14 a 3-7 dias (evaluar junto con que otorga el trial, ya que hoy da Pro completo).

### Pre-lanzamiento
- [ ] Testing externo en Win10 y Win11 limpios, SOBRE EL .EXE PUBLICADO (self-contained
      single-file) de Publish-CSharp.ps1, no sobre el Debug — pasada de regresion completa:
      optimizacion al 100%, backup/restore revierte valores reales, bloatware, licencias
      Free/Pro/Tech, auto-updater, escaneo de driver store (usan Regex; confirmar que no fallan
      en el publicado). Pasar a 2-3 personas, traer bugs al chat.
- [ ] Landing page (before/after de metricas reales del reporte HTML, tweaks documentados,
      planes Free/Pro/Tecnico, boton de descarga al release, seccion "que cambia exactamente")
- [ ] Primer feedback real (3-5 usuarios; define la siguiente version)

### Pulido del repo
- [ ] Topics: windows, optimization, powershell, wpf, performance
- [ ] Descripcion "About" del repo
- [ ] Capturas de pantalla en el README

### Procedimiento de release (referencia, probado en v4.1)
1. Bump de version en los 4 lugares: $VERSION (App.ps1), ps2exe (Build.ps1), version.json, define del .iss
2. Build.ps1 (admin) + compilar el .iss con Inno Setup
3. Calcular SHA256 del instalador -> version.json (sha256 + downloadUrl a la nueva version)
4. Publicar release con el instalador como asset (nombre exacto = el del downloadUrl)
5. Push de version.json a main
6. Verificar la raw URL + probar el update desde una version anterior

---

## Descartado / No implementar

- Selector de idioma EN/PT — lanzar solo en espanol
- Benchmark de disco — CrystalDiskMark existe y es gratis
- Verificacion SHA256 del XAML — optimizacion prematura
- Ofuscacion del PS1 — optimizacion prematura sin usuarios
- Verificacion online de versiones de drivers — fragil desde PS5.1
- ~~Runspace completo (8.1)~~ — SUPERADO: se resuelve con la migracion a C# (async nativo)

---

## Historico — PowerShell v4.x COMPLETO (41/41)

El desarrollo de la app en PowerShell esta cerrado al 100%. Detalle de cada item en
`CHANGELOG.md`. Roadmap original archivado en `docs/ROADMAP_v4_ps_legacy.md`.

| Fase | Items | Hecho |
|------|-------|-------|
| F0 — Prerequisitos y bugs criticos | 12 | 12 |
| F1 — Lanzamiento | 9 | 9 |
| F2 — Post-lanzamiento | 20 | 20 |
| Auto-updater v4.1 (Camino B) | — | hecho |
| **TOTAL** | **41** | **41** |
