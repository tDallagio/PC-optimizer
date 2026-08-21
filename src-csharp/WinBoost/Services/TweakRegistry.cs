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
        ];
    }

    public TweakDefinition? Find(string id) => All.FirstOrDefault(t => t.Id == id);

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
