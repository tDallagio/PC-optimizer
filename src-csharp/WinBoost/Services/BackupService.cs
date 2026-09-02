using System.Collections.Generic;
using System.Diagnostics;
using System.Management;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace WinBoost.Services;

public sealed class BackupService
{
    private string?            _path;
    private readonly List<BackupAction> _actions = [];
    private readonly List<SvcEntry>     _svcs    = [];
    private readonly List<NetEntry>     _nets    = [];

    public string? ActiveSession => _path;
    public bool    HasSession    => _path is not null;

    // ================================================================
    // SAVE — equivalentes a Save-* del PS1
    // ================================================================

    public string? NewBackupSession()
    {
        string ts   = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
        string root = App.Settings.Current.BackupRoot;
        string path = Path.Combine(root, ts);
        try
        {
            Directory.CreateDirectory(path);
            _path = path;
            _actions.Clear();
            _svcs.Clear();
            _nets.Clear();
            App.Logger?.Log($"Sesion de backup iniciada: {ts}", "ok");
            return path;
        }
        catch (Exception ex)
        {
            App.Logger?.Log($"No se pudo crear sesion de backup: {ex.Message}", "err");
            _path = null;
            return null;
        }
    }

    public void SaveRegBackup(string regPath, string label)
    {
        if (_path is null) return;
        try
        {
            string native = regPath
                .Replace(@"HKLM:\", @"HKLM\")
                .Replace(@"HKCU:\", @"HKCU\")
                .Replace(@"HKCR:\", @"HKCR\")
                .Replace(@"HKU:\",  @"HKU\")
                .Replace(@"HKCC:\", @"HKCC\");

            int    idx      = _actions.Count(a => a.Type == "reg");
            string safeName = SanitizeFileName(label);
            string file     = $"reg_{idx:D3}_{safeName}.reg";
            string outFile  = Path.Combine(_path, file);

            RunProcess("reg", $"export \"{native}\" \"{outFile}\" /y");
            bool existed = File.Exists(outFile);

            _actions.Add(new BackupAction
            {
                Type    = "reg",
                Label   = label,
                RegPath = regPath,
                Native  = native,
                File    = file,
                Existed = existed,
                Ts      = NowTs()
            });
        }
        catch { }
    }

    public void SaveSvcBackup(string svcName)
    {
        if (_path is null) return;
        try
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
                using var key = Registry.LocalMachine.OpenSubKey(
                    $@"SYSTEM\CurrentControlSet\Services\{svcName}");
                if (key?.GetValue("DelayedAutoStart") is int delayed && delayed == 1)
                    startMode = "AutoDelayed";
            }

            _svcs.Add(new SvcEntry
            {
                Name       = svcName,
                StartMode  = startMode,
                WasRunning = wasRunning,
                Ts         = NowTs()
            });
            _actions.Add(new BackupAction
            {
                Type    = "service",
                Label   = $"Servicio: {svcName}",
                SvcName = svcName,
                Ts      = NowTs()
            });
        }
        catch { }
    }

    public void SaveNetBackup()
    {
        if (_path is null) return;
        try
        {
            var ipv6Map = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using var searcher = new ManagementObjectSearcher(
                    @"ROOT\StandardCimv2",
                    "SELECT Name, Enabled FROM MSFT_NetAdapterBindingSettingData WHERE ComponentID='ms_tcpip6'");
                using ManagementObjectCollection col = searcher.Get();
                foreach (ManagementObject mo in col)
                {
                    string? name    = mo["Name"]?.ToString();
                    bool    enabled = mo["Enabled"] is bool b && b;
                    if (name is not null) ipv6Map[name] = enabled;
                    mo.Dispose();
                }
            }
            catch { }

            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus  != OperationalStatus.Up)          continue;
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;

                IPInterfaceProperties props = ni.GetIPProperties();
                int ifIndex;
                try   { ifIndex = props.GetIPv4Properties().Index; }
                catch { continue; }

                string[] dnsV4 = [.. props.DnsAddresses
                    .Where(a => a.AddressFamily == AddressFamily.InterNetwork)
                    .Select(a => a.ToString())];

                bool ipv6Enabled = ipv6Map.TryGetValue(ni.Name, out bool v) ? v : true;

                _nets.Add(new NetEntry
                {
                    Name        = ni.Name,
                    IfIndex     = ifIndex,
                    DnsServers  = string.Join(",", dnsV4),
                    Ipv6Enabled = ipv6Enabled,
                    Ts          = NowTs()
                });
            }

            if (_nets.Count > 0)
                _actions.Add(new BackupAction
                {
                    Type  = "network",
                    Label = $"Configuracion de red ({_nets.Count} adaptadores)",
                    Ts    = NowTs()
                });
        }
        catch { }
    }

    public void SavePowerPlanBackup()
    {
        if (_path is null) return;
        try
        {
            string output   = RunProcess("powercfg", "/getactivescheme");
            var    match    = Regex.Match(output,
                @"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
                RegexOptions.IgnoreCase);
            string prevGuid = match.Success
                ? match.Value
                : "381b4222-f694-41f0-9685-ff5bb260df2e";

            bool prevHibernate = true;
            using var key = Registry.LocalMachine.OpenSubKey(
                @"SYSTEM\CurrentControlSet\Control\Power");
            if (key?.GetValue("HibernateEnabled") is int hib)
                prevHibernate = hib == 1;

            _actions.Add(new BackupAction
            {
                Type          = "powerplan",
                Label         = "Plan de energia",
                PrevGuid      = prevGuid,
                PrevHibernate = prevHibernate,
                Ts            = NowTs()
            });
        }
        catch { }
    }

    public void SavePageFileBackup()
    {
        if (_path is null) return;
        try
        {
            bool autoManaged = false;
            using var csSearcher = new ManagementObjectSearcher(
                "SELECT AutomaticManagedPagefile FROM Win32_ComputerSystem");
            using (var csCol = csSearcher.Get())
            foreach (ManagementObject mo in csCol)
            {
                autoManaged = mo["AutomaticManagedPagefile"] is bool b && b;
                mo.Dispose();
                break;
            }

            var pageFiles = new List<PageFileEntry>();
            using var pfSearcher = new ManagementObjectSearcher(
                "SELECT Name, InitialSize, MaximumSize FROM Win32_PageFileSetting");
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

            var backup  = new PageFileBackup { AutomaticManaged = autoManaged, PageFiles = pageFiles };
            string outFile = Path.Combine(_path, "pagefile_backup.json");
            File.WriteAllText(outFile,
                JsonSerializer.Serialize(backup, new JsonSerializerOptions { WriteIndented = true }));

            _actions.Add(new BackupAction
            {
                Type  = "pagefile",
                Label = "PageFile (Win32_PageFileSetting)",
                File  = "pagefile_backup.json",
                Ts    = NowTs()
            });
        }
        catch { }
    }

    public void SaveNetshBackup()
    {
        if (_path is null) return;
        try
        {
            string output  = RunProcess("netsh", "int tcp show global");
            string outFile = Path.Combine(_path, "netsh_backup.txt");
            File.WriteAllText(outFile, output);
            _actions.Add(new BackupAction
            {
                Type  = "netsh",
                Label = "TCP global (netsh int tcp show global)",
                File  = "netsh_backup.txt",
                Ts    = NowTs()
            });
        }
        catch { }
    }

    public void SaveSessionMetadata(
        int    freedMb     = 0,
        int    scoreBefore = 0,
        int    scoreAfter  = 0,
        string preset      = "Manual")
    {
        if (_path is null) return;
        try
        {
            var meta = new SessionMetadata
            {
                Version     = App.Version,
                Timestamp   = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                SessionPath = _path,
                Preset      = preset,
                FreedMb     = freedMb,
                ScoreBefore = scoreBefore,
                ScoreAfter  = scoreAfter,
                Actions     = [.._actions],
                Services    = [.._svcs],
                Network     = [.._nets]
            };
            string jsonPath = Path.Combine(_path, "session.json");
            File.WriteAllText(jsonPath,
                JsonSerializer.Serialize(meta, new JsonSerializerOptions { WriteIndented = true }));
            App.Logger?.Log($"Metadata de sesion guardada ({meta.ActionCount} acciones)", "ok");
        }
        catch (Exception ex)
        {
            App.Logger?.Log($"No se pudo guardar metadata: {ex.Message}", "err");
        }
    }

    // ================================================================
    // QUERY — equivalentes a Get-BackupSessions / Cleanup
    // ================================================================

    public List<BackupSessionInfo> GetBackupSessions()
    {
        var sessions = new List<BackupSessionInfo>();
        string root = App.Settings.Current.BackupRoot;
        if (!Directory.Exists(root)) return sessions;
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(root)
                                         .OrderByDescending(d => d))
            {
                string         folderName = Path.GetFileName(dir);
                string         jsonFile   = Path.Combine(dir, "session.json");
                SessionMetadata? meta     = null;
                if (File.Exists(jsonFile))
                    try { meta = JsonSerializer.Deserialize<SessionMetadata>(File.ReadAllText(jsonFile)); }
                    catch { }

                sessions.Add(new BackupSessionInfo
                {
                    Path            = dir,
                    FolderName      = folderName,
                    Timestamp       = meta?.Timestamp ?? folderName.Replace('_', ' '),
                    FreedMb         = meta?.FreedMb    ?? 0,
                    Actions         = meta?.ActionCount ?? 0,
                    Preset          = meta?.Preset      ?? "Desconocido",
                    HasMeta         = meta is not null,
                    Meta            = meta,
                    HasBloatwareRef = File.Exists(Path.Combine(dir, "bloatware_removed.json"))
                });
            }
        }
        catch { }
        return sessions;
    }

    public void CleanupOldBackups(int keepDays = 30)
    {
        string root = App.Settings.Current.BackupRoot;
        if (!Directory.Exists(root)) return;
        try
        {
            DateTime cutoff = DateTime.Now.AddDays(-keepDays);
            foreach (var dir in Directory.EnumerateDirectories(root))
            {
                try
                {
                    if (Directory.GetLastWriteTime(dir) < cutoff)
                        Directory.Delete(dir, recursive: true);
                }
                catch { }
            }
        }
        catch { }
    }

    // ================================================================
    // RESTORE — equivalentes a Restore-* del PS1
    // La funcion principal es RestoreSession; las demas son privadas.
    // ================================================================

    /// <summary>
    /// Orquesta la restauracion completa de una sesion.
    /// Equivalente a Restore-Session del PS1.
    /// </summary>
    public bool RestoreSession(string sessionPath, Action<string, string>? logFn = null)
    {
        Action<string, string> log = logFn ?? ((msg, type) => App.Logger?.Log(msg, type));

        if (!Directory.Exists(sessionPath))
        {
            log($"Sesion no encontrada: {sessionPath}", "err");
            return false;
        }

        string         jsonFile = Path.Combine(sessionPath, "session.json");
        SessionMetadata? meta   = null;
        if (File.Exists(jsonFile))
            try { meta = JsonSerializer.Deserialize<SessionMetadata>(File.ReadAllText(jsonFile)); }
            catch { }

        // Prompt 69 — defensa contra el "exito falso": una carpeta con bloatware_removed.json
        // y sin session.json es un registro de desinstalacion de Bloatware. RestoreSession no
        // reinstala apps. Antes de este guard recorria los 6 pasos en 0/0/0 y terminaba con
        // "Restauracion completada" + return true. El boton por-fila de Historial ya no ofrece
        // "Revertir" para estas sesiones y btnRevertLast las saltea; esto cubre cualquier otro
        // caller que llegue aca en el futuro.
        if (meta is null && File.Exists(Path.Combine(sessionPath, "bloatware_removed.json")))
        {
            log("RESTAURANDO SESION", "head");
            log($"Carpeta: {Path.GetFileName(sessionPath)}", "info");
            log("Es un registro de desinstalacion de Bloatware: WinBoost no reinstala apps, no hay nada que revertir.", "err");
            return false;
        }

        log("RESTAURANDO SESION", "head");
        log($"Carpeta: {Path.GetFileName(sessionPath)}", "info");
        if (meta is not null)
            log($"Sesion del: {meta.Timestamp}  ({meta.ActionCount} acciones)", "info");

        int totalOk = 0, totalFailed = 0;

        // 1) Registro
        log("Restaurando registro...", "info");
        var regResult = RestoreRegFromSession(sessionPath);
        totalOk     += regResult.Ok;
        totalFailed += regResult.Failed;
        log($"Registro: {regResult.Ok} ok  {regResult.Failed} fallidos  {regResult.Skipped} omitidos",
            regResult.Failed > 0 ? "err" : "ok");
        foreach (var inv in regResult.InvalidFiles)
            log($"Archivo .reg invalido o corrupto omitido: {inv}", "err");

        // 2) Servicios
        if (meta?.Services is { Count: > 0 })
        {
            log("Restaurando servicios...", "info");
            var svcResult = RestoreServicesFromSession(meta);
            totalOk     += svcResult.Ok;
            totalFailed += svcResult.Failed;
            log($"Servicios: {svcResult.Ok} ok  {svcResult.Failed} fallidos  {svcResult.Skipped} omitidos",
                svcResult.Failed > 0 ? "err" : "ok");
        }

        // 3) Red
        if (meta?.Network is { Count: > 0 })
        {
            log("Restaurando configuracion de red...", "info");
            var netResult = RestoreNetworkFromSession(meta);
            totalOk     += netResult.Ok;
            totalFailed += netResult.Failed;
            log($"Red: {netResult.Ok} ok  {netResult.Failed} fallidos  {netResult.Skipped} omitidos",
                netResult.Failed > 0 ? "err" : "ok");
            log("Cache DNS limpiada", "ok");
        }

        // 4) HPET / bcdedit
        if (meta?.Actions.Any(a => Regex.IsMatch(a.Label, "HPET|useplatform|dynamictick")) == true)
        {
            log("Restaurando timers del sistema (bcdedit)...", "info");
            RestoreHpetFromSession();
            log("Timers restaurados a defaults de Windows", "ok");
            totalOk++;
        }

        // 5) Plan de energia
        var powerAction = meta?.Actions.FirstOrDefault(a => a.Type == "powerplan");
        if (powerAction is not null)
        {
            try
            {
                string guid = powerAction.PrevGuid ?? "SCHEME_BALANCED";
                RunProcess("powercfg", $"/setactive {guid}");
                log($"Plan de energia restaurado (GUID: {guid})", "ok");
                if (powerAction.PrevHibernate == true)
                {
                    RunProcess("powercfg", "/hibernate on");
                    log("Hibernacion reactivada", "ok");
                }
                totalOk++;
            }
            catch
            {
                log("Error restaurando plan de energia", "err");
                totalFailed++;
            }
        }

        // 6) PageFile
        if (meta?.Actions.Any(a => a.Type == "pagefile") == true)
        {
            log("Restaurando PageFile...", "info");
            var pfResult = RestorePageFileFromSession(sessionPath, log);
            totalOk     += pfResult.Ok;
            totalFailed += pfResult.Failed;
        }

        // 7) TCP global (netsh)
        if (meta?.Actions.Any(a => a.Type == "netsh") == true)
        {
            log("Restaurando TCP global (netsh)...", "info");
            var netshResult = RestoreNetshFromSession(sessionPath, log);
            totalOk     += netshResult.Ok;
            totalFailed += netshResult.Failed;
        }

        string status = totalFailed == 0 ? "ok" : "err";
        log($"Restauracion completada: {totalOk} cambios revertidos, {totalFailed} errores", status);
        log("Reinicia el equipo para que todos los cambios tomen efecto.", "info");

        return totalFailed == 0;
    }

    // ----------------------------------------------------------------
    // Restore helpers (privados)
    // ----------------------------------------------------------------

    private static bool IsRegFileValid(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            if (new FileInfo(path).Length < 10) return false;

            byte[] bytes = File.ReadAllBytes(path);
            Encoding enc = bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE
                ? Encoding.Unicode
                : Encoding.Default;

            string text      = enc.GetString(bytes);
            string firstLine = text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                                   .FirstOrDefault()?.TrimStart('﻿').Trim() ?? "";

            if (firstLine != "Windows Registry Editor Version 5.00" && firstLine != "REGEDIT4")
                return false;
            if (!text.Contains("[HKEY_")) return false;
            return true;
        }
        catch { return false; }
    }

    private static RestoreResult RestoreRegFromSession(string sessionPath)
    {
        var result = new RestoreResult();
        try
        {
            var regFiles = Directory.EnumerateFiles(sessionPath, "reg_*.reg")
                                    .OrderBy(f => f)
                                    .ToList();

            foreach (var file in regFiles)
            {
                if (new FileInfo(file).Length < 5) { result.Skipped++; continue; }
                if (!IsRegFileValid(file))
                {
                    result.Failed++;
                    result.InvalidFiles.Add(Path.GetFileName(file));
                    continue;
                }
                try
                {
                    using var proc = new Process
                    {
                        StartInfo = new ProcessStartInfo("reg.exe", $"import \"{file}\"")
                        {
                            UseShellExecute = false,
                            CreateNoWindow  = true,
                            WindowStyle     = ProcessWindowStyle.Hidden
                        }
                    };
                    proc.Start();
                    proc.WaitForExit(30_000);
                    if (proc.ExitCode == 0) result.Ok++;
                    else                    result.Failed++;
                }
                catch { result.Failed++; }
            }
        }
        catch { result.Failed++; }
        return result;
    }

    private static RestoreResult RestoreServicesFromSession(SessionMetadata meta)
    {
        var result = new RestoreResult();

        var modeMap = new Dictionary<string, ServiceStartMode>(StringComparer.OrdinalIgnoreCase)
        {
            ["Auto"]        = ServiceStartMode.Automatic,
            ["Automatic"]   = ServiceStartMode.Automatic,
            ["AutoDelayed"] = ServiceStartMode.Automatic,
            ["Manual"]      = ServiceStartMode.Manual,
            ["Disabled"]    = ServiceStartMode.Disabled,
            ["Boot"]        = ServiceStartMode.Boot,
            ["System"]      = ServiceStartMode.System
        };

        foreach (var entry in meta.Services)
        {
            try
            {
                using var svc = new ServiceController(entry.Name);
                try { _ = svc.Status; } // throws if service doesn't exist
                catch { result.Skipped++; continue; }

                var startupType = modeMap.TryGetValue(entry.StartMode, out var m)
                    ? m : ServiceStartMode.Manual;

                // ServiceController no expone setter de StartupType — usar registro
                // Valores DWORD: Boot=0, System=1, Automatic=2, Manual=3, Disabled=4
                int startValue = startupType switch
                {
                    ServiceStartMode.Boot      => 0,
                    ServiceStartMode.System    => 1,
                    ServiceStartMode.Automatic => 2,
                    ServiceStartMode.Manual    => 3,
                    ServiceStartMode.Disabled  => 4,
                    _                          => 3
                };
                using (var svcKey = Registry.LocalMachine.OpenSubKey(
                    $@"SYSTEM\CurrentControlSet\Services\{entry.Name}", writable: true))
                {
                    svcKey?.SetValue("Start", startValue, RegistryValueKind.DWord);
                }

                if (entry.StartMode == "AutoDelayed")
                {
                    using var key = Registry.LocalMachine.OpenSubKey(
                        $@"SYSTEM\CurrentControlSet\Services\{entry.Name}", writable: true);
                    key?.SetValue("DelayedAutoStart", 1, RegistryValueKind.DWord);
                }

                if (entry.WasRunning && startupType != ServiceStartMode.Disabled)
                    try { svc.Start(); } catch { }

                result.Ok++;
            }
            catch { result.Failed++; }
        }
        return result;
    }

    private static RestoreResult RestoreNetworkFromSession(SessionMetadata meta)
    {
        var result = new RestoreResult();

        foreach (var entry in meta.Network)
        {
            try
            {
                // Restaurar DNS via WMI Win32_NetworkAdapterConfiguration
                using var dnsSearcher = new ManagementObjectSearcher(
                    $"SELECT * FROM Win32_NetworkAdapterConfiguration WHERE InterfaceIndex={entry.IfIndex}");
                using var dnsCol = dnsSearcher.Get();
                bool foundAdapter = false;
                foreach (ManagementObject mo in dnsCol)
                {
                    foundAdapter = true;
                    if (!string.IsNullOrEmpty(entry.DnsServers))
                    {
                        string[] dnsArr = entry.DnsServers.Split(',', StringSplitOptions.RemoveEmptyEntries);
                        mo.InvokeMethod("SetDNSServerSearchOrder", [dnsArr]);
                    }
                    else
                    {
                        // Sin DNS guardado = estaba en automatico (DHCP). WMI requiere null (no array vacio)
#pragma warning disable CS8625
                        mo.InvokeMethod("SetDNSServerSearchOrder", new object[] { null });
#pragma warning restore CS8625
                    }
                    mo.Dispose();
                }
                if (!foundAdapter) { result.Skipped++; continue; }

                // Restaurar binding IPv6 via MSFT_NetAdapterBindingSettingData
                try
                {
                    string escaped = entry.Name.Replace("'", "\\'");
                    using var ipv6Searcher = new ManagementObjectSearcher(
                        @"ROOT\StandardCimv2",
                        $"SELECT * FROM MSFT_NetAdapterBindingSettingData WHERE ComponentID='ms_tcpip6' AND Name='{escaped}'");
                    using var ipv6Col = ipv6Searcher.Get();
                    foreach (ManagementObject mo in ipv6Col)
                    {
                        bool currentlyEnabled = mo["Enabled"] is bool b && b;
#pragma warning disable CS8625 // InvokeMethod acepta null para metodos sin parametros
                        if (entry.Ipv6Enabled && !currentlyEnabled)
                            mo.InvokeMethod("Enable", null);
                        else if (!entry.Ipv6Enabled && currentlyEnabled)
                            mo.InvokeMethod("Disable", null);
#pragma warning restore CS8625
                        mo.Dispose();
                    }
                }
                catch { }

                result.Ok++;
            }
            catch { result.Failed++; }
        }

        // Flush DNS siempre al restaurar red
        try { RunProcess("ipconfig", "/flushdns"); } catch { }
        return result;
    }

    private static void RestoreHpetFromSession()
    {
        try { RunProcess("bcdedit", "/deletevalue useplatformtick");    } catch { }
        try { RunProcess("bcdedit", "/deletevalue disabledynamictick"); } catch { }
        try { RunProcess("bcdedit", "/deletevalue useplatformclock");   } catch { }
    }

    private static RestoreResult RestorePageFileFromSession(string sessionPath, Action<string, string> log)
    {
        var    result     = new RestoreResult();
        string backupFile = Path.Combine(sessionPath, "pagefile_backup.json");
        if (!File.Exists(backupFile)) return result;
        try
        {
            var backup = JsonSerializer.Deserialize<PageFileBackup>(File.ReadAllText(backupFile));
            if (backup is null) throw new InvalidDataException("pagefile_backup.json vacio o invalido");

            ManagementObject? cs = null;
            try
            {
                using var csSearcher = new ManagementObjectSearcher(
                    "SELECT * FROM Win32_ComputerSystem");
                using var csCol = csSearcher.Get();
                foreach (ManagementObject mo in csCol) { cs = mo; break; }
                if (cs is null) throw new InvalidOperationException("No se pudo obtener Win32_ComputerSystem");

                if (backup.AutomaticManaged)
                {
                    cs["AutomaticManagedPagefile"] = true;
                    cs.Put();
                    log("PageFile: gestion automatica restaurada", "ok");
                }
                else
                {
                    if (cs["AutomaticManagedPagefile"] is bool auto && auto)
                    {
                        cs["AutomaticManagedPagefile"] = false;
                        cs.Put();
                    }

                    // Borrar pagefiles actuales
                    using var delSearcher = new ManagementObjectSearcher("SELECT * FROM Win32_PageFileSetting");
                    using var delCol = delSearcher.Get();
                    foreach (ManagementObject mo in delCol)
                    { try { mo.Delete(); } catch { } mo.Dispose(); }

                    // Recrear desde backup
                    using var cls = new ManagementClass("Win32_PageFileSetting");
                    foreach (var pf in backup.PageFiles)
                    {
                        using var inst = cls.CreateInstance();
                        inst["Name"]        = pf.Name;
                        inst["InitialSize"] = (uint)pf.InitialSize;
                        inst["MaximumSize"] = (uint)pf.MaximumSize;
                        inst.Put();
                    }
                    log($"PageFile: configuracion original restaurada ({backup.PageFiles.Count} entrada(s))", "ok");
                }
                log("Cambio de PageFile efectivo tras reinicio", "info");
                result.Ok = 1;
            }
            finally { cs?.Dispose(); }
        }
        catch (Exception ex)
        {
            log($"Error restaurando PageFile: {ex.Message}", "err");
            result.Failed = 1;
        }
        return result;
    }

    private static RestoreResult RestoreNetshFromSession(string sessionPath, Action<string, string> log)
    {
        var    result     = new RestoreResult();
        string backupFile = Path.Combine(sessionPath, "netsh_backup.txt");
        if (!File.Exists(backupFile)) return result;
        try
        {
            string content = File.ReadAllText(backupFile);
            string tuning  = Match(content, @"Receive Window Auto-Tuning Level\s*:\s*(\S+)", "normal");
            string chimney = Match(content, @"Chimney Offload State\s*:\s*(\S+)",            "disabled");
            string rss     = Match(content, @"Receive-Side Scaling State\s*:\s*(\S+)",       "enabled");
            string fo      = Match(content, @"TCP Fast Open\s*:\s*(\S+)",                    "enabled");

            RunProcess("netsh", $"int tcp set global autotuninglevel={tuning}");
            RunProcess("netsh", $"int tcp set global chimney={chimney}");
            RunProcess("netsh", $"int tcp set global rss={rss}");
            RunProcess("netsh", $"int tcp set global fastopen={fo}");
            log($"TCP global restaurado desde backup (tuning={tuning} rss={rss})", "ok");
            result.Ok = 1;
        }
        catch (Exception ex)
        {
            log($"Error restaurando TCP global: {ex.Message}", "err");
            result.Failed = 1;
        }
        return result;
    }

    // ================================================================
    // Helpers internos
    // ================================================================

    private static string RunProcess(string exe, string args)
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

    private static string Match(string input, string pattern, string fallback)
    {
        var m = Regex.Match(input, pattern, RegexOptions.IgnoreCase);
        return m.Success ? m.Groups[1].Value.ToLowerInvariant() : fallback;
    }

    // Reemplaza el Regex.Replace(label, "[^a-zA-Z0-9_]", "_") que usaba SaveRegBackup
    // (FIX_regex_singlefile.txt): mismo set de chars permitido (ASCII letra/digito/'_'),
    // sin depender de System.Text.RegularExpressions. Ojo: char.IsLetterOrDigit() es
    // Unicode-aware (deja pasar acentos/ñ) y NO es equivalente al regex original --
    // por eso la comparacion es por rango ASCII explicito, no por esa API.
    private static string SanitizeFileName(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (char c in s)
            sb.Append((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
                ? c : '_');
        return sb.ToString();
    }

    private static string NowTs() => DateTime.Now.ToString("HH:mm:ss");
}
