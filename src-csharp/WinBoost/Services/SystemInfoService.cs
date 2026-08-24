using System.Diagnostics;
using System.Management;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.ServiceProcess;
using Microsoft.Win32;

namespace WinBoost.Services;

public sealed record SystemSnapshot(
    string CpuName,
    string GpuName,
    int    TotalRamGb,
    bool   IsLaptop,
    bool   HasSsd,
    string OsCaption,
    int    BuildNumber,
    bool   IsWin11);

public sealed record AuditItemResult(string Id, string Label, string Category, int Weight, bool Ok);

public sealed record AuditResult(
    int    Score,
    IReadOnlyList<AuditItemResult>      Items,
    IReadOnlyDictionary<string, string> ByCategory,
    int    OkCount,
    int    FailCount);

public sealed class SystemInfoService
{
    // Mirror of $script:auditItems in PS1 (Id, Label, Category, Weight)
    private static readonly (string Id, string Label, string Cat, int Wt)[] AuditDefs =
    [
        ("HPET",        "HPET deshabilitado",                    "Rendimiento", 5),
        ("GPUPrio",     "GPU Priority (DXGI)",                   "Rendimiento", 5),
        ("PowerThrot",  "Power Throttling desactivado",          "Rendimiento", 5),
        ("MouseAccel",  "Aceleracion de mouse OFF",              "Rendimiento", 3),
        ("FastStartup", "Fast Startup deshabilitado",            "Rendimiento", 4),
        ("Visual",      "Efectos visuales minimizados",          "Rendimiento", 4),
        ("Telemetry",   "Telemetria deshabilitada",              "Privacidad",  8),
        ("GameDVR",     "Game DVR Xbox OFF",                     "Privacidad",  5),
        ("Cortana",     "Cortana deshabilitada",                 "Privacidad",  5),
        ("Tasks",       "Tareas de telemetria deshabilitadas",   "Privacidad",  8),
        ("DNS",         "DNS optimizado (no ISP)",               "Red",         8),
        ("Nagle",       "Algoritmo de Nagle OFF",                "Red",         5),
        ("TCPTuning",   "TCP/IP optimizado (RSS habilitado)",    "Red",         5),
        ("SvcDiag",     "DiagTrack deshabilitado",               "Servicios",   7),
        ("SvcXbox",     "Servicios Xbox deshabilitados",         "Servicios",   5),
        ("SvcFax",      "Fax y RemoteRegistry deshabilitados",   "Servicios",   5),
        ("SvcWER",      "Windows Error Reporting deshabilitado", "Servicios",   5),
    ];

    // ── System info ───────────────────────────────────────────────────────────

    public Task<SystemSnapshot> GetSystemInfoAsync() => Task.Run(GatherSystemInfo);

    private static SystemSnapshot GatherSystemInfo()
    {
        string cpu = "", gpu = "", os = "";
        int    ram = 0, build = 0;
        bool   laptop = false, ssd = false;

        try
        {
            using var q = new ManagementObjectSearcher("SELECT Name FROM Win32_Processor");
            foreach (ManagementObject o in q.Get())
            { cpu = o["Name"]?.ToString()?.Trim() ?? ""; break; }
        }
        catch { }

        try
        {
            using var q = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController");
            foreach (ManagementObject o in q.Get())
            { gpu = o["Name"]?.ToString()?.Trim() ?? ""; break; }
        }
        catch { }

        try
        {
            using var q = new ManagementObjectSearcher("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem");
            foreach (ManagementObject o in q.Get())
            {
                ram = (int)Math.Round(Convert.ToDouble(o["TotalPhysicalMemory"]) / 1_073_741_824.0);
                break;
            }
        }
        catch { }

        try
        {
            using var q = new ManagementObjectSearcher("SELECT Caption,BuildNumber FROM Win32_OperatingSystem");
            foreach (ManagementObject o in q.Get())
            {
                os    = o["Caption"]?.ToString() ?? "";
                build = Convert.ToInt32(o["BuildNumber"]);
                break;
            }
        }
        catch { }

        try
        {
            using var q = new ManagementObjectSearcher("SELECT ChassisTypes FROM Win32_SystemEnclosure");
            foreach (ManagementObject o in q.Get())
            {
                if (o["ChassisTypes"] is Array arr)
                {
                    int[] lt = [8, 9, 10, 14];
                    foreach (var v in arr) if (lt.Contains(Convert.ToInt32(v))) { laptop = true; break; }
                }
                break;
            }
        }
        catch { }

        try
        {
            var scope   = new ManagementScope(@"\\.\root\microsoft\windows\storage");
            var query   = new ObjectQuery("SELECT MediaType FROM MSFT_PhysicalDisk");
            using var q = new ManagementObjectSearcher(scope, query);
            foreach (ManagementObject o in q.Get())
                if (Convert.ToInt32(o["MediaType"]) == 4) { ssd = true; break; }
        }
        catch { }

        return new SystemSnapshot(cpu, gpu, ram, laptop, ssd, os, build, build >= 22000);
    }

    // ── Audit ─────────────────────────────────────────────────────────────────

    public Task<AuditResult> RunAuditAsync() => Task.Run(RunAudit);

    private static AuditResult RunAudit()
    {
        int maxPts  = AuditDefs.Sum(d => d.Wt);
        int earned  = 0;
        var results = new List<AuditItemResult>(AuditDefs.Length);

        foreach (var (id, label, cat, wt) in AuditDefs)
        {
            bool ok = false;
            try { ok = Check(id); } catch { }
            earned += ok ? wt : 0;
            results.Add(new AuditItemResult(id, label, cat, wt, ok));
        }

        int score = maxPts > 0 ? (int)Math.Round(earned * 100.0 / maxPts) : 0;
        var byCategory = results
            .GroupBy(r => r.Category)
            .ToDictionary(g => g.Key, g => $"{g.Count(r => r.Ok)}/{g.Count()}");

        return new AuditResult(score, results, byCategory,
            results.Count(r => r.Ok), results.Count(r => !r.Ok));
    }

    private static bool Check(string id) => id switch
    {
        "HPET"        => CheckHpet(),
        "GPUPrio"     => CheckGpuPrio(),
        "PowerThrot"  => CheckPowerThrot(),
        "MouseAccel"  => CheckMouseAccel(),
        "FastStartup" => CheckFastStartup(),
        "Visual"      => CheckVisual(),
        "Telemetry"   => CheckTelemetry(),
        "GameDVR"     => CheckGameDvr(),
        "Cortana"     => CheckCortana(),
        "Tasks"       => CheckTasks(),
        "DNS"         => CheckDns(),
        "Nagle"       => CheckNagle(),
        "TCPTuning"   => CheckTcpTuning(),
        "SvcDiag"     => CheckSvc("DiagTrack"),
        "SvcXbox"     => CheckSvcXbox(),
        "SvcFax"      => CheckSvc("Fax") || CheckSvc("RemoteRegistry"),
        "SvcWER"      => CheckSvc("WerSvc"),
        _             => false,
    };

    // ── Individual checks (mirror of PS1 scriptblocks) ───────────────────────

    private static bool CheckHpet()
    {
        foreach (string line in RunProcess("bcdedit", "/enum").Split('\n'))
            if (line.Contains("disabledynamictick", StringComparison.OrdinalIgnoreCase)
             && line.Contains("Yes", StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    private static bool CheckGpuPrio()
    {
        using var k = Registry.LocalMachine.OpenSubKey(
            @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games");
        return k?.GetValue("GPU Priority") is int i && i >= 8;
    }

    private static bool CheckPowerThrot()
    {
        using var k = Registry.LocalMachine.OpenSubKey(
            @"SYSTEM\CurrentControlSet\Control\Power\PowerThrottling");
        return k?.GetValue("PowerThrottlingOff") is int i && i == 1;
    }

    private static bool CheckMouseAccel()
    {
        using var k = Registry.CurrentUser.OpenSubKey(@"Control Panel\Mouse");
        return k?.GetValue("MouseSpeed")?.ToString() == "0";
    }

    private static bool CheckFastStartup()
    {
        using var k = Registry.LocalMachine.OpenSubKey(
            @"SYSTEM\CurrentControlSet\Control\Session Manager\Power");
        return k?.GetValue("HiberbootEnabled") is int i && i == 0;
    }

    private static bool CheckVisual()
    {
        using var k = Registry.CurrentUser.OpenSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects");
        return k?.GetValue("VisualFXSetting") is int i && i == 2;
    }

    private static bool CheckTelemetry()
    {
        using var k = Registry.LocalMachine.OpenSubKey(
            @"SOFTWARE\Policies\Microsoft\Windows\DataCollection");
        return k?.GetValue("AllowTelemetry") is int i && i == 0;
    }

    private static bool CheckGameDvr()
    {
        using var k = Registry.CurrentUser.OpenSubKey(@"System\GameConfigStore");
        return k?.GetValue("GameDVR_Enabled") is int i && i == 0;
    }

    private static bool CheckCortana()
    {
        using var k = Registry.LocalMachine.OpenSubKey(
            @"SOFTWARE\Policies\Microsoft\Windows\Windows Search");
        return k?.GetValue("AllowCortana") is int i && i == 0;
    }

    // Fix 32: lee el estado Enabled (bool, INDEPENDIENTE DEL IDIOMA) via la API COM del Task
    // Scheduler (Schedule.Service), en vez de parsear la salida LOCALIZADA de `schtasks`. El
    // codigo viejo hacia .Contains("Disabled"), que en Windows en español (estado "Deshabilitado")
    // nunca matcheaba -> Tasks daba falso y Privacidad quedaba en 3/4 aunque los tweaks estuvieran
    // aplicados. Mismo criterio que el fix de la politica termica: leer el estado como dato, no
    // como texto. Late-bind por reflection (sin dependencia NuGet ni DLR) para robustez en el
    // publish single-file.
    private static bool CheckTasks()
    {
        string[] tasks =
        [
            @"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            @"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            @"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        ];

        object? svc = null;
        try
        {
            var svcType = Type.GetTypeFromProgID("Schedule.Service");
            if (svcType is null) return false;
            svc = Activator.CreateInstance(svcType);
            if (svc is null) return false;
            ComInvoke(svc, "Connect"); // conecta al Task Scheduler local

            int disabled = 0;
            foreach (var full in tasks)
            {
                try
                {
                    int    slash      = full.LastIndexOf('\\');
                    string folderPath = slash > 0 ? full[..slash] : "\\";
                    string name       = full[(slash + 1)..];
                    object folder = ComInvoke(svc, "GetFolder", folderPath)!;
                    object task   = ComInvoke(folder, "GetTask", name)!;
                    // IRegisteredTask.Enabled es un bool -> sin idioma.
                    if (ComInvoke(task, "Enabled") is bool en && !en) disabled++;
                }
                catch { /* tarea inexistente / sin permiso: no cuenta como deshabilitada */ }
            }
            return disabled >= 2;
        }
        catch { return false; }
        finally
        {
            if (svc is not null && System.Runtime.InteropServices.Marshal.IsComObject(svc))
                System.Runtime.InteropServices.Marshal.FinalReleaseComObject(svc);
        }
    }

    // Late-bind sobre un objeto COM (IDispatch): invoca metodo o lee propiedad por nombre. El binder
    // COM tolera args opcionales omitidos (ej. Connect() sin parametros).
    // internal (era private): reusado por GetTasksEnabledState (mismo mecanismo, no se duplica).
    internal static object? ComInvoke(object target, string member, params object[] args)
        => target.GetType().InvokeMember(member,
               System.Reflection.BindingFlags.InvokeMethod | System.Reflection.BindingFlags.GetProperty,
               binder: null, target: target, args: args);

    // Piloto Fase A (TweakRegistry, tweak "Tasks"): variante de CheckTasks que devuelve el
    // estado Enabled de CADA tarea (no solo un conteo agregado sobre 3 de las 5), reusando el
    // MISMO mecanismo COM Schedule.Service (una sola conexion para todas). Una tarea que no se
    // pudo leer (inexistente/sin permiso) se omite del resultado -- no se asume un valor, para
    // que quien la use decida el fallback mas seguro segun el contexto (aplicar vs leer estado).
    internal static Dictionary<string, bool> GetTasksEnabledState(IEnumerable<string> fullPaths)
    {
        var result = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        object? svc = null;
        try
        {
            var svcType = Type.GetTypeFromProgID("Schedule.Service");
            if (svcType is null) return result;
            svc = Activator.CreateInstance(svcType);
            if (svc is null) return result;
            ComInvoke(svc, "Connect");

            foreach (var full in fullPaths)
            {
                try
                {
                    int    slash      = full.LastIndexOf('\\');
                    string folderPath = slash > 0 ? full[..slash] : "\\";
                    string name       = full[(slash + 1)..];
                    object folder = ComInvoke(svc, "GetFolder", folderPath)!;
                    object task   = ComInvoke(folder, "GetTask", name)!;
                    if (ComInvoke(task, "Enabled") is bool en) result[full] = en;
                }
                catch { /* tarea inexistente / sin permiso: se omite, no se asume valor */ }
            }
        }
        catch { }
        finally
        {
            if (svc is not null && System.Runtime.InteropServices.Marshal.IsComObject(svc))
                System.Runtime.InteropServices.Marshal.FinalReleaseComObject(svc);
        }
        return result;
    }

    private static bool CheckDns()
    {
        string[] known = ["1.1.1.1","1.0.0.1","8.8.8.8","8.8.4.4",
                          "9.9.9.9","149.112.112.112","94.140.14.14","94.140.15.15"];
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            foreach (var dns in nic.GetIPProperties().DnsAddresses)
                if (dns.AddressFamily == AddressFamily.InterNetwork && known.Contains(dns.ToString()))
                    return true;
            break;
        }
        return false;
    }

    private static bool CheckNagle()
    {
        using var k = Registry.LocalMachine.OpenSubKey(
            @"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces");
        if (k == null) return false;
        foreach (string sub in k.GetSubKeyNames())
        {
            using var iface = k.OpenSubKey(sub);
            if (iface?.GetValue("TcpAckFrequency") is int i && i == 1) return true;
        }
        return false;
    }

    // internal (era private): reusado por TweakRegistry (piloto Fase A, tweak "TCP") como
    // LeerEstadoAsync -- decision documentada en CHANGELOG (proxy RSS, no los 4 parametros).
    internal static bool CheckTcpTuning()
    {
        // La salida de `netsh int tcp show global` se localiza segun el idioma de
        // Windows: en es-ES la linea de RSS es "Estado de escalado de lado de
        // recepcion: enabled", no "Receive-Side Scaling State: enabled". El check
        // original solo matcheaba el rotulo en ingles, por lo que en Windows en
        // espanol SIEMPRE daba negativo (Red se quedaba en 2/3) aunque RSS estuviera
        // activo. Se matchea bilingue: el token "escalado" identifica la linea de RSS
        // en espanol (la de RSC usa "fusion de segmento", sin "escalado"); el valor
        // "enabled"/"disabled" que emite netsh no se localiza.
        foreach (string line in RunProcess("netsh", "int tcp show global").Split('\n'))
        {
            bool isRssLine = line.Contains("Receive-Side Scaling", StringComparison.OrdinalIgnoreCase)
                          || line.Contains("escalado", StringComparison.OrdinalIgnoreCase);
            if (isRssLine && line.Contains("enabled", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    // internal (era private): reusado por TweakRegistry (piloto Fase A, tweak "SvcDiag") --
    // mismo criterio simple que ya usa el health score (StartType Disabled = Off, resto = On).
    internal static bool CheckSvc(string name)
    {
        try { using var s = new ServiceController(name); return s.StartType == ServiceStartMode.Disabled; }
        catch { return false; }
    }

    // internal: reusado por TweakRegistry (Fase B, Tanda 4, SvcSysMain/SvcWSearch) para la
    // pregunta "esta maquina tiene al menos un SSD" -- MISMA deteccion que ya usa GatherSystemInfo
    // para el SystemSnapshot (MSFT_PhysicalDisk, MediaType==4), extraida a su propio metodo en vez
    // de duplicar el WMI a mano en TweakRegistry.cs. NO es OptimizationService.GetSsdDriveLetters()
    // (esa responde una pregunta distinta -- que letras de unidad tocar con TRIM -- y hace un WMI
    // propio con otro filtro). No cachea nada: se re-consulta en cada llamada a proposito, para que
    // SvcSysMain/SvcWSearch reflejen un cambio de disco sin reiniciar la app.
    internal static bool HasSsd()
    {
        try
        {
            var scope   = new ManagementScope(@"\\.\root\microsoft\windows\storage");
            var query   = new ObjectQuery("SELECT MediaType FROM MSFT_PhysicalDisk");
            using var q = new ManagementObjectSearcher(scope, query);
            foreach (ManagementObject o in q.Get())
                if (Convert.ToInt32(o["MediaType"]) == 4) return true;
        }
        catch { }
        return false;
    }

    private static bool CheckSvcXbox()
    {
        string[] names = ["XblAuthManager", "XblGameSave", "XboxNetApiSvc"];
        return names.Count(CheckSvc) >= 2;
    }

    private static string RunProcess(string exe, string args)
    {
        try
        {
            var psi = new ProcessStartInfo(exe, args)
            {
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute        = false,
                CreateNoWindow         = true,
            };
            using var proc = Process.Start(psi)!;
            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();
            return output;
        }
        catch { return ""; }
    }
}
