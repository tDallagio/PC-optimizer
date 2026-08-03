using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Management;
using System.ServiceProcess;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────
public record DnsProvider(string Name, string Primary, string Secondary);
public record PlanAction(string Category, string Label, string Detail, string Impact);
public record OptResult(int Applied, int Skipped, double FreedMb);

// ─────────────────────────────────────────────────────────────────────────────
public sealed class OptimizationService
{
    // ── DNS providers (mirror de $script:dnsProviders del PS1) ───────────────
    public static readonly IReadOnlyList<DnsProvider> DnsProviders =
    [
        new("Cloudflare", "1.1.1.1",      "1.0.0.1"),
        new("Google",     "8.8.8.8",      "8.8.4.4"),
        new("Quad9",      "9.9.9.9",      "149.112.112.112"),
        new("AdGuard",    "94.140.14.14", "94.140.15.15"),
    ];

    // ── Presets (mirror exacto de $presetGaming / $presetProd / $presetSafe) ─
    private static readonly Dictionary<string, bool> _gaming = new()
    {
        ["TempUser"]    = true,  ["TempSys"]     = true,  ["Prefetch"]    = true,
        ["WinUpdate"]   = true,  ["Browsers"]    = true,  ["Thumb"]       = true,
        ["Recycle"]     = true,  ["EventLogs"]   = false,
        ["Power"]       = true,  ["HPET"]        = true,  ["GPUPrio"]     = true,
        ["PowerThrot"]  = true,  ["Visual"]      = true,  ["MouseAccel"]  = true,
        ["Startup"]     = true,  ["FastStartup"] = true,  ["PageFile"]    = true,
        ["TrimDesfrag"] = true,
        ["GameDVR"]     = true,  ["GameMode"]    = true,  ["Telemetry"]   = true,
        ["Cortana"]     = true,  ["Notif"]       = true,  ["Tasks"]       = true,
        ["Nagle"]       = true,  ["TCP"]         = true,  ["DNS"]         = true,
        ["DNSFlush"]    = true,  ["DisableIPv6"] = false,
        ["SvcXbox"]     = true,  ["SvcDiag"]     = true,  ["SvcWER"]      = true,
        ["SvcSysMain"]  = true,  ["SvcMaps"]     = true,  ["SvcFax"]      = true,
        ["SvcWSearch"]  = true,
    };

    private static readonly Dictionary<string, bool> _prod = new()
    {
        ["TempUser"]    = true,  ["TempSys"]     = true,  ["Prefetch"]    = false,
        ["WinUpdate"]   = true,  ["Browsers"]    = true,  ["Thumb"]       = true,
        ["Recycle"]     = true,  ["EventLogs"]   = false,
        ["Power"]       = true,  ["HPET"]        = false, ["GPUPrio"]     = false,
        ["PowerThrot"]  = false, ["Visual"]      = false, ["MouseAccel"]  = false,
        ["Startup"]     = true,  ["FastStartup"] = false, ["PageFile"]    = true,
        ["TrimDesfrag"] = true,
        ["GameDVR"]     = true,  ["GameMode"]    = true,  ["Telemetry"]   = true,
        ["Cortana"]     = true,  ["Notif"]       = false, ["Tasks"]       = true,
        ["Nagle"]       = false, ["TCP"]         = false, ["DNS"]         = true,
        ["DNSFlush"]    = true,  ["DisableIPv6"] = false,
        ["SvcXbox"]     = true,  ["SvcDiag"]     = true,  ["SvcWER"]      = false,
        ["SvcSysMain"]  = false, ["SvcMaps"]     = false, ["SvcFax"]      = false,
        ["SvcWSearch"]  = false,
    };

    private static readonly Dictionary<string, bool> _safe = new()
    {
        ["TempUser"]    = true,  ["TempSys"]     = true,  ["Prefetch"]    = false,
        ["WinUpdate"]   = true,  ["Browsers"]    = true,  ["Thumb"]       = true,
        ["Recycle"]     = true,  ["EventLogs"]   = false,
        ["Power"]       = false, ["HPET"]        = false, ["GPUPrio"]     = false,
        ["PowerThrot"]  = false, ["Visual"]      = false, ["MouseAccel"]  = false,
        ["Startup"]     = true,  ["FastStartup"] = false, ["PageFile"]    = false,
        ["TrimDesfrag"] = false,
        ["GameDVR"]     = false, ["GameMode"]    = false, ["Telemetry"]   = false,
        ["Cortana"]     = false, ["Notif"]       = false, ["Tasks"]       = false,
        ["Nagle"]       = false, ["TCP"]         = false, ["DNS"]         = true,
        ["DNSFlush"]    = true,  ["DisableIPv6"] = false,
        ["SvcXbox"]     = false, ["SvcDiag"]     = false, ["SvcWER"]      = false,
        ["SvcSysMain"]  = false, ["SvcMaps"]     = false, ["SvcFax"]      = false,
        ["SvcWSearch"]  = false,
    };

    public static IReadOnlyDictionary<string, bool> GetPreset(string name) => name switch
    {
        "Gaming" => _gaming,
        "Prod"   => _prod,
        _        => _safe,
    };

    // ── Build-ActionPlan (mirror exacto del PS1) ──────────────────────────────
    public static List<PlanAction> BuildActionPlan(
        IReadOnlyDictionary<string, bool> sel, int dnsIndex)
    {
        var plan = new List<PlanAction>();
        void Add(string cat, string label, string detail, string impact)
            => plan.Add(new PlanAction(cat, label, detail, impact));

        // Seguridad
        if (G(sel, "Startup"))
            Add("Seguridad", "Punto de restauracion",
                "Crea un punto de restauracion de Windows antes de aplicar cambios", "low");

        // Limpieza
        if (G(sel, "TempUser"))  Add("Limpieza", "Temp usuario",      "%TEMP% - archivos temporales del perfil de usuario",         "low");
        if (G(sel, "TempSys"))   Add("Limpieza", "Temp sistema",      "C:\\Windows\\Temp - temporales del sistema operativo",        "low");
        if (G(sel, "Prefetch"))  Add("Limpieza", "Prefetch (SSD)",    "C:\\Windows\\Prefetch - solo recomendado en SSD",             "low");
        if (G(sel, "WinUpdate")) Add("Limpieza", "Cache Windows Update", "SoftwareDistribution\\Download - paquetes ya instalados",  "low");
        if (G(sel, "Browsers"))  Add("Limpieza", "Cache navegadores", "Chrome, Edge, Firefox, Brave, Opera - no borra contrasenas",  "low");
        if (G(sel, "Thumb"))     Add("Limpieza", "Thumbnails",        "Cache de miniaturas del Explorador - se regenera solo",       "low");
        if (G(sel, "Recycle"))   Add("Limpieza", "Papelera",          "Vacia la papelera permanentemente",                           "low");
        if (G(sel, "EventLogs")) Add("Limpieza", "Logs de eventos",
            "Borra logs Aplicacion/Sistema/etc. Log de Seguridad NO se toca. Elimina registros forenses.", "high");

        // Rendimiento
        if (G(sel, "Power"))       Add("Rendimiento", "Plan de energia",       "Activa Ultimate Performance / Alto Rendimiento",          "medium");
        if (G(sel, "HPET"))        Add("Rendimiento", "Deshabilitar HPET",     "bcdedit: useplatformtick, disabledynamictick",            "medium");
        if (G(sel, "GPUPrio"))     Add("Rendimiento", "GPU Priority",          "Registro DXGI: GPU Priority=8, Scheduling=High",          "medium");
        if (G(sel, "PowerThrot"))  Add("Rendimiento", "Power Throttling OFF",  "PowerThrottlingOff=1 - evita bajadas de frecuencia",      "medium");
        if (G(sel, "Visual"))      Add("Rendimiento", "Efectos visuales min.", "VisualFXSetting=2 - desactiva animaciones de Windows",    "low");
        if (G(sel, "MouseAccel"))  Add("Rendimiento", "Mouse accel OFF",       "MouseSpeed=0, MouseThreshold1/2=0",                       "low");
        if (G(sel, "FastStartup")) Add("Rendimiento", "Fast Startup OFF",      "HiberbootEnabled=0 + powercfg hibernate off",            "medium");
        if (G(sel, "PageFile"))    Add("Rendimiento", "Optimizar PageFile",    "Tamanio fijo segun RAM via Win32_PageFileSetting",        "high");
        if (G(sel, "TrimDesfrag"))
        {
            // PS1 no tiene acceso a hasSsd aqui; en C# tampoco (BuildActionPlan es estatico)
            Add("Rendimiento", "TRIM / Desfrag", "Optimize-Volume ReTrim (SSD) o desfrag semanal (HDD)", "low");
        }

        // Privacidad
        if (G(sel, "GameDVR"))   Add("Privacidad", "Game DVR / Xbox OFF", "GameDVR_Enabled=0, AllowGameDVR=0",                       "medium");
        if (G(sel, "GameMode"))  Add("Privacidad", "Game Mode OFF",       "AutoGameModeEnabled=0 - evita stutters en AMD/Ryzen",     "medium");
        if (G(sel, "Telemetry")) Add("Privacidad", "Telemetria Windows",  "AllowTelemetry=0 - detiene envio de datos a Microsoft",   "medium");
        if (G(sel, "Cortana"))   Add("Privacidad", "Cortana OFF",         "AllowCortana=0 via politica de grupo",                    "medium");
        if (G(sel, "Notif"))     Add("Privacidad", "Notificaciones OFF",  "ToastEnabled=0 - sin interrupciones mientras se juega",   "low");
        if (G(sel, "Tasks"))     Add("Privacidad", "Tareas telemetria",   "Deshabilita 5 tareas programadas de recopilacion de datos", "medium");

        // Red
        if (G(sel, "Nagle"))       Add("Red", "Nagle OFF",    "TcpAckFrequency=1, TCPNoDelay=1 en todos los adaptadores", "medium");
        if (G(sel, "TCP"))         Add("Red", "TCP/IP gaming", "netsh: autotuning normal, chimney disabled, RSS, FastOpen", "medium");
        if (G(sel, "DNS"))
        {
            int idx = Math.Clamp(dnsIndex, 0, DnsProviders.Count - 1);
            var p   = DnsProviders[idx];
            Add("Red", $"DNS {p.Name}", $"{p.Primary} / {p.Secondary} en todos los adaptadores activos", "low");
        }
        if (G(sel, "DNSFlush"))    Add("Red", "Flush DNS",          "ipconfig /flushdns - limpia cache DNS local",                   "low");
        if (G(sel, "DisableIPv6")) Add("Red", "Preferir IPv4 sobre IPv6",
            "DisabledComponents=0x20 - IPv6 sigue activo, Windows prefiere IPv4. Seguro en todas las redes.", "low");

        // Servicios
        if (G(sel, "SvcXbox"))    Add("Servicios", "Xbox Live (3 svcs)",   "XblAuthManager, XblGameSave, XboxNetApiSvc -> Disabled",  "medium");
        if (G(sel, "SvcDiag"))    Add("Servicios", "DiagTrack",            "Connected User Experiences and Telemetry -> Disabled",    "medium");
        if (G(sel, "SvcWER"))     Add("Servicios", "Error Reporting",      "WerSvc -> Disabled",                                      "medium");
        if (G(sel, "SvcSysMain")) Add("Servicios", "SysMain / Superfetch", "SysMain -> Disabled (solo SSD)",                         "medium");
        if (G(sel, "SvcMaps"))    Add("Servicios", "Maps / Geo",           "MapsBroker, lfsvc -> Disabled",                           "medium");
        if (G(sel, "SvcFax"))     Add("Servicios", "Fax / Remote Reg",     "Fax, RemoteRegistry -> Disabled",                         "medium");
        if (G(sel, "SvcWSearch")) Add("Servicios", "Windows Search",       "WSearch -> Disabled (solo SSD)",                          "medium");

        return plan;
    }

    // ── Estado de la ejecucion actual ─────────────────────────────────────────
    private int    _applied;
    private int    _skipped;
    private double _freedMb;

    // ── RunAsync: orquestador principal ───────────────────────────────────────
    public async Task<OptResult> RunAsync(
        IReadOnlyDictionary<string, bool> sel,
        bool   hasSsd,
        bool   isLaptop,
        double totalRamGb,
        string sysDrive,
        int    dnsIndex,
        string? altDriveForPageFile,
        bool   movePageFileToAlt,
        CancellationToken ct)
    {
        _applied = 0;
        _skipped = 0;
        _freedMb = 0;

        // Punto de restauracion (2%)
        if (G(sel, "Startup"))
        {
            await Task.Run(() => Safe(() => CreateRestorePoint(sysDrive), "Punto de restauracion"), ct);
        }

        ct.ThrowIfCancellationRequested();

        // Limpieza (8-20%)
        _freedMb = await Task.Run(() => SafeD(() => CleanupTweaks(sel, hasSsd, sysDrive), "Limpieza"), ct);

        ct.ThrowIfCancellationRequested();

        // Plan de energia (30-36%)
        if (G(sel, "Power"))
            await Task.Run(() => Safe(() => PowerPlanTweaks(isLaptop), "Plan de energia"), ct);

        // HPET (36-44%)
        if (G(sel, "HPET"))
            await Task.Run(() => Safe(() => HpetTweaks(), "HPET"), ct);

        // Tweaks de registro (44-70%)
        await Task.Run(() => Safe(() => RegistryTweaks(sel), "Tweaks de registro"), ct);

        ct.ThrowIfCancellationRequested();

        // Red (70-75%)
        await Task.Run(() => Safe(() => NetworkTweaks(sel, dnsIndex), "Red"), ct);

        // Servicios (82-88%)
        await Task.Run(() => Safe(() => ServiceTweaks(sel, hasSsd), "Servicios"), ct);

        ct.ThrowIfCancellationRequested();

        // Fast Startup (88-92%)
        if (G(sel, "FastStartup"))
            await Task.Run(() => Safe(() => FastStartupTweaks(), "Fast Startup"), ct);

        // PageFile (91-94%)
        if (G(sel, "PageFile"))
            await Task.Run(() => Safe(() => PageFileTweaks(totalRamGb, sysDrive, altDriveForPageFile, movePageFileToAlt), "PageFile"), ct);

        // TRIM / Desfrag (94-96%)
        if (G(sel, "TrimDesfrag"))
        {
            try { await TrimTweaksAsync(hasSsd, ct); }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { Log($"Fallo: TRIM/Desfrag ({ex.Message})", "err"); }
        }

        // Efectos visuales (96%)
        if (G(sel, "Visual"))
            await Task.Run(() => Safe(() => VisualTweaks(totalRamGb), "Efectos visuales"), ct);

        return new OptResult(_applied, _skipped, _freedMb);
    }

    // Ejecuta un paso de la optimizacion sin dejar que una excepcion no
    // capturada frene el resto del flujo (ej. Process.Start fallando para
    // powercfg/bcdedit/netsh en una maquina rara). Cancelacion del usuario
    // se sigue propagando normalmente.
    private static void Safe(Action step, string label)
    {
        try { step(); }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) { Log($"Fallo: {label} ({ex.Message})", "err"); }
    }

    private static double SafeD(Func<double> step, string label)
    {
        try { return step(); }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) { Log($"Fallo: {label} ({ex.Message})", "err"); return 0; }
    }

    // ── Punto de restauracion ─────────────────────────────────────────────────

    private void CreateRestorePoint(string sysDrive)
    {
        Prog(2, "Creando punto de restauracion (puede tardar 30-60 s)...");
        Log("PUNTO DE RESTAURACION", "head");
        try
        {
            string driveArg = sysDrive.TrimEnd('\\') + @"\";
            string cmd = $"Enable-ComputerRestore -Drive '{driveArg}' -EA SilentlyContinue; " +
                         "Checkpoint-Computer -Description 'WinBoost pre-optimizacion' " +
                         "-RestorePointType MODIFY_SETTINGS -EA Stop";
            using var p = new Process
            {
                StartInfo = new ProcessStartInfo("powershell.exe",
                    $"-NoProfile -NonInteractive -Command \"{cmd}\"")
                {
                    UseShellExecute = false, CreateNoWindow = true
                }
            };
            p.Start();
            p.WaitForExit(90_000);
            Log("Punto de restauracion creado", "ok");
        }
        catch
        {
            Log("Advertencia: no se pudo crear el punto de restauracion. Continuando de todas formas.", "skip");
        }
    }

    // ── Invoke-CleanupTweaks ──────────────────────────────────────────────────

    private double CleanupTweaks(
        IReadOnlyDictionary<string, bool> sel, bool hasSsd, string sysDrive)
    {
        Log("LIMPIEZA DE ARCHIVOS", "head");
        Prog(8, "Limpiando temporales...");

        double freed = 0;
        string local  = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string tempEnv = Environment.GetEnvironmentVariable("TEMP") ?? Path.GetTempPath();

        if (G(sel, "TempUser")) { freed += RemoveDir(tempEnv, "Temp usuario"); _applied++; }
        if (G(sel, "TempSys"))  { freed += RemoveDir(Path.Combine(sysDrive, @"Windows\Temp"), "Temp sistema"); _applied++; }
        if (G(sel, "Prefetch"))
        {
            if (hasSsd) { freed += RemoveDir(Path.Combine(sysDrive, @"Windows\Prefetch"), "Prefetch"); _applied++; }
            else        { Log("Prefetch omitido (requiere SSD)", "skip"); _skipped++; }
        }
        if (G(sel, "WinUpdate"))
        {
            try { RunProcess("net", "stop wuauserv /y"); } catch { }
            freed += RemoveDir(Path.Combine(sysDrive, @"Windows\SoftwareDistribution\Download"), "WUpdate cache");
            try { RunProcess("net", "start wuauserv"); } catch { }
            _applied++;
        }
        if (G(sel, "Browsers"))
        {
            Prog(14, "Cache navegadores...");
            (string path, string name)[] browsers =
            [
                (Path.Combine(local, @"Google\Chrome\User Data\Default\Cache"),          "Chrome"),
                (Path.Combine(local, @"Microsoft\Edge\User Data\Default\Cache"),         "Edge"),
                (Path.Combine(local, @"BraveSoftware\Brave-Browser\User Data\Default\Cache"), "Brave"),
                (Path.Combine(local, @"Opera Software\Opera Stable\Cache"),              "Opera"),
                (Path.Combine(appData, @"Mozilla\Firefox\Profiles"),                    "Firefox"),
            ];
            foreach (var (path, bname) in browsers)
                freed += RemoveDir(path, $"Cache {bname}");
            _applied++;
        }
        if (G(sel, "Thumb"))
        {
            freed += RemoveDir(Path.Combine(local, @"Microsoft\Windows\Explorer"), "Thumbnails");
            _applied++;
        }
        if (G(sel, "Recycle"))
        {
            try { NativeMethods.EmptyRecycleBin(); Log("Papelera vaciada", "ok"); _applied++; }
            catch { Log("Papelera: archivos en uso", "skip"); }
        }
        if (G(sel, "EventLogs"))
        {
            Prog(18, "Logs de eventos...");
            ClearEventLogs();
            Log("Logs de eventos limpiados (Security excluido)", "ok");
            _applied++;
        }

        double mb = Math.Round(freed, 1);
        Log($"Total liberado: {mb} MB", "ok");
        return freed;
    }

    // ── Invoke-RegistryTweaks ─────────────────────────────────────────────────

    private void RegistryTweaks(IReadOnlyDictionary<string, bool> sel)
    {
        Log("REGISTRO", "head");
        Prog(44, "Tweaks de registro...");

        const string gp = @"HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games";

        if (G(sel, "GPUPrio"))
        {
            SetReg(gp, "GPU Priority",         RegistryValueKind.DWord,  8);
            SetReg(gp, "Priority",             RegistryValueKind.DWord,  6);
            SetReg(gp, "Scheduling Category", RegistryValueKind.String, "High");
            SetReg(gp, "SFIO Priority",       RegistryValueKind.String, "High");
            SetReg(gp, "Background Only",     RegistryValueKind.String, "False");
            _applied++;
        }
        if (G(sel, "PowerThrot"))
        {
            SetReg(@"HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling",
                "PowerThrottlingOff", RegistryValueKind.DWord, 1);
            _applied++;
        }
        if (G(sel, "MouseAccel"))
        {
            SetReg(@"HKCU:\Control Panel\Mouse", "MouseSpeed",      RegistryValueKind.String, "0");
            SetReg(@"HKCU:\Control Panel\Mouse", "MouseThreshold1", RegistryValueKind.String, "0");
            SetReg(@"HKCU:\Control Panel\Mouse", "MouseThreshold2", RegistryValueKind.String, "0");
            SetReg(@"HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters",
                "MouseDataQueueSize", RegistryValueKind.DWord, 20);
            _applied++;
        }

        if (G(sel, "GameDVR") || G(sel, "GameMode"))
        { Prog(52, "Game DVR..."); Log("GAME DVR / XBOX", "head"); }

        if (G(sel, "GameDVR"))
        {
            SetReg(@"HKCU:\System\GameConfigStore", "GameDVR_Enabled",                   RegistryValueKind.DWord, 0);
            SetReg(@"HKCU:\System\GameConfigStore", "GameDVR_FSEBehaviorMode",           RegistryValueKind.DWord, 2);
            SetReg(@"HKCU:\System\GameConfigStore", "GameDVR_HonorUserFSEBehaviorMode",  RegistryValueKind.DWord, 1);
            SetReg(@"HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR", "AllowGameDVR", RegistryValueKind.DWord, 0);
            _applied++;
        }
        if (G(sel, "GameMode"))
        {
            SetReg(@"HKCU:\Software\Microsoft\GameBar", "AutoGameModeEnabled", RegistryValueKind.DWord, 0);
            SetReg(@"HKCU:\Software\Microsoft\GameBar", "AllowAutoGameMode",   RegistryValueKind.DWord, 0);
            _applied++;
        }

        bool anyPrivacy = G(sel, "Telemetry") || G(sel, "Cortana") || G(sel, "Notif") || G(sel, "Tasks");
        if (anyPrivacy) { Prog(60, "Privacidad..."); Log("PRIVACIDAD / TELEMETRIA", "head"); }

        if (G(sel, "Telemetry"))
        {
            SetReg(@"HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
                "AllowTelemetry", RegistryValueKind.DWord, 0);
            SetReg(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
                "AllowTelemetry", RegistryValueKind.DWord, 0);
            _applied++;
        }
        if (G(sel, "Cortana"))
        {
            SetReg(@"HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
                "AllowCortana", RegistryValueKind.DWord, 0);
            _applied++;
        }
        if (G(sel, "Notif"))
        {
            SetReg(@"HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications",
                "ToastEnabled", RegistryValueKind.DWord, 0);
            _applied++;
        }
        if (G(sel, "Tasks"))
        {
            string[] tasks =
            [
                @"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
                @"\Microsoft\Windows\Application Experience\ProgramDataUpdater",
                @"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
                @"\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
                @"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
            ];
            foreach (var t in tasks)
                try { RunProcess("schtasks", $"/change /tn \"{t}\" /disable"); } catch { }
            Log("Tareas telemetria deshabilitadas", "ok");
            _applied++;
        }
    }

    // ── Invoke-NetworkTweaks ──────────────────────────────────────────────────

    private void NetworkTweaks(IReadOnlyDictionary<string, bool> sel, int dnsIndex)
    {
        bool any = G(sel, "Nagle") || G(sel, "TCP") || G(sel, "DNS") || G(sel, "DNSFlush") || G(sel, "DisableIPv6");
        if (!any) return;

        Prog(70, "Red...");
        Log("RED", "head");

        if (G(sel, "DNS") || G(sel, "DisableIPv6"))
            try { App.Backup.SaveNetBackup(); } catch (Exception ex) { Log($"Backup de red fallo: {ex.Message}", "skip"); }
        if (G(sel, "TCP"))
            try { App.Backup.SaveNetshBackup(); } catch (Exception ex) { Log($"Backup de netsh fallo: {ex.Message}", "skip"); }

        if (G(sel, "Nagle"))
        {
            try
            {
                int nagleCount = 0;
                const string ifRoot = @"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces";
                using var root = Registry.LocalMachine.OpenSubKey(ifRoot);
                if (root != null)
                {
                    foreach (string sub in root.GetSubKeyNames())
                    {
                        using var sk = root.OpenSubKey(sub, writable: false);
                        string? ip = sk?.GetValue("DhcpIPAddress") as string;
                        if (!string.IsNullOrEmpty(ip) && ip != "0.0.0.0")
                        {
                            string psPath = $@"HKLM:\{ifRoot}\{sub}";
                            SetReg(psPath, "TcpAckFrequency", RegistryValueKind.DWord, 1);
                            SetReg(psPath, "TCPNoDelay",      RegistryValueKind.DWord, 1);
                            nagleCount++;
                        }
                    }
                }
                Log($"Nagle OFF en {nagleCount} adaptador(es)", "ok");
            }
            catch (Exception ex) { Log($"Fallo: Nagle ({ex.Message})", "err"); }
            _applied++;
        }

        if (G(sel, "TCP"))
        {
            try
            {
                RunProcess("netsh", "int tcp set global autotuninglevel=normal");
                RunProcess("netsh", "int tcp set global chimney=disabled");
                RunProcess("netsh", "int tcp set global rss=enabled");
                RunProcess("netsh", "int tcp set global fastopen=enabled");
                Log("TCP/IP optimizado", "ok");
            }
            catch (Exception ex) { Log($"Fallo: TCP/IP ({ex.Message})", "err"); }
            _applied++;
        }

        if (G(sel, "DNS"))
        {
            int idx = Math.Clamp(dnsIndex, 0, DnsProviders.Count - 1);
            var prov = DnsProviders[idx];
            int dn   = 0;
            try
            {
                using var searcher = new ManagementObjectSearcher(
                    "SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True AND MACAddress IS NOT NULL");
                foreach (ManagementObject mo in searcher.Get())
                {
                    try
                    {
                        var inParams = mo.GetMethodParameters("SetDNSServerSearchOrder");
                        inParams["DNSServerSearchOrder"] = new string[] { prov.Primary, prov.Secondary };
                        mo.InvokeMethod("SetDNSServerSearchOrder", inParams, new InvokeMethodOptions());
                        dn++;
                    }
                    catch { }
                    finally { mo.Dispose(); }
                }
            }
            catch { }
            Log($"DNS {prov.Name} ({prov.Primary} / {prov.Secondary}) en {dn} adaptador(es)", "ok");
            _applied++;
        }

        if (G(sel, "DNSFlush"))
        {
            try
            {
                RunProcess("ipconfig", "/flushdns");
                Log("Cache DNS limpiada", "ok");
            }
            catch (Exception ex) { Log($"Fallo: Flush DNS ({ex.Message})", "err"); }
            _applied++;
        }

        if (G(sel, "DisableIPv6"))
        {
            Prog(75, "Preferencia IPv4...");
            Log("IPv4 PREFERIDO SOBRE IPv6", "head");
            SetReg(@"HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters",
                "DisabledComponents", RegistryValueKind.DWord, 0x20);
            Log("IPv4 preferido sobre IPv6 (DisabledComponents=0x20, IPv6 activo)", "ok");
            _applied++;
        }
    }

    // ── Invoke-ServiceTweaks ──────────────────────────────────────────────────

    private void ServiceTweaks(IReadOnlyDictionary<string, bool> sel, bool hasSsd)
    {
        bool any = G(sel, "SvcXbox") || G(sel, "SvcDiag") || G(sel, "SvcWER") ||
                   G(sel, "SvcSysMain") || G(sel, "SvcMaps") || G(sel, "SvcFax") || G(sel, "SvcWSearch");
        if (!any) return;

        Prog(82, "Servicios...");
        Log("SERVICIOS", "head");

        if (G(sel, "SvcXbox"))
        {
            DisableSvc("XblAuthManager",  "Xbox Live Auth");
            DisableSvc("XblGameSave",     "Xbox GameSave");
            DisableSvc("XboxNetApiSvc",   "Xbox Networking");
            _applied++;
        }
        if (G(sel, "SvcDiag"))   { DisableSvc("DiagTrack",       "DiagTrack");                 _applied++; }
        if (G(sel, "SvcWER"))    { DisableSvc("WerSvc",          "Windows Error Reporting");    _applied++; }
        if (G(sel, "SvcSysMain"))
        {
            if (hasSsd) { DisableSvc("SysMain", "SysMain/Superfetch"); _applied++; }
            else        { Log("SysMain/Superfetch omitido (requiere SSD)", "skip"); _skipped++; }
        }
        if (G(sel, "SvcMaps"))
        {
            DisableSvc("MapsBroker", "Maps Broker");
            DisableSvc("lfsvc",      "Geolocation");
            _applied++;
        }
        if (G(sel, "SvcFax"))
        {
            DisableSvc("Fax",            "Fax");
            DisableSvc("RemoteRegistry", "Remote Registry");
            _applied++;
        }
        if (G(sel, "SvcWSearch"))
        {
            if (hasSsd) { DisableSvc("WSearch", "Windows Search (indexado)"); _applied++; }
            else        { Log("Windows Search omitido (requiere SSD)", "skip"); _skipped++; }
        }
    }

    // ── Plan de energia ───────────────────────────────────────────────────────

    private void PowerPlanTweaks(bool isLaptop)
    {
        Prog(30, "Plan de energia...");
        Log("PLAN DE ENERGIA", "head");
        try { App.Backup.SavePowerPlanBackup(); }
        catch (Exception ex) { Log($"Backup de plan de energia fallo: {ex.Message}", "skip"); }

        // GUID "semilla" que powercfg reconoce como plantilla oculta de Ultimate Performance.
        // OJO: -duplicatescheme NO conserva este GUID en el plan resultante -- asigna uno
        // nuevo aleatorio cada vez. Comparar contra este GUID fijo (como hacia el codigo viejo,
        // igual que el .ps1) nunca matchea, asi que la deteccion de "ya existe" siempre fallaba
        // -> duplicaba en cada corrida y despues activaba el fallback SCHEME_MIN en vez del plan
        // recien creado. El fix busca el plan YA CREADO por nombre (bilingue) en vez de por GUID.
        const string ultimateSeedGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61";

        try
        {
            if (!isLaptop)
            {
                string list = RunProcessCapture("powercfg", "/list");
                string? guid = FindSchemeGuidByName(list, "Ultimate Performance", "M.ximo rendimiento");

                if (guid == null)
                {
                    RunProcess("powercfg", $"-duplicatescheme {ultimateSeedGuid}");
                    list = RunProcessCapture("powercfg", "/list");
                    guid = FindSchemeGuidByName(list, "Ultimate Performance", "M.ximo rendimiento");
                }

                if (guid != null)
                {
                    RunProcess("powercfg", $"/setactive {guid}");
                    Log("Ultimate Performance activado", "ok");
                }
                else
                {
                    RunProcess("powercfg", "/setactive SCHEME_MIN");
                    Log("Alto Rendimiento activado", "ok");
                }
                RunProcess("powercfg", "/hibernate off");
                Log("Hibernate desactivado", "ok");
            }
            else
            {
                RunProcess("powercfg", "/setactive SCHEME_MIN");
                Log("Alto Rendimiento activado (laptop)", "ok");
            }
        }
        catch (Exception ex) { Log($"Fallo activando el plan de energia: {ex.Message}", "err"); }

        try { RunProcess("powercfg", "/change standby-timeout-ac 0"); }
        catch (Exception ex) { Log($"Fallo: standby-timeout ({ex.Message})", "err"); }

        _applied++;
    }

    // Busca en la salida de "powercfg /list" un plan cuyo nombre matchee alguno de los
    // patrones dados (regex, case-insensitive) y devuelve su GUID. Cada linea tiene la forma
    // "<etiqueta>: <guid>  (<nombre>) [*]" en cualquier idioma; el GUID y los parentesis son
    // el unico formato estable entre locales.
    private static string? FindSchemeGuidByName(string powercfgListOutput, params string[] namePatterns)
    {
        foreach (Match line in Regex.Matches(
            powercfgListOutput,
            @"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([^)]+)\)"))
        {
            string name = line.Groups[2].Value;
            foreach (string pattern in namePatterns)
                if (Regex.IsMatch(name, pattern, RegexOptions.IgnoreCase))
                    return line.Groups[1].Value;
        }
        return null;
    }

    // ── HPET ─────────────────────────────────────────────────────────────────

    private void HpetTweaks()
    {
        Prog(36, "HPET...");
        Log("HPET / TIMER", "head");
        try
        {
            RunProcess("bcdedit", "/deletevalue useplatformclock");
            RunProcess("bcdedit", "/set useplatformtick yes");
            RunProcess("bcdedit", "/set disabledynamictick yes");
            Log("HPET deshabilitado - TSC activado", "ok");
        }
        catch (Exception ex) { Log($"Fallo: HPET ({ex.Message})", "err"); }
        _applied++;
    }

    // ── Fast Startup ──────────────────────────────────────────────────────────

    private void FastStartupTweaks()
    {
        Prog(88, "Fast Startup...");
        Log("FAST STARTUP", "head");
        SetReg(@"HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power",
            "HiberbootEnabled", RegistryValueKind.DWord, 0);
        try
        {
            RunProcess("powercfg", "/hibernate off");
            Log("Fast Startup deshabilitado (HiberbootEnabled=0 + hibernate off)", "ok");
        }
        catch (Exception ex) { Log($"Fallo: hibernate off ({ex.Message})", "err"); }
        _applied++;
    }

    // ── PageFile ──────────────────────────────────────────────────────────────

    private void PageFileTweaks(
        double totalRamGb, string sysDrive, string? altDrive, bool moveToAlt)
    {
        Prog(91, "Optimizando PageFile...");
        Log("PAGEFILE", "head");
        App.Backup.SavePageFileBackup();

        try
        {
            int totalRamMb = (int)(totalRamGb * 1024);
            int pfMin = Math.Max(4096, Math.Min(totalRamMb,     8192));
            int pfMax = Math.Max(8192, Math.Min(totalRamMb * 2, 16384));

            string target = (moveToAlt && !string.IsNullOrEmpty(altDrive)) ? altDrive : sysDrive;
            string pfPath = target.TrimEnd('\\') + @"\pagefile.sys";

            // Deshabilitar gestion automatica
            using var cs = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem")
                .Get().OfType<ManagementObject>().FirstOrDefault();
            if (cs != null && cs["AutomaticManagedPagefile"] is true)
            {
                cs["AutomaticManagedPagefile"] = false;
                cs.Put();
                Log("Gestion automatica de PageFile desactivada", "ok");
            }

            // Crear el nuevo PageFile PRIMERO
            using var cls  = new ManagementClass("Win32_PageFileSetting");
            using var inst = cls.CreateInstance();
            inst["Name"]        = pfPath;
            inst["InitialSize"] = pfMin;
            inst["MaximumSize"] = pfMax;
            inst.Put();

            // Verificar que existe
            bool exists = new ManagementObjectSearcher("SELECT * FROM Win32_PageFileSetting")
                .Get().OfType<ManagementObject>()
                .Any(o => string.Equals(o["Name"]?.ToString(), pfPath, StringComparison.OrdinalIgnoreCase));
            if (!exists)
                throw new InvalidOperationException("Verificacion fallida: el nuevo PageFile no aparece en Win32_PageFileSetting");

            // Borrar los anteriores (excepto el recien creado)
            foreach (ManagementObject pf in new ManagementObjectSearcher("SELECT * FROM Win32_PageFileSetting").Get())
            {
                if (!string.Equals(pf["Name"]?.ToString(), pfPath, StringComparison.OrdinalIgnoreCase))
                    try { pf.Delete(); } catch { }
                pf.Dispose();
            }

            Log($"PageFile: {pfPath}  min={pfMin} MB  max={pfMax} MB", "ok");
            Log("Cambio efectivo tras reinicio", "info");
            _applied++;
        }
        catch (Exception ex)
        {
            // Rollback: reactivar gestion automatica
            try
            {
                using var cs2 = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem")
                    .Get().OfType<ManagementObject>().FirstOrDefault();
                if (cs2 != null && cs2["AutomaticManagedPagefile"] is false)
                {
                    cs2["AutomaticManagedPagefile"] = true;
                    cs2.Put();
                    Log("PageFile: se restauro gestion automatica tras error", "skip");
                }
            }
            catch { }
            Log($"Error configurando PageFile: {ex.Message}", "err");
        }
    }

    // ── TRIM / Desfrag (async con progreso) ───────────────────────────────────

    private async Task TrimTweaksAsync(bool hasSsd, CancellationToken ct)
    {
        Prog(94, "TRIM / Desfrag schedule...");
        Log("TRIM / DESFRAG", "head");

        List<char> ssdLetters = await Task.Run(() =>
        {
            try
            {
                if (hasSsd)
                {
                    string trimStatus = RunProcessCapture("fsutil", "behavior query DisableDeleteNotify");
                    if (trimStatus.Contains("= 1"))
                    {
                        RunProcess("fsutil", "behavior set DisableDeleteNotify 0");
                        Log("TRIM re-habilitado (DisableDeleteNotify=0)", "ok");
                    }
                    else
                        Log("TRIM ya estaba habilitado", "ok");

                    try
                    {
                        RunProcess("schtasks",
                            @"/change /tn ""\Microsoft\Windows\Defrag\ScheduledDefrag"" /enable");
                        Log("Tarea ScheduledDefrag habilitada (TRIM semanal automatico)", "ok");
                    }
                    catch { Log("No se pudo habilitar tarea de TRIM", "skip"); }

                    return GetSsdDriveLetters();
                }
                else
                {
                    try
                    {
                        RunProcess("schtasks",
                            @"/change /tn ""\Microsoft\Windows\Defrag\ScheduledDefrag"" /enable");
                        Log("Desfrag semanal habilitado (HDD)", "ok");
                    }
                    catch { Log("No se pudo habilitar tarea de Desfrag", "skip"); }
                    return [];
                }
            }
            catch (Exception ex) { Log($"Error en TRIM/Desfrag setup: {ex.Message}", "err"); return []; }
        }, ct);

        if (ssdLetters.Count == 0) return;

        Prog(94, "TRIM en progreso (puede tardar varios minutos)...");
        Log($"TRIM lanzado en background para {ssdLetters.Count} volumen(es) SSD", "info");

        var trimTask = Task.Run(async () =>
        {
            foreach (char letter in ssdLetters)
            {
                ct.ThrowIfCancellationRequested();
                string cmd = $"-NoProfile -NonInteractive -Command " +
                             $"\"Optimize-Volume -DriveLetter '{letter}' -ReTrim -NormalPriority -ErrorAction SilentlyContinue\"";
                using var p = new Process
                {
                    StartInfo = new ProcessStartInfo("powershell.exe", cmd)
                    { UseShellExecute = false, CreateNoWindow = true }
                };
                p.Start();
                await p.WaitForExitAsync(ct);
                Log($"TRIM completado en {letter}:", "ok");
            }
        }, ct);

        int elapsed = 0;
        while (!trimTask.IsCompleted)
        {
            await Task.Delay(1000, ct);
            elapsed++;
            Prog(94, $"TRIM en progreso... {elapsed} s");
        }

        await trimTask; // propaga OperationCanceledException si fue cancelado
    }

    // ── Efectos visuales ──────────────────────────────────────────────────────

    private void VisualTweaks(double totalRamGb)
    {
        Prog(96, "Efectos visuales...");
        Log("EFECTOS VISUALES", "head");
        SetReg(@"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
            "VisualFXSetting", RegistryValueKind.DWord, 2);
        SetReg(@"HKCU:\Control Panel\Desktop", "FontSmoothing", RegistryValueKind.String, "2");
        if (totalRamGb <= 8)
        {
            SetReg(@"HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                "EnableTransparency", RegistryValueKind.DWord, 0);
            Log("Transparencia OFF (RAM baja)", "ok");
        }
        _applied++;
    }

    // ── Helpers privados ──────────────────────────────────────────────────────

    private void SetReg(string psPath, string name, RegistryValueKind kind, object value)
    {
        try
        {
            App.Backup.SaveRegBackup(psPath, name);
            using var key = OpenOrCreateKey(psPath);
            key?.SetValue(name, value, kind);
            Log($"{name} = {value}", "ok");
        }
        catch { Log($"Fallo: {name}", "err"); }
    }

    private void DisableSvc(string name, string label)
    {
        try
        {
            using var svc = new ServiceController(name);
            if (svc.StartType == ServiceStartMode.Disabled)
            {
                Log($"{label} (ya deshabilitado)", "skip");
                return;
            }
            App.Backup.SaveSvcBackup(name);
            try
            {
                svc.Stop();
                svc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(10));
            }
            catch { }
            // StartupType via registro: 4 = Disabled (SetService no disponible en .NET)
            using var key = RegistryPrivilegeHelper.OpenWritable(
                RegistryHive.LocalMachine, $@"SYSTEM\CurrentControlSet\Services\{name}");
            key?.SetValue("Start", 4, RegistryValueKind.DWord);
            Log(label, "ok");
        }
        catch { Log($"Sin permisos: {label}", "skip"); }
    }

    private double RemoveDir(string path, string label)
    {
        if (!Directory.Exists(path))
        { Log($"{label} - no encontrado", "skip"); return 0; }

        double mb = GetFolderMb(path);
        foreach (string entry in Directory.EnumerateFileSystemEntries(path))
        {
            try
            {
                if (Directory.Exists(entry))
                    Directory.Delete(entry, recursive: true);
                else
                {
                    File.SetAttributes(entry, FileAttributes.Normal);
                    File.Delete(entry);
                }
            }
            catch { }
        }
        Log($"{label} - {Math.Round(mb, 1)} MB liberados", "ok");
        return mb;
    }

    private static double GetFolderMb(string path)
    {
        try
        {
            return Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)
                .Sum(f => { try { return new FileInfo(f).Length; } catch { return 0L; } })
                / 1_048_576.0;
        }
        catch { return 0; }
    }

    private static void ClearEventLogs()
    {
        try
        {
            foreach (string logName in EventLogSession.GlobalSession.GetLogNames())
            {
                if (string.Equals(logName, "Security", StringComparison.OrdinalIgnoreCase)) continue;
                try { EventLogSession.GlobalSession.ClearLog(logName); }
                catch { }
            }
        }
        catch { }
    }

    private static List<char> GetSsdDriveLetters()
    {
        var letters = new List<char>();
        try
        {
            var scope = new ManagementScope(@"\\.\ROOT\Microsoft\Windows\Storage");
            scope.Connect();
            using var diskSearcher = new ManagementObjectSearcher(scope,
                new ObjectQuery("SELECT DeviceId FROM MSFT_PhysicalDisk WHERE MediaType = 4"));
            foreach (ManagementObject disk in diskSearcher.Get())
            {
                string? deviceId = disk["DeviceId"]?.ToString();
                if (string.IsNullOrEmpty(deviceId)) { disk.Dispose(); continue; }

                using var partSearcher = new ManagementObjectSearcher(scope,
                    new ObjectQuery($"SELECT DriveLetter FROM MSFT_Partition WHERE DiskNumber = {deviceId}"));
                foreach (ManagementObject part in partSearcher.Get())
                {
                    string? dl = part["DriveLetter"]?.ToString();
                    if (!string.IsNullOrEmpty(dl) && dl[0] != '\0')
                        letters.Add(dl[0]);
                    part.Dispose();
                }
                disk.Dispose();
            }
        }
        catch
        {
            // Fallback: todos los drives fijos (si hay SSD, asumimos que todos son SSD)
            letters.AddRange(DriveInfo.GetDrives()
                .Where(d => d.IsReady && d.DriveType == DriveType.Fixed)
                .Select(d => d.RootDirectory.FullName[0]));
        }
        return letters;
    }

    private static RegistryKey? OpenOrCreateKey(string psPath)
    {
        string p = psPath.TrimEnd('\\');
        RegistryHive hive;
        string sub;
        if (p.StartsWith("HKLM:", StringComparison.OrdinalIgnoreCase))
        { hive = RegistryHive.LocalMachine; sub = p["HKLM:".Length..].TrimStart('\\'); }
        else if (p.StartsWith("HKCU:", StringComparison.OrdinalIgnoreCase))
        { hive = RegistryHive.CurrentUser; sub = p["HKCU:".Length..].TrimStart('\\'); }
        else
            throw new ArgumentException($"Hive desconocido: {psPath}");

        return RegistryPrivilegeHelper.OpenWritable(hive, sub);
    }

    private static void RunProcess(string exe, string args)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo(exe, args)
            { UseShellExecute = false, CreateNoWindow = true,
              RedirectStandardOutput = true, RedirectStandardError = true }
        };
        p.Start();
        p.WaitForExit(30_000);
    }

    private static string RunProcessCapture(string exe, string args)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo(exe, args)
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true }
        };
        p.Start();
        string output = p.StandardOutput.ReadToEnd();
        p.WaitForExit(30_000);
        return output;
    }

    private static bool G(IReadOnlyDictionary<string, bool> sel, string key)
        => sel.TryGetValue(key, out bool v) && v;

    private static void Log(string msg, string type)
        => App.Logger?.Log(msg, type);

    private static void Prog(int pct, string msg)
        => App.Progress?.Set(pct, msg);
}
