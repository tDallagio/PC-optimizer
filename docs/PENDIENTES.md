# WinBoost — PENDIENTES

> **Instruccion para Claude Code:** Leer este archivo al arrancar cada sesion.
> El desarrollo v4.x en PowerShell esta COMPLETO (41/41). El trabajo ACTIVO ahora es
> la migracion a C#/WPF (carpeta `src-csharp/`). Implementar los items EN ORDEN por su
> identificador (0.4, 0.5, 1.1, ...). Marcar [x] al completar. Al terminar un item,
> actualizar tambien CHANGELOG.md. Reglas C# en CLAUDE.md.

---

## Migracion a C# / WPF — TRABAJO ACTIVO

El `.ps1` (10.400 lineas) migra a C#/WPF de forma incremental. El XAML se reusa. El PS1
sigue siendo la version distribuida hasta paridad. Validar cada modulo contra el
comportamiento del PS1 original.

### FASE 0 — Andamiaje + infraestructura
- [x] 0.1 Proyecto C# WPF (.NET 8) en `src-csharp/`
- [x] 0.2 MainWindow carga el XAML actual (compilado); x:Name -> campos tipados (mueren los Get-Ctrl)
- [x] 0.3 NativeMethods: portar los dos bloques P/Invoke (ntdll/psapi/advapi32/kernel32 + user32)
- [x] 0.4 Infraestructura base: logging, Set-Progress, toasts, settings (JSON), theme
- [x] 0.5 Patron async base (servicio para correr trabajo fuera del hilo UI)
- **Meta de cierre:** la app abre, el sidebar navega, los settings cargan

### FASE 1 — Nucleo de seguridad (backup/restore)
- [ ] 1.1 BackupService: New-BackupSession + Save-*Backup (Reg/Svc/Net/PowerPlan/PageFile/Netsh)
- [ ] 1.2 Restore-* completos + Get-BackupSessions + Cleanup
- [ ] 1.3 Validar contra el motor de backup del PS1

### FASE 2 — Diagnostico read-only (valida la fluidez async)
- [ ] 2.1 System info + score + auditoria
- [ ] 2.2 Snapshots (boot time, RAM idle, conteo procesos) + Compare
- [ ] 2.3 Temperaturas CPU/GPU/thermal
- [ ] 2.4 Procesos pesados (async, sin Sleep en hilo UI)
- [ ] 2.5 Dispositivos con problemas + inventario de drivers
- **Meta de cierre:** confirmar que la UI no se congela en ninguna de estas operaciones

### FASE 3 — Motor de optimizacion
- [ ] 3.1 OptimizationService: Apply-Preset + Invoke-*Tweaks (cleanup/registry/network/service)
- [ ] 3.2 Build-ActionPlan + modelo de action plan
- [ ] 3.3 Dialogos de confirmacion / analisis
- [ ] 3.4 Invoke-OptimizeFinish + resumen aplicado/omitido
- [ ] 3.5 Modo silencioso CLI (-Silent -Preset)

### FASE 4 — Features independientes (paralelizable)
- [ ] 4.1 Bloatware (AppX + winget)
- [ ] 4.2 Startup manager
- [ ] 4.3 Mantenimiento (tarea programada)
- [ ] 4.4 Game Focus Mode (P/Invoke user32 + afinidad de CPU)
- [ ] 4.5 Purga de RAM (Standby List)
- [ ] 4.6 Historial + score history
- [ ] 4.7 Reporte HTML
- [ ] 4.8 Dialogo de comparacion

### FASE 5 — Licencias + onboarding + updater
- [ ] 5.1 Licencias: RSA-2048, trial, lock Pro, badge
- [ ] 5.2 First-run / onboarding / changelog
- [ ] 5.3 Auto-updater (Check / Download / Apply) en C#

### FASE 6 — Tuning tab + pulido estetico + corte
- [ ] 6.1 Tuning tab: reconstruir como XAML declarativo (achica el Build-TuningTab de 1.200 lineas)
- [ ] 6.2 Sistema de diseno: tokens de espaciado/tipografia, acento unico, estados hover/pressed/disabled, transiciones
- [ ] 6.3 Corte: jubilar el `.ps1`, actualizar README e instalador

---

## Pendientes de producto / distribucion

### Bloqueante de distribucion
- [ ] **Code signing** — certificado OV (~100-200 USD/ano; Sectigo, DigiCert o GlobalSign).
      La migracion a C# elimina el falso positivo de Defender (Wacatac), pero SmartScreen
      sigue necesitando firma para reputacion. Integrar en Build.ps1 cuando se obtenga.

### Pre-lanzamiento
- [ ] Testing externo en Win10 y Win11 limpios (pasar a 2-3 personas, traer bugs al chat)
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
