using System.Diagnostics;
using System.Linq;
using System.Management;
using System.ServiceProcess;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace WinBoost.Services;

// Piloto Fase A (38_fase_a_registro_tweaks_piloto.txt): modelo de datos para el registro unico
// de tweaks (toggles inmediatos, prender = aplica ya / apagar = revierte ya). Precede a escalar
// el patron a los ~25 tweaks reales de Optimizar (Fase B) -- ver docs/ARQUITECTURA_TWEAKS.md.

public enum TweakState { On, Off, NoAplicable }

// Combina estado + motivo (solo relevante para NoAplicable, ej. "requiere SSD" en Fase B) en un
// mismo valor para que el motivo pueda viajar hasta la UI sin un segundo canal separado.
public sealed record TweakStatus(TweakState State, string? Motivo = null)
{
    public static readonly TweakStatus On  = new(TweakState.On);
    public static readonly TweakStatus Off = new(TweakState.Off);
    public static TweakStatus NotApplicable(string motivo) => new(TweakState.NoAplicable, motivo);
}

public sealed record TweakDefinition(
    string Id,
    string Nombre,
    string Descripcion,
    string Categoria,
    bool RequiereReinicio,
    Func<Task> AplicarAsync,
    Func<Task> RevertirAsync,
    Func<Task<TweakStatus>> LeerEstadoAsync);

public sealed class TweakRegistry
{
    public IReadOnlyList<TweakDefinition> All { get; }

    public TweakRegistry()
    {
        All =
        [
            new TweakDefinition(
                Id:               "Telemetry",
                Nombre:           "Telemetria de Windows",
                Descripcion:      "Detiene el envio de datos de diagnostico y uso de Windows a Microsoft.",
                Categoria:        "Privacidad",
                RequiereReinicio: false,
                AplicarAsync:     ApplyTelemetryAsync,
                RevertirAsync:    RevertTelemetryAsync,
                LeerEstadoAsync:  ReadTelemetryAsync),

            new TweakDefinition(
                Id:               "SvcDiag",
                Nombre:           "Servicio de telemetria (DiagTrack)",
                Descripcion:      "Deshabilita el servicio Connected User Experiences and Telemetry, que recopila datos de diagnostico en segundo plano.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     ApplySvcDiagAsync,
                RevertirAsync:    RevertSvcDiagAsync,
                LeerEstadoAsync:  ReadSvcDiagAsync),

            new TweakDefinition(
                Id:               "Tasks",
                Nombre:           "Tareas programadas de recopilacion de datos",
                Descripcion:      "Deshabilita 5 tareas programadas que Windows usa para recopilar datos de diagnostico, compatibilidad y uso.",
                Categoria:        "Privacidad",
                RequiereReinicio: false,
                AplicarAsync:     ApplyTasksAsync,
                RevertirAsync:    RevertTasksAsync,
                LeerEstadoAsync:  ReadTasksAsync),

            new TweakDefinition(
                Id:               "TCP",
                Nombre:           "TCP/IP para gaming",
                Descripcion:      "Ajusta auto-tuning, RSS y TCP Fast Open para reducir latencia de red en juegos online.",
                Categoria:        "Red",
                RequiereReinicio: false,
                AplicarAsync:     ApplyTcpAsync,
                RevertirAsync:    RevertTcpAsync,
                LeerEstadoAsync:  ReadTcpAsync),

            new TweakDefinition(
                Id:               "PageFile",
                Nombre:           "Archivo de paginacion (PageFile)",
                Descripcion:      "Fija el tamano del archivo de paginacion segun la RAM detectada, en vez de dejarlo en gestion automatica de Windows.",
                Categoria:        "Rendimiento",
                RequiereReinicio: true,
                AplicarAsync:     ApplyPageFileAsync,
                RevertirAsync:    RevertPageFileAsync,
                LeerEstadoAsync:  ReadPageFileAsync),

            // ── Fase B, Tanda 1 (40_fase_b_tanda_1_registro_directo.txt) ──────────────────

            new TweakDefinition(
                Id:               "GPUPrio",
                Nombre:           "Prioridad de GPU para juegos",
                Descripcion:      "Sube la prioridad de GPU y CPU que Windows asigna a los juegos en primer plano.",
                Categoria:        "Rendimiento",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplyRegEntriesAsync("GPUPrio", GpuPrioEntries()),
                RevertirAsync:    () => RevertRegEntriesAsync("GPUPrio", GpuPrioEntries()),
                LeerEstadoAsync:  () => ReadRegEntriesAsync(GpuPrioEntries())),

            new TweakDefinition(
                Id:               "PowerThrot",
                Nombre:           "Power Throttling",
                Descripcion:      "Evita que Windows reduzca la frecuencia de CPU para ahorrar energia en procesos activos.",
                Categoria:        "Rendimiento",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplyRegEntriesAsync("PowerThrot", PowerThrotEntries()),
                RevertirAsync:    () => RevertRegEntriesAsync("PowerThrot", PowerThrotEntries()),
                LeerEstadoAsync:  () => ReadRegEntriesAsync(PowerThrotEntries())),

            new TweakDefinition(
                Id:               "MouseAccel",
                Nombre:           "Aceleracion del mouse",
                Descripcion:      "Desactiva la aceleracion del mouse para que el movimiento sea 1:1, sin curvas que dependan de la velocidad.",
                Categoria:        "Rendimiento",
                RequiereReinicio: true,
                AplicarAsync:     ApplyMouseAccelAsync,
                RevertirAsync:    RevertMouseAccelAsync,
                LeerEstadoAsync:  () => ReadRegEntriesAsync(MouseAccelEntries())),

            new TweakDefinition(
                Id:               "GameDVR",
                Nombre:           "Game DVR / Xbox Game Bar",
                Descripcion:      "Desactiva la grabacion en segundo plano de Xbox Game Bar, que puede consumir recursos mientras jugas.",
                Categoria:        "Privacidad",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplyRegEntriesAsync("GameDVR", GameDvrEntries()),
                RevertirAsync:    () => RevertRegEntriesAsync("GameDVR", GameDvrEntries()),
                LeerEstadoAsync:  () => ReadRegEntriesAsync(GameDvrEntries())),

            new TweakDefinition(
                Id:               "GameMode",
                Nombre:           "Modo Juego de Windows",
                Descripcion:      "Desactiva el Modo Juego automatico de Windows (en algunos sistemas AMD/Ryzen evita microcortes).",
                Categoria:        "Privacidad",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplyRegEntriesAsync("GameMode", GameModeEntries()),
                RevertirAsync:    () => RevertRegEntriesAsync("GameMode", GameModeEntries()),
                LeerEstadoAsync:  () => ReadRegEntriesAsync(GameModeEntries())),

            new TweakDefinition(
                Id:               "Cortana",
                Nombre:           "Cortana",
                Descripcion:      "Desactiva Cortana via politica de grupo.",
                Categoria:        "Privacidad",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplyRegEntriesAsync("Cortana", CortanaEntries()),
                RevertirAsync:    () => RevertRegEntriesAsync("Cortana", CortanaEntries()),
                LeerEstadoAsync:  () => ReadRegEntriesAsync(CortanaEntries())),

            new TweakDefinition(
                Id:               "Notif",
                Nombre:           "Notificaciones (Toast)",
                Descripcion:      "Desactiva las notificaciones emergentes de Windows para no interrumpir mientras jugas o trabajas.",
                Categoria:        "Privacidad",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplyRegEntriesAsync("Notif", NotifEntries()),
                RevertirAsync:    () => RevertRegEntriesAsync("Notif", NotifEntries()),
                LeerEstadoAsync:  () => ReadRegEntriesAsync(NotifEntries())),

            new TweakDefinition(
                Id:               "Nagle",
                Nombre:           "Algoritmo de Nagle",
                Descripcion:      "Desactiva el algoritmo de Nagle en los adaptadores de red activos para reducir la latencia de red.",
                Categoria:        "Red",
                RequiereReinicio: false,
                AplicarAsync:     ApplyNagleAsync,
                RevertirAsync:    RevertNagleAsync,
                LeerEstadoAsync:  ReadNagleAsync),

            new TweakDefinition(
                Id:               "Visual",
                Nombre:           "Efectos visuales",
                Descripcion:      "Reduce animaciones y efectos visuales de Windows para priorizar rendimiento sobre estetica. En equipos con 8 GB de RAM o menos, ademas desactiva la transparencia.",
                Categoria:        "Rendimiento",
                RequiereReinicio: false,
                AplicarAsync:     ApplyVisualAsync,
                RevertirAsync:    RevertVisualAsync,
                LeerEstadoAsync:  ReadVisualAsync),

            // ── Fase B, Tanda 2 (44_fase_b_tanda_2_servicios.txt) ──────────────────────────
            // Extiende el patron de servicios validado por SvcDiag (piloto) a 2-3 servicios por
            // tweak -- ver helper ApplySvcEntriesAsync/RevertSvcEntriesAsync mas abajo.

            new TweakDefinition(
                Id:               "SvcXbox",
                Nombre:           "Servicios de Xbox Live",
                Descripcion:      "Deshabilita XblAuthManager, XblGameSave y XboxNetApiSvc, usados para el login y el guardado en la nube de Xbox/Game Pass.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplySvcEntriesAsync("SvcXbox", SvcXboxNames),
                RevertirAsync:    () => RevertSvcEntriesAsync("SvcXbox", SvcXboxNames),
                LeerEstadoAsync:  ReadSvcXboxAsync),

            new TweakDefinition(
                Id:               "SvcWER",
                Nombre:           "Informes de error de Windows (WerSvc)",
                Descripcion:      "Deshabilita el servicio de Windows Error Reporting, que envia informes de errores y fallos a Microsoft.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplySvcEntriesAsync("SvcWER", SvcWerNames),
                RevertirAsync:    () => RevertSvcEntriesAsync("SvcWER", SvcWerNames),
                LeerEstadoAsync:  ReadSvcWerAsync),

            new TweakDefinition(
                Id:               "SvcMaps",
                Nombre:           "Servicios de Mapas y Geolocalizacion",
                Descripcion:      "Deshabilita MapsBroker y lfsvc (Geolocation), usados por apps que descargan mapas sin conexion o necesitan tu ubicacion.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplySvcEntriesAsync("SvcMaps", SvcMapsNames),
                RevertirAsync:    () => RevertSvcEntriesAsync("SvcMaps", SvcMapsNames),
                LeerEstadoAsync:  ReadSvcMapsAsync),

            new TweakDefinition(
                Id:               "SvcFax",
                Nombre:           "Servicios de Fax y Registro remoto",
                Descripcion:      "Deshabilita Fax y RemoteRegistry, en desuso en la gran mayoria de los equipos modernos.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplySvcEntriesAsync("SvcFax", SvcFaxNames),
                RevertirAsync:    () => RevertSvcEntriesAsync("SvcFax", SvcFaxNames),
                LeerEstadoAsync:  ReadSvcFaxAsync),

            // ── Fase B, Tanda 3 (45_fase_b_tanda_3_hpet_faststartup.txt) ───────────────────

            new TweakDefinition(
                Id:               "HPET",
                Nombre:           "HPET (temporizador de plataforma)",
                Descripcion:      "Desactiva el temporizador HPET como reloj de plataforma para que Windows use el TSC de la CPU, reduciendo la sobrecarga del timer en juegos sensibles a la latencia.",
                Categoria:        "Sistema y Rendimiento",
                RequiereReinicio: true,
                AplicarAsync:     ApplyHpetAsync,
                RevertirAsync:    RevertHpetAsync,
                LeerEstadoAsync:  ReadHpetAsync),

            new TweakDefinition(
                Id:               "FastStartup",
                Nombre:           "Inicio rapido (Fast Startup)",
                Descripcion:      "Desactiva el inicio rapido y la hibernacion de Windows, que pueden causar problemas de arranque con actualizaciones de drivers, doble arranque o discos NVMe.",
                Categoria:        "Sistema y Rendimiento",
                RequiereReinicio: false,
                AplicarAsync:     ApplyFastStartupAsync,
                RevertirAsync:    RevertFastStartupAsync,
                LeerEstadoAsync:  ReadFastStartupAsync),

            // ── Fase B, Tanda 4 (46_fase_b_tanda_4_svcsysmain_svcwsearch.txt) ──────────────
            // Cierra la categoria Servicios (7/7).

            new TweakDefinition(
                Id:               "SvcSysMain",
                Nombre:           "Superfetch (SysMain)",
                Descripcion:      "Deshabilita SysMain (Superfetch), que precarga apps en RAM segun el uso -- pensado para HDD, sin beneficio real en discos SSD/NVMe.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplySvcIfSsdAsync("SvcSysMain", "SysMain"),
                RevertirAsync:    () => RevertSvcIfSsdAsync("SvcSysMain", "SysMain"),
                LeerEstadoAsync:  () => ReadSvcIfSsdAsync("SysMain")),

            new TweakDefinition(
                Id:               "SvcWSearch",
                Nombre:           "Busqueda de Windows (WSearch)",
                Descripcion:      "Deshabilita WSearch, el indexado de archivos de Windows -- pensado para acelerar busquedas en HDD, innecesario en discos SSD/NVMe.",
                Categoria:        "Servicios",
                RequiereReinicio: false,
                AplicarAsync:     () => ApplySvcIfSsdAsync("SvcWSearch", "WSearch"),
                RevertirAsync:    () => RevertSvcIfSsdAsync("SvcWSearch", "WSearch"),
                LeerEstadoAsync:  () => ReadSvcIfSsdAsync("WSearch")),
        ];
    }

    public TweakDefinition? Find(string id) => All.FirstOrDefault(t => t.Id == id);

    // ══ Fase B, Tanda 1 (40_fase_b_tanda_1_registro_directo.txt) ═══════════════════════════
    // ── Helper compartido de "registro directo" (Familia 1 de ARQUITECTURA_TWEAKS.md) ────
    // 7 de los 9 tweaks de esta tanda son N valores fijos en 1 o mas keys HKLM/HKCU, siempre
    // aplicados/revertidos igual: capturar el original SOLO la primera vez (incluyendo "no
    // existia" como valor valido, mismo criterio que Telemetry del piloto) y despues
    // escribir/restaurar. En vez de duplicar ese bloque 7 veces (y de nuevo en cada tanda futura
    // de esta misma familia, ~12 tweaks segun ARQUITECTURA_TWEAKS.md), se factoriza en un helper
    // generico -- Nagle y Visual quedan afuera porque no encajan (N dinamico de adaptadores y un
    // valor condicional a RAM, respectivamente).
    //
    // Decision de diseño aplicada a los 7 (documentada una sola vez aca, vale para GPUPrio,
    // MouseAccel, GameDVR; PowerThrot/Cortana/Notif no tienen asimetria así que es lo mismo
    // cualquier criterio): LeerEstadoAsync exige que TODOS los valores que Apply realmente
    // escribe coincidan, no solo el proxy parcial que usan los Check* del health score (ej.
    // CheckGpuPrio solo mira "GPU Priority", CheckMouseAccel solo "MouseSpeed", CheckGameDvr solo
    // "GameDVR_Enabled"). Mismo argumento que Telemetry en el piloto: el toggle es el estado
    // autoritativo de ESE tweak especifico para el usuario -- un proxy parcial podria mostrar On
    // con 4 de 5 valores revertidos por fuera de WinBoost. El health score en SystemInfoService.cs
    // no se toco (sigue usando su proxy liviano, es codigo distinto con otro proposito). Por eso
    // ninguno de los Check* existentes se reusa aca (ni siquiera PowerThrot/Cortana, que si
    // coinciden 1 a 1 con Apply): usar el mismo helper generico para los 7 es mas simple y
    // consistente que mezclar "algunos reusan un Check* de SystemInfoService, otros no".
    private sealed record RegEntry(RegistryHive Hive, string SubKey, string Name, RegistryValueKind Kind, object Value);

    private static string? ReadRegValueAsString(RegistryHive hive, string subKey, string name)
    {
        using var root = RegistryKey.OpenBaseKey(hive, RegistryView.Default);
        using var key  = root.OpenSubKey(subKey);
        return key?.GetValue(name)?.ToString();
    }

    private static Task ApplyRegEntriesAsync(string id, RegEntry[] entries) => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry(id))
        {
            string?[] original = entries.Select(e => ReadRegValueAsString(e.Hive, e.SubKey, e.Name)).ToArray();
            App.TweakState.SaveOriginal(id, original);
        }
        foreach (var e in entries)
        {
            using var key = RegistryPrivilegeHelper.OpenWritable(e.Hive, e.SubKey);
            key?.SetValue(e.Name, e.Value, e.Kind);
        }
        App.TweakState.SetAppliedByWinBoost(id, true);
    });

    private static Task RevertRegEntriesAsync(string id, RegEntry[] entries) => Task.Run(() =>
    {
        // Sin entrada = WinBoost nunca aplico este tweak desde esta seccion -- no-op (mismo
        // criterio que los 5 del piloto, fix 39).
        if (!App.TweakState.HasEntry(id)) return;

        string?[]? original = App.TweakState.ReadOriginal<string?[]>(id);
        if (original is null) return;

        for (int i = 0; i < entries.Length; i++)
        {
            var    e = entries[i];
            string? v = i < original.Length ? original[i] : null;
            using var key = RegistryPrivilegeHelper.OpenWritable(e.Hive, e.SubKey);
            if (key is null) continue;
            if (v is null) key.DeleteValue(e.Name, throwOnMissingValue: false);
            else key.SetValue(e.Name, e.Kind == RegistryValueKind.DWord ? int.Parse(v) : v, e.Kind);
        }
        App.TweakState.SetAppliedByWinBoost(id, false);
    });

    private static Task<TweakStatus> ReadRegEntriesAsync(RegEntry[] entries) => Task.Run(() =>
    {
        bool allMatch = entries.All(e =>
            string.Equals(ReadRegValueAsString(e.Hive, e.SubKey, e.Name), e.Value.ToString(),
                StringComparison.OrdinalIgnoreCase));
        return allMatch ? TweakStatus.On : TweakStatus.Off;
    });

    // ── GPUPrio ────────────────────────────────────────────────────────────────
    // Apply hoy (OptimizationService) escribe los 5 valores en una sola key. Nota de robustez ya
    // conocida (ver comentario de OptimizationService/RegistryPrivilegeHelper): esta key puede
    // traer ACL protegida en instalaciones limpias -- ApplyRegEntriesAsync ya usa
    // RegistryPrivilegeHelper.OpenWritable para TODAS las entradas (no solo esta), asi que queda
    // cubierto sin caso especial.
    private static RegEntry[] GpuPrioEntries()
    {
        const string key = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games";
        return
        [
            new(RegistryHive.LocalMachine, key, "GPU Priority",         RegistryValueKind.DWord,  8),
            new(RegistryHive.LocalMachine, key, "Priority",             RegistryValueKind.DWord,  6),
            new(RegistryHive.LocalMachine, key, "Scheduling Category",  RegistryValueKind.String, "High"),
            new(RegistryHive.LocalMachine, key, "SFIO Priority",        RegistryValueKind.String, "High"),
            new(RegistryHive.LocalMachine, key, "Background Only",     RegistryValueKind.String, "False"),
        ];
    }

    // ── PowerThrot ─────────────────────────────────────────────────────────────
    // El mas simple de la tanda: 1 solo valor, Apply y el checker existente (CheckPowerThrot)
    // coinciden exactamente -- no hay decision pendiente.
    private static RegEntry[] PowerThrotEntries() =>
    [
        new(RegistryHive.LocalMachine, @"SYSTEM\CurrentControlSet\Control\Power\PowerThrottling",
            "PowerThrottlingOff", RegistryValueKind.DWord, 1),
    ];

    // ── MouseAccel ─────────────────────────────────────────────────────────────
    // Mezcla HKCU (3 valores) + HKLM (1 valor, mouclass) en un solo tweak -- RegEntry no asume
    // que todas las entradas compartan hive/key, asi que no hace falta caso especial para eso.
    //
    // Fix 43 (43_fix_mouseaccel_no_aplica_realmente.txt): confirmado que el registro SI quedaba
    // escrito (verificado en vivo, ACL de mouclass\Parameters sin restriccion para Administradores
    // -- no era el caso del prompt 42), pero el cambio no se notaba en la maquina real por DOS
    // motivos distintos, uno por cada mitad del tweak:
    // - MouseSpeed/MouseThreshold1/MouseThreshold2 ("Mejorar precision del puntero" de Panel de
    //   Control): Windows cachea estos 3 a nivel de sesion; escribir el registro directo no los
    //   aplica en vivo, solo persiste el valor para el proximo logon. Fix: llamar
    //   NativeMethods.SetMouseAcceleration (SystemParametersInfo/SPI_SETMOUSE) despues de
    //   escribir, la MISMA API que usa Panel de Control -- toma efecto ya, sin logon ni reinicio.
    // - MouseDataQueueSize: parametro de un DRIVER DE KERNEL (mouclass.sys), que solo relee sus
    //   parametros al cargar. No hay API de "aplicar ya" como con el mouse -- necesita reinicio (o
    //   como minimo re-habilitar el dispositivo desde el Administrador de dispositivos), igual que
    //   PageFile/HPET. RequiereReinicio pasa a true para todo el tweak (peor caso del combinado).
    private static RegEntry[] MouseAccelEntries() =>
    [
        new(RegistryHive.CurrentUser,  @"Control Panel\Mouse", "MouseSpeed",      RegistryValueKind.String, "0"),
        new(RegistryHive.CurrentUser,  @"Control Panel\Mouse", "MouseThreshold1", RegistryValueKind.String, "0"),
        new(RegistryHive.CurrentUser,  @"Control Panel\Mouse", "MouseThreshold2", RegistryValueKind.String, "0"),
        new(RegistryHive.LocalMachine, @"SYSTEM\CurrentControlSet\Services\mouclass\Parameters",
            "MouseDataQueueSize", RegistryValueKind.DWord, 20),
    ];

    private static async Task ApplyMouseAccelAsync()
    {
        await ApplyRegEntriesAsync("MouseAccel", MouseAccelEntries());
        NotifyMouseSettingsChanged();
    }

    private static async Task RevertMouseAccelAsync()
    {
        await RevertRegEntriesAsync("MouseAccel", MouseAccelEntries());
        NotifyMouseSettingsChanged();
    }

    // Relee lo que haya QUEDADO en el registro (recien aplicado o recien revertido, da igual) y lo
    // empuja a la sesion en curso -- no asume la direccion, asi sirve para las dos.
    private static void NotifyMouseSettingsChanged()
    {
        try
        {
            using var key  = Registry.CurrentUser.OpenSubKey(@"Control Panel\Mouse");
            int speed      = int.TryParse(key?.GetValue("MouseSpeed")?.ToString(),      out var s)  ? s  : 0;
            int threshold1 = int.TryParse(key?.GetValue("MouseThreshold1")?.ToString(), out var t1) ? t1 : 0;
            int threshold2 = int.TryParse(key?.GetValue("MouseThreshold2")?.ToString(), out var t2) ? t2 : 0;
            NativeMethods.SetMouseAcceleration(threshold1, threshold2, speed);
        }
        catch { }
    }

    // ── GameDVR ────────────────────────────────────────────────────────────────
    private static RegEntry[] GameDvrEntries() =>
    [
        new(RegistryHive.CurrentUser,  @"System\GameConfigStore", "GameDVR_Enabled",                  RegistryValueKind.DWord, 0),
        new(RegistryHive.CurrentUser,  @"System\GameConfigStore", "GameDVR_FSEBehaviorMode",           RegistryValueKind.DWord, 2),
        new(RegistryHive.CurrentUser,  @"System\GameConfigStore", "GameDVR_HonorUserFSEBehaviorMode",  RegistryValueKind.DWord, 1),
        new(RegistryHive.LocalMachine, @"SOFTWARE\Policies\Microsoft\Windows\GameDVR", "AllowGameDVR", RegistryValueKind.DWord, 0),
    ];

    // ── GameMode ───────────────────────────────────────────────────────────────
    // Sin checker en SystemInfoService (confirmado: no aparece en el switch Check(id)).
    private static RegEntry[] GameModeEntries() =>
    [
        new(RegistryHive.CurrentUser, @"Software\Microsoft\GameBar", "AutoGameModeEnabled", RegistryValueKind.DWord, 0),
        new(RegistryHive.CurrentUser, @"Software\Microsoft\GameBar", "AllowAutoGameMode",   RegistryValueKind.DWord, 0),
    ];

    // ── Cortana ────────────────────────────────────────────────────────────────
    // Simple, sin asimetria (igual que PowerThrot).
    private static RegEntry[] CortanaEntries() =>
    [
        new(RegistryHive.LocalMachine, @"SOFTWARE\Policies\Microsoft\Windows\Windows Search",
            "AllowCortana", RegistryValueKind.DWord, 0),
    ];

    // ── Notif ──────────────────────────────────────────────────────────────────
    // Sin checker en SystemInfoService (confirmado: no aparece en el switch Check(id)).
    private static RegEntry[] NotifEntries() =>
    [
        new(RegistryHive.CurrentUser, @"Software\Microsoft\Windows\CurrentVersion\PushNotifications",
            "ToastEnabled", RegistryValueKind.DWord, 0),
    ];

    // ── Nagle ──────────────────────────────────────────────────────────────────
    // El unico de esta tanda que no encaja en el helper generico: N adaptadores dinamicos, no una
    // lista fija de claves (mismo patron estructural que "Tasks" del piloto). Apply hoy recorre
    // TODAS las subkeys de Interfaces y toca solo las que tienen DhcpIPAddress asignado (!= vacio,
    // != "0.0.0.0"); esa lista puede variar entre corridas (adaptador que aparece/desaparece).
    //
    // Decision (documentada en CHANGELOG): LeerEstadoAsync exige que TODOS los adaptadores
    // ACTUALMENTE elegibles tengan los 2 valores en 1 -- no el "al menos uno" que usa CheckNagle
    // del health score (proxy liviano, no se toco). Mismo argumento que el resto de la tanda: un
    // toggle que dijera On con 1 de 5 adaptadores tocados seria un proxy demasiado debil. Riesgo
    // conocido y aceptado: un adaptador que se conecta DESPUES de aplicar (uno que WinBoost nunca
    // vio) hace que el toggle pase a Off aunque nada haya "retrocedido" en los adaptadores que si
    // se tocaron -- se considera el comportamiento mas honesto (ese adaptador nuevo realmente no
    // tiene el ajuste), no un bug.
    // Caso NoAplicable (usa el estado que el piloto dejo preparado para esto, primera vez que se
    // necesita de verdad): 0 adaptadores elegibles ahora mismo (ej. maquina toda con IP estatica)
    // -> sin este guard, `.All()` sobre una lista vacia da true (vacuous truth) y el toggle
    // mostraria On sin que haya nada tocado.
    private const string NagleIfRoot = @"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces";

    private sealed record NagleOriginal(int? TcpAckFrequency, int? TCPNoDelay);

    private static List<string> GetEligibleNagleAdapters()
    {
        var result = new List<string>();
        using var root = Registry.LocalMachine.OpenSubKey(NagleIfRoot);
        if (root is null) return result;
        foreach (string sub in root.GetSubKeyNames())
        {
            using var iface = root.OpenSubKey(sub);
            string? ip = iface?.GetValue("DhcpIPAddress") as string;
            if (!string.IsNullOrEmpty(ip) && ip != "0.0.0.0") result.Add(sub);
        }
        return result;
    }

    private static Task ApplyNagleAsync() => Task.Run(() =>
    {
        var adapters = GetEligibleNagleAdapters();
        if (!App.TweakState.HasEntry("Nagle"))
        {
            var original = adapters.ToDictionary(sub => sub, sub => new NagleOriginal(
                ReadDwordOrNull($@"{NagleIfRoot}\{sub}", "TcpAckFrequency"),
                ReadDwordOrNull($@"{NagleIfRoot}\{sub}", "TCPNoDelay")));
            App.TweakState.SaveOriginal("Nagle", original);
        }
        foreach (var sub in adapters)
        {
            using var key = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, $@"{NagleIfRoot}\{sub}");
            key?.SetValue("TcpAckFrequency", 1, RegistryValueKind.DWord);
            key?.SetValue("TCPNoDelay",      1, RegistryValueKind.DWord);
        }
        App.TweakState.SetAppliedByWinBoost("Nagle", true);
    });

    private static Task RevertNagleAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("Nagle")) return;
        var original = App.TweakState.ReadOriginal<Dictionary<string, NagleOriginal>>("Nagle");
        if (original is null) return;

        foreach (var (sub, orig) in original)
        {
            // El adaptador ya no existe (desconectado desde que se aplico) -- no recrear la
            // subkey de la nada, RegistryPrivilegeHelper.OpenWritable la crearia si no existe.
            using (var probe = Registry.LocalMachine.OpenSubKey($@"{NagleIfRoot}\{sub}"))
                if (probe is null) continue;

            using var key = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, $@"{NagleIfRoot}\{sub}");
            if (key is null) continue;
            if (orig.TcpAckFrequency is int a) key.SetValue("TcpAckFrequency", a, RegistryValueKind.DWord);
            else key.DeleteValue("TcpAckFrequency", throwOnMissingValue: false);
            if (orig.TCPNoDelay is int n) key.SetValue("TCPNoDelay", n, RegistryValueKind.DWord);
            else key.DeleteValue("TCPNoDelay", throwOnMissingValue: false);
        }
        App.TweakState.SetAppliedByWinBoost("Nagle", false);
    });

    private static Task<TweakStatus> ReadNagleAsync() => Task.Run(() =>
    {
        var adapters = GetEligibleNagleAdapters();
        if (adapters.Count == 0)
            return TweakStatus.NotApplicable("No hay adaptadores de red con IP asignada por DHCP en este momento.");

        bool allOff = adapters.All(sub =>
            ReadDwordOrNull($@"{NagleIfRoot}\{sub}", "TcpAckFrequency") == 1 &&
            ReadDwordOrNull($@"{NagleIfRoot}\{sub}", "TCPNoDelay") == 1);
        return allOff ? TweakStatus.On : TweakStatus.Off;
    });

    // ── Visual ─────────────────────────────────────────────────────────────────
    // Apply hoy escribe 2 valores SIEMPRE + un 3ro (EnableTransparency) SOLO si la RAM total es
    // <=8GB. Decision (documentada en CHANGELOG): LeerEstadoAsync usa el mismo criterio
    // condicional -- lee la RAM real de la maquina (igual que hace Apply) y exige el 3er valor
    // SOLO cuando corresponde, para que el toggle sea honesto en maquinas con poca RAM (si se
    // ignorara la condicion, una maquina de 8GB con EnableTransparency revertido a mano seguiria
    // mostrando On). RAM leida via GlobalMemoryStatusEx (nativo, ya usado por el monitor en vivo
    // de MainWindow) en vez de SystemInfoService.GetSystemInfoAsync(): esta ultima hace varias
    // consultas WMI pesadas (CPU/GPU/SSD) para un dato que acá solo hace falta el total de RAM;
    // el monitor en vivo ya prueba que GlobalMemoryStatusEx es lo bastante rapido para llamarse
    // sincrono sin Task.Run.
    private static RegEntry[] VisualEntries(bool lowRam)
    {
        List<RegEntry> entries =
        [
            new(RegistryHive.CurrentUser, @"Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
                "VisualFXSetting", RegistryValueKind.DWord, 2),
            new(RegistryHive.CurrentUser, @"Control Panel\Desktop", "FontSmoothing", RegistryValueKind.String, "2"),
        ];
        if (lowRam)
            entries.Add(new(RegistryHive.CurrentUser,
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency",
                RegistryValueKind.DWord, 0));
        return [.. entries];
    }

    private static int GetTotalRamGb()
    {
        var status = new NativeMethods.MEMORYSTATUSEX { dwLength = NativeMethods.MemoryStatusExSize };
        // Si falla, asumir RAM alta: evita tocar EnableTransparency de mas por un dato que no se
        // pudo leer (menos sorpresa que asumir RAM baja).
        if (!NativeMethods.GlobalMemoryStatusEx(ref status)) return 999;
        return (int)Math.Round(status.ullTotalPhys / 1_073_741_824.0);
    }

    private static Task ApplyVisualAsync() =>
        ApplyRegEntriesAsync("Visual", VisualEntries(GetTotalRamGb() <= 8));

    private static Task RevertVisualAsync() =>
        RevertRegEntriesAsync("Visual", VisualEntries(GetTotalRamGb() <= 8));

    private static Task<TweakStatus> ReadVisualAsync() =>
        ReadRegEntriesAsync(VisualEntries(GetTotalRamGb() <= 8));

    // ── Telemetry ──────────────────────────────────────────────────────────────
    // Apply hoy (OptimizationService) escribe DOS claves. Decision (sin motivo historico
    // encontrado en CHANGELOG para la segunda clave): LeerEstadoAsync exige que AMBAS esten en 0
    // para reportar On -- un toggle que dijera On con una sola clave en 0 mentiria sobre lo que
    // Apply realmente aplica.
    private static readonly (string Path, string Name)[] TelemetryKeys =
    [
        (@"SOFTWARE\Policies\Microsoft\Windows\DataCollection",                  "AllowTelemetry"),
        (@"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",   "AllowTelemetry"),
    ];

    private static Task ApplyTelemetryAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("Telemetry"))
        {
            int?[] original = TelemetryKeys.Select(k => ReadDwordOrNull(k.Path, k.Name)).ToArray();
            App.TweakState.SaveOriginal("Telemetry", original);
        }
        foreach (var (path, name) in TelemetryKeys)
        {
            using var key = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, path);
            key?.SetValue(name, 0, RegistryValueKind.DWord);
        }
        App.TweakState.SetAppliedByWinBoost("Telemetry", true);
    });

    private static Task RevertTelemetryAsync() => Task.Run(() =>
    {
        // Sin entrada en el store = WinBoost nunca aplico este tweak desde ESTA seccion (puede
        // estar On por el tab Optimizar clasico, o por politica externa) -- no hay valor original
        // capturado para restaurar, y adivinar uno violaria el principio de "no asumir default".
        // No-op, igual que TCP/PageFile.
        if (!App.TweakState.HasEntry("Telemetry")) return;

        int?[] original = App.TweakState.ReadOriginal<int?[]>("Telemetry") ?? new int?[] { null, null };
        for (int i = 0; i < TelemetryKeys.Length; i++)
        {
            var (path, name) = TelemetryKeys[i];
            using var key = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, path);
            if (key is null) continue;
            if (i < original.Length && original[i] is int v) key.SetValue(name, v, RegistryValueKind.DWord);
            else key.DeleteValue(name, throwOnMissingValue: false);
        }
        App.TweakState.SetAppliedByWinBoost("Telemetry", false);
    });

    private static Task<TweakStatus> ReadTelemetryAsync() => Task.Run(() =>
        TelemetryKeys.All(k => ReadDwordOrNull(k.Path, k.Name) == 0) ? TweakStatus.On : TweakStatus.Off);

    private static int? ReadDwordOrNull(string subKey, string name)
    {
        using var k = Registry.LocalMachine.OpenSubKey(subKey);
        return k?.GetValue(name) is int i ? i : null;
    }

    // ── SvcDiag ────────────────────────────────────────────────────────────────
    private const string SvcDiagName = "DiagTrack";

    private sealed record SvcOriginal(string StartMode, bool WasRunning);

    private static readonly Dictionary<string, int> SvcStartValues = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Boot"] = 0, ["System"] = 1, ["Auto"] = 2, ["AutoDelayed"] = 2, ["Manual"] = 3, ["Disabled"] = 4
    };

    // Mismo dato que BackupService.SaveSvcBackup, guardado en el store por-tweak en vez del
    // session.json de una corrida completa de Optimizar.
    private static SvcOriginal ReadSvcOriginal(string svcName)
    {
        using var svc = new ServiceController(svcName);
        bool wasRunning = svc.Status == ServiceControllerStatus.Running;
        string startMode = svc.StartType switch
        {
            ServiceStartMode.Automatic => "Auto",
            ServiceStartMode.Manual    => "Manual",
            ServiceStartMode.Disabled  => "Disabled",
            _                          => svc.StartType.ToString()
        };
        if (startMode == "Auto")
        {
            using var key = Registry.LocalMachine.OpenSubKey($@"SYSTEM\CurrentControlSet\Services\{svcName}");
            if (key?.GetValue("DelayedAutoStart") is int d && d == 1) startMode = "AutoDelayed";
        }
        return new SvcOriginal(startMode, wasRunning);
    }

    private static Task ApplySvcDiagAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("SvcDiag"))
            App.TweakState.SaveOriginal("SvcDiag", ReadSvcOriginal(SvcDiagName));

        try
        {
            using var svc = new ServiceController(SvcDiagName);
            if (svc.StartType != ServiceStartMode.Disabled)
                try { svc.Stop(); svc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(10)); }
                catch { }
        }
        catch { }
        using (var key = RegistryPrivilegeHelper.OpenWritable(
            RegistryHive.LocalMachine, $@"SYSTEM\CurrentControlSet\Services\{SvcDiagName}"))
            key?.SetValue("Start", 4, RegistryValueKind.DWord);

        App.TweakState.SetAppliedByWinBoost("SvcDiag", true);
    });

    // Mismo mecanismo que BackupService.RestoreServicesFromSession, adaptado a UN servicio leido
    // del store por-tweak en vez de SessionMetadata.Services.
    private static Task RevertSvcDiagAsync() => Task.Run(() =>
    {
        // Sin entrada = WinBoost nunca aplico este tweak desde esta seccion -- no-op (ver
        // comentario equivalente en RevertTelemetryAsync).
        if (!App.TweakState.HasEntry("SvcDiag")) return;

        var original = App.TweakState.ReadOriginal<SvcOriginal>("SvcDiag") ?? new SvcOriginal("Auto", true);
        int startValue = SvcStartValues.TryGetValue(original.StartMode, out var v) ? v : 3;

        using (var key = RegistryPrivilegeHelper.OpenWritable(
            RegistryHive.LocalMachine, $@"SYSTEM\CurrentControlSet\Services\{SvcDiagName}"))
        {
            key?.SetValue("Start", startValue, RegistryValueKind.DWord);
            if (original.StartMode == "AutoDelayed") key?.SetValue("DelayedAutoStart", 1, RegistryValueKind.DWord);
            else key?.DeleteValue("DelayedAutoStart", throwOnMissingValue: false);
        }

        if (original.WasRunning && original.StartMode != "Disabled")
            try { using var svc = new ServiceController(SvcDiagName); svc.Start(); } catch { }

        App.TweakState.SetAppliedByWinBoost("SvcDiag", false);
    });

    private static Task<TweakStatus> ReadSvcDiagAsync() => Task.Run(() =>
        SystemInfoService.CheckSvc(SvcDiagName) ? TweakStatus.On : TweakStatus.Off);

    // ══ Fase B, Tanda 2 (44_fase_b_tanda_2_servicios.txt) ══════════════════════════════════
    // ── Helper compartido de "servicios" (mismo mecanismo de SvcDiag, multiplicado por N) ──
    // SvcDiag (arriba) probo el patron para UN servicio: Stop() + Start=4 via
    // RegistryPrivilegeHelper, original guardado DIRECTO en TweakStateStore (NO
    // App.Backup.SaveSvcBackup -- ese es el guardado ligado a una corrida del tab Optimizar
    // clasico, y reusarlo aca habria reproducido el mismo bug de TCP del piloto, fix 39: nunca
    // persiste nada fuera de esa corrida). Los 4 tweaks de esta tanda tocan 1 a 3 servicios cada
    // uno -- en vez de repetir el cuerpo de SvcDiag 4 veces (y de nuevo en cada tanda futura de
    // esta familia), se factoriza en un helper generico parametrizado por la lista de nombres,
    // mismo criterio que RegEntry en la Tanda 1. SvcDiag no se toca ni se migra a este helper --
    // mismo precedente que Telemetry en la Tanda 1 (los tweaks de tandas anteriores que ya
    // funcionan quedan como estan). ReadSvcOriginal/SvcOriginal/SvcStartValues (arriba, junto a
    // SvcDiag) ya son genericos por servicio -- se reusan tal cual, sin cambios.
    private static Task ApplySvcEntriesAsync(string id, string[] svcNames) => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry(id))
        {
            var original = svcNames.ToDictionary(n => n, ReadSvcOriginal, StringComparer.OrdinalIgnoreCase);
            App.TweakState.SaveOriginal(id, original);
        }
        foreach (string name in svcNames)
        {
            try
            {
                using var svc = new ServiceController(name);
                if (svc.StartType != ServiceStartMode.Disabled)
                    try { svc.Stop(); svc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(10)); }
                    catch { }
            }
            catch { }
            using var key = RegistryPrivilegeHelper.OpenWritable(
                RegistryHive.LocalMachine, $@"SYSTEM\CurrentControlSet\Services\{name}");
            key?.SetValue("Start", 4, RegistryValueKind.DWord);
        }
        App.TweakState.SetAppliedByWinBoost(id, true);
    });

    // Restaura cada servicio a SU PROPIO original -- no asume que todos comparten estado de
    // fabrica (ej. SvcFax: RemoteRegistry suele venir Disabled de fabrica en Win10/11 modernos por
    // endurecimiento de seguridad, Fax no). Caso "ya estaba Disabled" ya cubierto sin caso especial:
    // ReadSvcOriginal captura StartMode="Disabled"/WasRunning=false, SvcStartValues lo mapea de
    // vuelta a 4 (no-op real), y "WasRunning && StartMode != Disabled" da false -- nunca se
    // intenta arrancar un servicio que nunca fue WinBoost quien lo apago.
    private static Task RevertSvcEntriesAsync(string id, string[] svcNames) => Task.Run(() =>
    {
        // Sin entrada = WinBoost nunca aplico este tweak desde esta seccion -- no-op (mismo
        // criterio que el resto de los tweaks del registro).
        if (!App.TweakState.HasEntry(id)) return;

        var original = App.TweakState.ReadOriginal<Dictionary<string, SvcOriginal>>(id);
        if (original is null) return;

        foreach (string name in svcNames)
        {
            if (!original.TryGetValue(name, out var orig)) continue;
            int startValue = SvcStartValues.TryGetValue(orig.StartMode, out var v) ? v : 3;

            using (var key = RegistryPrivilegeHelper.OpenWritable(
                RegistryHive.LocalMachine, $@"SYSTEM\CurrentControlSet\Services\{name}"))
            {
                key?.SetValue("Start", startValue, RegistryValueKind.DWord);
                if (orig.StartMode == "AutoDelayed") key?.SetValue("DelayedAutoStart", 1, RegistryValueKind.DWord);
                else key?.DeleteValue("DelayedAutoStart", throwOnMissingValue: false);
            }

            if (orig.WasRunning && orig.StartMode != "Disabled")
                try { using var svc = new ServiceController(name); svc.Start(); } catch { }
        }
        App.TweakState.SetAppliedByWinBoost(id, false);
    });

    // ── SvcXbox ────────────────────────────────────────────────────────────────
    // Checker existente (CheckSvcXbox, SystemInfoService.cs) es un proxy de health-score: cuenta
    // "mayoria" (>=2 de 3) a proposito, para que el score tolere que UN servicio no se pudo
    // deshabilitar por permisos y aun asi puntue bien. Para el toggle de Tweaks ese criterio seria
    // un placebo parcial (On con 1 de 3 servicios todavia activos) -- mismo argumento que
    // GPUPrio/MouseAccel/GameDVR en la Tanda 1 frente a sus Check* de health-score. Criterio
    // estricto propio (All) sin tocar CheckSvcXbox ni su uso en el audit de Home: son dos
    // consumidores con objetivos distintos (score tolerante vs. toggle honesto).
    private static readonly string[] SvcXboxNames = ["XblAuthManager", "XblGameSave", "XboxNetApiSvc"];

    private static Task<TweakStatus> ReadSvcXboxAsync() => Task.Run(() =>
        SvcXboxNames.All(SystemInfoService.CheckSvc) ? TweakStatus.On : TweakStatus.Off);

    // ── SvcWER ─────────────────────────────────────────────────────────────────
    // Checker existente (CheckSvc("WerSvc")) ya valida exactamente ese servicio, sin proxy ni
    // asimetria -- se reusa tal cual, caso mas directo de la tanda (mismo patron 1:1 que SvcDiag).
    private static readonly string[] SvcWerNames = ["WerSvc"];

    private static Task<TweakStatus> ReadSvcWerAsync() => Task.Run(() =>
        SystemInfoService.CheckSvc("WerSvc") ? TweakStatus.On : TweakStatus.Off);

    // ── SvcMaps ────────────────────────────────────────────────────────────────
    // Sin checker en SystemInfoService (confirmado: no aparece en el switch Check(id)) -- se
    // construye de cero reusando el helper generico CheckSvc(nombre) que ya existe, con criterio
    // AND (ambos deshabilitados), mismo criterio "todos, no al menos uno" que GameMode/Notif en la
    // Tanda 1.
    private static readonly string[] SvcMapsNames = ["MapsBroker", "lfsvc"];

    private static Task<TweakStatus> ReadSvcMapsAsync() => Task.Run(() =>
        SvcMapsNames.All(SystemInfoService.CheckSvc) ? TweakStatus.On : TweakStatus.Off);

    // ── SvcFax ─────────────────────────────────────────────────────────────────
    // Checker existente (CheckSvc("Fax") || CheckSvc("RemoteRegistry")) es un proxy de
    // health-score con criterio OR (alcanza con que UNO este deshabilitado) -- mismo problema que
    // SvcXbox, criterio estricto propio (AND) sin tocar el checker del audit de Home. Nota de
    // fabrica: en instalaciones limpias de Win10/11 modernas es comun que RemoteRegistry ya venga
    // con StartType Disabled por endurecimiento de seguridad -- ese caso lo maneja
    // RevertSvcEntriesAsync sin rama especial (ver comentario del helper).
    private static readonly string[] SvcFaxNames = ["Fax", "RemoteRegistry"];

    private static Task<TweakStatus> ReadSvcFaxAsync() => Task.Run(() =>
        SvcFaxNames.All(SystemInfoService.CheckSvc) ? TweakStatus.On : TweakStatus.Off);

    // ══ Fase B, Tanda 3 (45_fase_b_tanda_3_hpet_faststartup.txt) ═══════════════════════════
    // ── HPET ───────────────────────────────────────────────────────────────────
    // Apply hoy (OptimizationService.HpetTweaks) corre 3 comandos bcdedit en orden fijo. Checker
    // existente (CheckHpet) valida SOLO disabledynamictick=Yes -- ya confirmado en un corte
    // anterior que bcdedit no localiza sus tokens Yes/No (se probaron 4 elementos BCD distintos,
    // todos "Yes" en español); ese hallazgo y CheckHpet no se tocan.
    //
    // Decision (LeerEstadoAsync, documentada en CHANGELOG): en vez del proxy de una sola clave,
    // exige los 3 elementos que Apply realmente toca -- useplatformtick=Yes (el que CheckHpet no
    // valida) Y disabledynamictick=Yes, MAS useplatformclock ausente (lo que Apply realmente
    // produce al borrarlo -- a diferencia de los otros dos, este elemento no es un booleano que se
    // "prende", es una key que se elimina para que Windows decida el reloj por su cuenta). Mismo
    // criterio "todos, no el proxy parcial" que la mayoria de los tweaks de la Tanda 1. Sin riesgo
    // de falso positivo en una maquina virgen que nunca toco HPET: useplatformtick/
    // disabledynamictick ya dan Off por si solos ahi, sea cual sea el estado de useplatformclock.
    //
    // Revertir -- el punto central del tweak: NO se reusa BackupService.RestoreHpetFromSession
    // (borra los 3 elementos SIEMPRE via /deletevalue, sin haber leido nunca el estado real antes
    // de aplicar -- asume que "borrar" equivale a "default seguro". Es el mismo atajo, "asumir un
    // default en vez de leer el valor real", que ya se identifico y se corrigio para valores de
    // registro en GPUPrio, Tanda 1). Tampoco se llama a RestoreHpetFromSession desde aca. En su
    // lugar: antes de aplicar se lee el estado REAL de los 3 elementos parseando "bcdedit /enum"
    // (mismo criterio de tokens no localizados que ya usa CheckHpet) y se guarda en el
    // TweakStateStore si cada uno existia (con que valor exacto, sin asumir que es booleano) o no
    // existia. Al revertir: elemento que no existia -> "bcdedit /deletevalue <elemento>"; elemento
    // que existia -> "bcdedit /set <elemento> <valor>" repitiendo el token tal cual se capturo.
    private static readonly string[] HpetElements = ["useplatformclock", "useplatformtick", "disabledynamictick"];

    private static string[] ReadBcdEnum() => RunProcess("bcdedit", "/enum").Split('\n');

    // Linea tipica de "bcdedit /enum": "<elemento>        <valor>" (padding variable, sin
    // separador fijo) -- estos 3 elementos no tienen nombre amigable en bcdedit, asi que aparecen
    // con su identificador crudo (en ingles, en cualquier locale). null si el elemento no aparece
    // (no seteado en el store BCD actual).
    private static string? ReadBcdElement(string[] enumLines, string element)
    {
        foreach (string raw in enumLines)
        {
            string[] tokens = raw.Trim().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (tokens.Length >= 2 && string.Equals(tokens[0], element, StringComparison.OrdinalIgnoreCase))
                return tokens[1];
        }
        return null;
    }

    private static Task ApplyHpetAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("HPET"))
        {
            var enumLines = ReadBcdEnum();
            var original   = HpetElements.ToDictionary(e => e, e => ReadBcdElement(enumLines, e));
            App.TweakState.SaveOriginal("HPET", original);
        }
        RunProcess("bcdedit", "/deletevalue useplatformclock");
        RunProcess("bcdedit", "/set useplatformtick yes");
        RunProcess("bcdedit", "/set disabledynamictick yes");
        App.TweakState.SetAppliedByWinBoost("HPET", true);
    });

    private static Task RevertHpetAsync() => Task.Run(() =>
    {
        // Sin entrada = WinBoost nunca aplico este tweak desde esta seccion -- no-op (mismo
        // criterio que el resto de los tweaks del registro).
        if (!App.TweakState.HasEntry("HPET")) return;

        var original = App.TweakState.ReadOriginal<Dictionary<string, string?>>("HPET");
        if (original is null) return;

        foreach (string element in HpetElements)
        {
            string? value = original.TryGetValue(element, out var v) ? v : null;
            if (value is null) RunProcess("bcdedit", $"/deletevalue {element}");
            else RunProcess("bcdedit", $"/set {element} {value}");
        }
        App.TweakState.SetAppliedByWinBoost("HPET", false);
    });

    private static Task<TweakStatus> ReadHpetAsync() => Task.Run(() =>
    {
        var enumLines = ReadBcdEnum();
        bool clockGone = ReadBcdElement(enumLines, "useplatformclock") is null;
        bool tickOn    = string.Equals(ReadBcdElement(enumLines, "useplatformtick"),    "Yes", StringComparison.OrdinalIgnoreCase);
        bool dynOff    = string.Equals(ReadBcdElement(enumLines, "disabledynamictick"), "Yes", StringComparison.OrdinalIgnoreCase);
        return (clockGone && tickOn && dynOff) ? TweakStatus.On : TweakStatus.Off;
    });

    // ── FastStartup ────────────────────────────────────────────────────────────
    // Apply hoy (OptimizationService.FastStartupTweaks) mezcla DOS mecanismos: SetReg de
    // HiberbootEnabled=0 (hoy pasa por el generico SetReg/App.Backup.SaveRegBackup del tab
    // clasico, session-scoped -- no se reusa aca, mismo motivo de siempre) MAS
    // "powercfg /hibernate off", que apaga la hibernacion de TODA la maquina, no solo el fast
    // startup (confirmado contra el codigo real: es el comportamiento documentado de ese comando).
    // Es el mismo efecto que ya produce el tab Optimizar clasico hoy -- no se cambia aca; queda
    // anotado que es un efecto secundario del comando en si, no algo que este tweak decida agregar,
    // y no hay evidencia en el codigo de que haya sido una decision de producto evaluada a
    // proposito (vale la pena que alguien lo revise como decision de producto en algun momento,
    // fuera del alcance de esta tanda). No existia NINGUN revert dedicado para este tweak completo
    // en ningun lado del codigo, ni siquiera el viejo de sesion.
    //
    // Captura del estado de hibernacion: se reusa la MISMA lectura que ya usa
    // BackupService.SavePowerPlanBackup (el DWord HibernateEnabled bajo
    // HKLM\SYSTEM\CurrentControlSet\Control\Power, con el mismo default -- "no se pudo leer" =
    // asumir que estaba activada, igual que esa lectura ya asume), NO el metodo completo (que
    // ademas guarda el GUID del plan de energia activo, algo que este tweak no toca). Se guarda
    // junto con el original de HiberbootEnabled en un solo record por-tweak.
    //
    // Decision (LeerEstadoAsync, documentada en CHANGELOG): no se queda con el proxy de una sola
    // clave que usa CheckFastStartup (solo HiberbootEnabled) -- verifica ADEMAS que la hibernacion
    // este realmente apagada. Se descarto "powercfg /a" (la forma obvia de preguntarle a Windows si
    // la hibernacion esta disponible) por ser texto libre LOCALIZADO -- exactamente el tipo de
    // parseo fragil que docs/PENDIENTES.md ya identifica como riesgo para el mercado LATAM. En vez
    // de eso, se reusa la MISMA lectura de registro (HibernateEnabled) que la captura: no
    // localizada, ya validada por el propio codigo del tab clasico.
    //
    // RequiereReinicio = false (a diferencia de HPET/PageFile): HiberbootEnabled lo relee la
    // rutina de apagado en el momento de apagar, no algo que el kernel cachee al arrancar: el
    // cambio de configuracion es inmediato, el usuario recien lo "nota" en el proximo apagado
    // completo (que ademas no es lo mismo que un reinicio -- Reiniciar en Windows siempre hace
    // arranque en frio, Fast Startup solo afecta a Apagar). "powercfg /hibernate off" tambien es
    // inmediato: desactiva la hibernacion y borra hiberfil.sys al toque, sin esperar a un reinicio.
    // Ninguna de las dos mitades del tweak encaja en la misma categoria que HPET (bcdedit, que el
    // firmware/kernel solo relee en el proximo arranque) o MouseDataQueueSize (parametro de driver
    // de kernel que solo se relee al cargar).
    private sealed record FastStartupOriginal(int? HiberbootEnabled, bool HibernateWasEnabled);

    private const string FastStartupPowerKey = @"SYSTEM\CurrentControlSet\Control\Session Manager\Power";
    private const string HibernatePowerKey   = @"SYSTEM\CurrentControlSet\Control\Power";

    private static Task ApplyFastStartupAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("FastStartup"))
        {
            int? hiberboot = ReadDwordOrNull(FastStartupPowerKey, "HiberbootEnabled");
            int? hibernate = ReadDwordOrNull(HibernatePowerKey, "HibernateEnabled");
            bool hibernateWasOn = hibernate is int hibVal ? hibVal == 1 : true;
            App.TweakState.SaveOriginal("FastStartup", new FastStartupOriginal(hiberboot, hibernateWasOn));
        }
        using (var key = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, FastStartupPowerKey))
            key?.SetValue("HiberbootEnabled", 0, RegistryValueKind.DWord);
        RunProcess("powercfg", "/hibernate off");
        App.TweakState.SetAppliedByWinBoost("FastStartup", true);
    });

    private static Task RevertFastStartupAsync() => Task.Run(() =>
    {
        // Sin entrada = WinBoost nunca aplico este tweak desde esta seccion -- no-op (mismo
        // criterio que el resto de los tweaks del registro).
        if (!App.TweakState.HasEntry("FastStartup")) return;

        var original = App.TweakState.ReadOriginal<FastStartupOriginal>("FastStartup");
        if (original is null) return;

        using (var key = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, FastStartupPowerKey))
        {
            if (original.HiberbootEnabled is int v) key?.SetValue("HiberbootEnabled", v, RegistryValueKind.DWord);
            else key?.DeleteValue("HiberbootEnabled", throwOnMissingValue: false);
        }
        // Solo reactivar si WinBoost fue quien la apago -- si ya estaba apagada de antes, no
        // tocarla (mismo criterio "restaurar exactamente lo que habia" que el resto de la tanda).
        if (original.HibernateWasEnabled) RunProcess("powercfg", "/hibernate on");
        App.TweakState.SetAppliedByWinBoost("FastStartup", false);
    });

    private static Task<TweakStatus> ReadFastStartupAsync() => Task.Run(() =>
    {
        bool hiberbootOff = ReadDwordOrNull(FastStartupPowerKey, "HiberbootEnabled") == 0;
        bool hibernateOff = ReadDwordOrNull(HibernatePowerKey, "HibernateEnabled") == 0;
        return (hiberbootOff && hibernateOff) ? TweakStatus.On : TweakStatus.Off;
    });

    // ══ Fase B, Tanda 4 (46_fase_b_tanda_4_svcsysmain_svcwsearch.txt) ══════════════════════
    // ── SvcSysMain / SvcWSearch ───────────────────────────────────────────────
    // Mecanismo de servicio identico a SvcDiag/SvcWER -- 1 servicio, mismo
    // ApplySvcEntriesAsync/RevertSvcEntriesAsync de la Tanda 2, sin novedad ahi. La unica novedad
    // real: Apply hoy (OptimizationService.ServiceTweaks) omite el tweak entero si la maquina no
    // tiene SSD (SysMain/Superfetch existe justamente PARA ayudar en HDD; WSearch sin SSD tiene
    // sentido dejarlo, indexar acelera busquedas en disco lento) -- primer caso real que ejercita
    // TweakState.NoAplicable: el enum existe desde el piloto (prompt 38) pero ningun tweak anterior
    // lo necesitaba (Nagle, Tanda 1, tiene su propio caso NoAplicable pero solo dispara sin NINGUN
    // adaptador con IP DHCP, algo que nunca se vio en la practica).
    //
    // Deteccion de SSD: SystemInfoService.HasSsd() -- MISMA deteccion que ya usa GatherSystemInfo
    // para el SystemSnapshot (MSFT_PhysicalDisk, MediaType==4), extraida a su propio metodo
    // reusable (ver comentario en SystemInfoService.cs). NO se usa
    // OptimizationService.GetSsdDriveLetters(): esa responde una pregunta distinta (que letras de
    // unidad tocar con TRIM), no "hay un SSD si o no". Se consulta fresco en Aplicar/Revertir/Leer
    // por separado, nunca cacheada -- si el usuario cambia de disco despues de instalar, la proxima
    // apertura de la seccion Tweaks lo refleja solo, sin reiniciar la app.
    //
    // Guard "sin SSD, no-op" DENTRO de AplicarAsync/RevertirAsync (no solo en la UI, que ya
    // deshabilita el toggle cuando LeerEstadoAsync devuelve NoAplicable -- pero la UI es un solo
    // punto de control, no el unico camino posible para invocar estos metodos, mismo criterio
    // general del proyecto de no confiar en una sola capa para algo que importa).
    private static async Task ApplySvcIfSsdAsync(string id, string svcName)
    {
        if (!await Task.Run(SystemInfoService.HasSsd)) return;
        await ApplySvcEntriesAsync(id, [svcName]);
    }

    private static async Task RevertSvcIfSsdAsync(string id, string svcName)
    {
        if (!await Task.Run(SystemInfoService.HasSsd)) return;
        await RevertSvcEntriesAsync(id, [svcName]);
    }

    private static async Task<TweakStatus> ReadSvcIfSsdAsync(string svcName)
    {
        if (!await Task.Run(SystemInfoService.HasSsd))
            return TweakStatus.NotApplicable("Requiere un disco SSD.");
        return await Task.Run(() => SystemInfoService.CheckSvc(svcName) ? TweakStatus.On : TweakStatus.Off);
    }

    // ── Tasks ──────────────────────────────────────────────────────────────────
    // No existia revert individual (BackupService no cubre tareas programadas) -- se construye
    // aca. Apply/Revert usan la misma CLI schtasks que ya usa OptimizationService; LeerEstadoAsync
    // usa el mecanismo COM de SystemInfoService.GetTasksEnabledState, extendido a las 5 tareas
    // reales (CheckTasks del health score solo cubre 3).
    private static readonly string[] TaskPaths =
    [
        @"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        @"\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        @"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        @"\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        @"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    ];

    private static Task ApplyTasksAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("Tasks"))
        {
            var states = SystemInfoService.GetTasksEnabledState(TaskPaths);
            // Una tarea que no se pudo leer se guarda como "estaba enabled" (true): asi el
            // revert la reactiva por las dudas, en vez de dejarla deshabilitada para siempre
            // por un fallo de lectura que no tiene que ver con su valor real.
            var original = TaskPaths.ToDictionary(t => t, t => !states.TryGetValue(t, out var e) || e);
            App.TweakState.SaveOriginal("Tasks", original);
        }
        foreach (var t in TaskPaths) RunProcess("schtasks", $"/change /tn \"{t}\" /disable");
        App.TweakState.SetAppliedByWinBoost("Tasks", true);
    });

    private static Task RevertTasksAsync() => Task.Run(() =>
    {
        // Sin entrada = WinBoost nunca aplico este tweak desde esta seccion -- no-op (ver
        // comentario equivalente en RevertTelemetryAsync).
        if (!App.TweakState.HasEntry("Tasks")) return;

        var original = App.TweakState.ReadOriginal<Dictionary<string, bool>>("Tasks")
                       ?? TaskPaths.ToDictionary(t => t, _ => true);
        foreach (var t in TaskPaths)
            if (original.TryGetValue(t, out var wasEnabled) && wasEnabled)
                RunProcess("schtasks", $"/change /tn \"{t}\" /enable");
        App.TweakState.SetAppliedByWinBoost("Tasks", false);
    });

    private static Task<TweakStatus> ReadTasksAsync() => Task.Run(() =>
    {
        var states = SystemInfoService.GetTasksEnabledState(TaskPaths);
        // Honesto: On solo si las 5 (no 3) estan confirmadas deshabilitadas. Una tarea que no se
        // pudo verificar no cuenta como deshabilitada -- el toggle no puede afirmar algo que no
        // pudo confirmar.
        bool allDisabled = TaskPaths.All(t => states.TryGetValue(t, out var en) && !en);
        return allDisabled ? TweakStatus.On : TweakStatus.Off;
    });

    // ── TCP ────────────────────────────────────────────────────────────────────
    // Guarda el texto de "netsh int tcp show global" en el store por-tweak en vez del
    // netsh_backup.txt de sesion de BackupService. El parseo al revertir (MatchNetshLine, mas
    // abajo) es propio, NO el de BackupService.RestoreNetshFromSession -- ese usa regex solo en
    // ingles y esta roto en Windows localizado (fix 39, ver comentario en RevertTcpAsync); no se
    // toco BackupService.cs, pero tampoco se reuso su parseo tal cual como pedia originalmente
    // el prompt 38, porque hacerlo habria heredado el mismo bug.
    private static Task ApplyTcpAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry("TCP"))
            App.TweakState.SaveOriginal("TCP", RunProcess("netsh", "int tcp show global"));

        RunProcess("netsh", "int tcp set global autotuninglevel=normal");
        RunProcess("netsh", "int tcp set global chimney=disabled");
        RunProcess("netsh", "int tcp set global rss=enabled");
        RunProcess("netsh", "int tcp set global fastopen=enabled");
        App.TweakState.SetAppliedByWinBoost("TCP", true);
    });

    private static Task RevertTcpAsync() => Task.Run(() =>
    {
        string? content = App.TweakState.ReadOriginal<string>("TCP");
        if (string.IsNullOrEmpty(content)) return;

        // Fix 39: las 4 etiquetas de BackupService.RestoreNetshFromSession son SOLO en ingles.
        // Confirmado en la maquina real (es-ES): "netsh int tcp show global" localiza 3 de las 4
        // etiquetas (autotuning, RSS, fastopen -- "Chimney Offload State" ya no aparece en
        // Windows moderno, ni en ingles ni en español, deprecado). El regex en ingles nunca
        // matcheaba nada -> MatchNetsh caia SIEMPRE al fallback hardcodeado, que para RSS es
        // "enabled": el revert re-aplicaba el mismo valor que Apply, nunca el original guardado
        // (ej. "disabled" forzado a mano quedaba ignorado). Fix: matchea por linea con anclas SIN
        // acentos (mismo token "escalado" que ya usa y valido CheckTcpTuning, corte 33) en vez de
        // un regex de texto completo -- no depende de la codificacion con la que RunProcess
        // capturo el texto (los acentos del original guardado vienen corrompidos por el codepage
        // de consola, ej. "recepci¢n"; los anclajes de abajo evitan tocar caracteres acentuados a
        // proposito, mismo criterio que "Versi.n" en ParsePnpUtil).
        string tuning  = MatchNetshLine(content, l =>
            l.Contains("Auto-Tuning Level", StringComparison.OrdinalIgnoreCase) ||
            l.Contains("ajuste autom",      StringComparison.OrdinalIgnoreCase), "normal");
        string chimney = MatchNetshLine(content, l =>
            l.Contains("Chimney Offload State", StringComparison.OrdinalIgnoreCase), "disabled");
        string rss     = MatchNetshLine(content, l =>
            l.Contains("Receive-Side Scaling", StringComparison.OrdinalIgnoreCase) ||
            l.Contains("escalado",              StringComparison.OrdinalIgnoreCase), "enabled");
        string fo      = MatchNetshLine(content, l =>
            l.Contains("Fast Open", StringComparison.OrdinalIgnoreCase) &&
            !l.Contains("Reserva",  StringComparison.OrdinalIgnoreCase) &&
            !l.Contains("Fallback", StringComparison.OrdinalIgnoreCase), "enabled");

        RunProcess("netsh", $"int tcp set global autotuninglevel={tuning}");
        RunProcess("netsh", $"int tcp set global chimney={chimney}");
        RunProcess("netsh", $"int tcp set global rss={rss}");
        RunProcess("netsh", $"int tcp set global fastopen={fo}");
        App.TweakState.SetAppliedByWinBoost("TCP", false);
    });

    // Decision (documentada en CHANGELOG): se reusa CheckTcpTuning (proxy RSS) tal cual, no se
    // verifican los 4 parametros. 1) Es el mismo lector que ya alimenta el health score de Red
    // (TCPTuning) -- un criterio distinto en el toggle podria mostrar On/Off en desacuerdo con
    // el score de la misma categoria. 2) Ya esta validado bilingue contra una maquina real
    // (corte 33). 3) En la practica los 4 valores se tocan siempre juntos (mismo Apply, mismo
    // Revert por texto); solo divergirian si el usuario edita netsh a mano por fuera de WinBoost.
    private static Task<TweakStatus> ReadTcpAsync() => Task.Run(() =>
        SystemInfoService.CheckTcpTuning() ? TweakStatus.On : TweakStatus.Off);

    private static string MatchNetshLine(string content, Func<string, bool> isLabelLine, string fallback)
    {
        foreach (string rawLine in content.Split('\n'))
        {
            string line = rawLine.Trim();
            if (!isLabelLine(line)) continue;
            var m = Regex.Match(line, @":\s*(\S+)");
            if (m.Success) return m.Groups[1].Value.ToLowerInvariant();
        }
        return fallback;
    }

    // ── PageFile ───────────────────────────────────────────────────────────────
    // Apply reusa OptimizationService.PageFileTweaks tal cual (WMI + rollback a automatico si
    // falla, ya probado -- no se reescribe). Captura/restore del valor original reusan las MISMAS
    // consultas WMI que BackupService.SavePageFileBackup/RestorePageFileFromSession, guardando en
    // el store por-tweak en vez del pagefile_backup.json de una sesion completa.
    private static async Task ApplyPageFileAsync()
    {
        if (!App.TweakState.HasEntry("PageFile"))
        {
            var backup = await Task.Run(CapturePageFileState);
            App.TweakState.SaveOriginal("PageFile", backup);
        }

        var sysInfo     = await App.SystemInfo.GetSystemInfoAsync();
        string sysDrive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:") + @"\";
        await Task.Run(() =>
        {
            new OptimizationService().PageFileTweaks(sysInfo.TotalRamGb, sysDrive, altDrive: null, moveToAlt: false);
            App.TweakState.SetAppliedByWinBoost("PageFile", true);
        });
    }

    private static PageFileBackup CapturePageFileState()
    {
        bool autoManaged = false;
        using (var csSearcher = new ManagementObjectSearcher("SELECT AutomaticManagedPagefile FROM Win32_ComputerSystem"))
        using (var csCol = csSearcher.Get())
            foreach (ManagementObject mo in csCol) { autoManaged = mo["AutomaticManagedPagefile"] is bool b && b; mo.Dispose(); break; }

        var pageFiles = new List<PageFileEntry>();
        using (var pfSearcher = new ManagementObjectSearcher("SELECT Name, InitialSize, MaximumSize FROM Win32_PageFileSetting"))
        using (var pfCol = pfSearcher.Get())
            foreach (ManagementObject mo in pfCol)
            {
                pageFiles.Add(new PageFileEntry
                {
                    Name        = mo["Name"]?.ToString() ?? "",
                    InitialSize = Convert.ToInt32(mo["InitialSize"]),
                    MaximumSize = Convert.ToInt32(mo["MaximumSize"])
                });
                mo.Dispose();
            }
        return new PageFileBackup { AutomaticManaged = autoManaged, PageFiles = pageFiles };
    }

    private static async Task RevertPageFileAsync()
    {
        var backup = App.TweakState.ReadOriginal<PageFileBackup>("PageFile");
        if (backup is null) return;

        await Task.Run(() =>
        {
            ManagementObject? cs = null;
            try
            {
                using var csSearcher = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem");
                using var csCol = csSearcher.Get();
                foreach (ManagementObject mo in csCol) { cs = mo; break; }
                if (cs is null) return;

                if (backup.AutomaticManaged)
                {
                    cs["AutomaticManagedPagefile"] = true;
                    cs.Put();
                }
                else
                {
                    if (cs["AutomaticManagedPagefile"] is bool auto && auto)
                    {
                        cs["AutomaticManagedPagefile"] = false;
                        cs.Put();
                    }
                    using var delSearcher = new ManagementObjectSearcher("SELECT * FROM Win32_PageFileSetting");
                    using var delCol = delSearcher.Get();
                    foreach (ManagementObject mo in delCol) { try { mo.Delete(); } catch { } mo.Dispose(); }

                    using var cls = new ManagementClass("Win32_PageFileSetting");
                    foreach (var pf in backup.PageFiles)
                    {
                        using var inst = cls.CreateInstance();
                        inst["Name"]        = pf.Name;
                        inst["InitialSize"] = (uint)pf.InitialSize;
                        inst["MaximumSize"] = (uint)pf.MaximumSize;
                        inst.Put();
                    }
                }
                App.Logger?.Log("PageFile: configuracion original restaurada (efectivo tras reinicio)", "info");
            }
            catch (Exception ex) { App.Logger?.Log($"Error restaurando PageFile: {ex.Message}", "err"); }
            finally { cs?.Dispose(); }
        });

        App.TweakState.SetAppliedByWinBoost("PageFile", false);
    }

    // No existe Check* reusable en SystemInfoService para PageFile (confirmado) -- criterio
    // simple del prompt: On si la gestion automatica esta apagada Y existe al menos un
    // Win32_PageFileSetting de tamano fijo.
    private static Task<TweakStatus> ReadPageFileAsync() => Task.Run(() =>
    {
        using var csSearcher = new ManagementObjectSearcher("SELECT AutomaticManagedPagefile FROM Win32_ComputerSystem");
        using var csCol      = csSearcher.Get();
        using var cs         = csCol.OfType<ManagementObject>().FirstOrDefault();
        if (cs is null) return TweakStatus.Off;
        bool autoManaged = cs["AutomaticManagedPagefile"] is bool b && b;

        using var pfSearcher = new ManagementObjectSearcher("SELECT Name FROM Win32_PageFileSetting");
        using var pfCol      = pfSearcher.Get();
        return (!autoManaged && pfCol.Count > 0) ? TweakStatus.On : TweakStatus.Off;
    });

    // ── Helpers compartidos ────────────────────────────────────────────────────
    private static string RunProcess(string exe, string args)
    {
        try
        {
            using var proc = new Process
            {
                StartInfo = new ProcessStartInfo(exe, args)
                {
                    UseShellExecute        = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow         = true
                }
            };
            proc.Start();
            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit(30_000);
            return output;
        }
        catch { return ""; }
    }
}
