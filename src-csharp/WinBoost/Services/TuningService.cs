using System.Diagnostics;
using System.Management;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace WinBoost.Services;

// Info extendida de componentes (mirror de Get-ExtendedSystemInfo).
internal sealed record ExtendedSystemInfo(
    int CpuCores, int CpuThreads, double CpuCacheMB,
    int RamSpeedMHz, int RamSlots, int RamUsedSlots,
    double GpuVramMB, string GpuName, string GpuDriver);

// Paquete del Driver Store (mirror del PSCustomObject de Parse-PnpUtilOutput).
internal sealed record DriverPackage(
    string PublishedName, string OriginalName, string DriverVersion, string DriverDate);

// ============================================================
// F2.18/F2.19 - TUNING AVANZADO (motor)
// Mirror de los helpers Get/Set del PS1: Win32PrioritySeparation,
// HAGS, politica termica, info extendida y limpieza del Driver Store.
// La UI vive declarativa en el XAML (tab "Tuning Avanzado").
// ============================================================
internal sealed class TuningService
{
    private const string PriorityKeyPs = @"HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl";
    private const string PriorityKey   = @"SYSTEM\CurrentControlSet\Control\PriorityControl";
    private const string GraphicsKeyPs = @"HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers";
    private const string GraphicsKey   = @"SYSTEM\CurrentControlSet\Control\GraphicsDrivers";

    // GUIDs de la politica termica del sistema (subgrupo + ajuste).
    private const string CoolSub     = "54533251-82be-4824-96c1-47b60b740d00";
    private const string CoolSetting = "94d3a615-a899-4ac5-ae2b-e4d8f634367f";

    // ── Scheduler de CPU (Win32PrioritySeparation) ────────────────────────────
    internal int GetWin32PrioritySep()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(PriorityKey);
            return Convert.ToInt32(k?.GetValue("Win32PrioritySeparation") ?? 2);
        }
        catch { return 2; }
    }

    internal void SetWin32PrioritySep(int value)
    {
        EnsureBackupSession();
        App.Backup.SaveRegBackup(PriorityKeyPs, "Win32PrioritySep_backup");
        using var k = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, PriorityKey);
        k?.SetValue("Win32PrioritySeparation", value, RegistryValueKind.DWord);
    }

    // ── HAGS (Hardware-Accelerated GPU Scheduling) ────────────────────────────
    internal bool GetHagsState()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(GraphicsKey);
            return Convert.ToInt32(k?.GetValue("HwSchMode") ?? 0) == 2;
        }
        catch { return false; }
    }

    internal void SetHagsState(bool enable)
    {
        EnsureBackupSession();
        App.Backup.SaveRegBackup(GraphicsKeyPs, "HAGS_backup");
        using var k = RegistryPrivilegeHelper.OpenWritable(RegistryHive.LocalMachine, GraphicsKey);
        k?.SetValue("HwSchMode", enable ? 2 : 1, RegistryValueKind.DWord);
    }

    // ── Politica termica (Cooling Policy) ─────────────────────────────────────
    // -1 = no disponible / plan personalizado, 0 = Pasiva, 1 = Activa.
    internal int GetCoolingPolicyState()
    {
        try
        {
            string raw  = RunCapture("powercfg", $"/query SCHEME_CURRENT {CoolSub} {CoolSetting}");
            string? line = raw.Split('\n')
                .FirstOrDefault(l => l.Contains("Current AC Power Setting Index"));
            if (line != null)
            {
                int idx = line.IndexOf("0x", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                    return Convert.ToInt32(line[(idx + 2)..].Trim(), 16);
            }
        }
        catch { }
        return -1;
    }

    internal bool SetCoolingPolicy(int value) // 0 = Pasiva, 1 = Activa
    {
        try
        {
            RunCapture("powercfg", $"/setacvalueindex SCHEME_CURRENT {CoolSub} {CoolSetting} {value}");
            RunCapture("powercfg", $"/setdcvalueindex SCHEME_CURRENT {CoolSub} {CoolSetting} {value}");
            RunCapture("powercfg", "/setactive SCHEME_CURRENT");
            return true;
        }
        catch { return false; }
    }

    // ── Info extendida de componentes ─────────────────────────────────────────
    internal async Task<ExtendedSystemInfo> GetExtendedInfoAsync() => await Task.Run(() =>
    {
        int cpuCores = 0, cpuThreads = 0; double cpuCacheMb = 0;
        int ramSpeed = 0, ramSlots = 0, ramUsed = 0;
        double gpuVram = 0; string gpuName = "", gpuDriver = "";

        try
        {
            foreach (ManagementObject mo in new ManagementObjectSearcher(
                "SELECT NumberOfCores, NumberOfLogicalProcessors, L3CacheSize FROM Win32_Processor").Get())
            {
                cpuCores   = Convert.ToInt32(mo["NumberOfCores"] ?? 0);
                cpuThreads = Convert.ToInt32(mo["NumberOfLogicalProcessors"] ?? 0);
                cpuCacheMb = Math.Round(Convert.ToDouble(mo["L3CacheSize"] ?? 0) / 1024, 1);
                break;
            }
        }
        catch { }

        try
        {
            var mems = new ManagementObjectSearcher("SELECT Speed FROM Win32_PhysicalMemory")
                .Get().Cast<ManagementObject>().ToList();
            ramUsed = mems.Count;
            if (mems.Count > 0) ramSpeed = Convert.ToInt32(mems[0]["Speed"] ?? 0);
            foreach (ManagementObject mo in new ManagementObjectSearcher(
                "SELECT MemoryDevices FROM Win32_PhysicalMemoryArray").Get())
            {
                ramSlots = Convert.ToInt32(mo["MemoryDevices"] ?? 0);
                break;
            }
        }
        catch { }

        try
        {
            foreach (ManagementObject mo in new ManagementObjectSearcher(
                "SELECT Name, AdapterRAM, DriverVersion FROM Win32_VideoController").Get())
            {
                long ram = Convert.ToInt64(mo["AdapterRAM"] ?? 0);
                if (ram <= 0) continue;
                gpuName   = mo["Name"]?.ToString() ?? "";
                gpuDriver = mo["DriverVersion"]?.ToString() ?? "";

                // BUG heredado: Win32_VideoController.AdapterRAM es un entero de 32 bits
                // CON SIGNO -> cualquier GPU con >4GB reporta ~4GB por overflow (ej. una
                // RX 6700 XT de 12GB). La VRAM real vive en el registro como QWORD de 64
                // bits (HardwareInformation.qwMemorySize). Se prefiere esa; AdapterRAM
                // queda solo como fallback si el registro no la expone.
                long realBytes = GetVramBytesFromRegistry(gpuName);
                gpuVram   = Math.Round((realBytes > 0 ? realBytes : ram) / 1_048_576.0, 0);
                break;
            }
        }
        catch { }

        // Sin controlador con AdapterRAM valido: intentar puramente por registro
        // (toma la GPU con mas VRAM dedicada).
        if (gpuVram <= 0)
        {
            var (regName, regBytes, regDrv) = GetPrimaryGpuFromRegistry();
            if (regBytes > 0)
            {
                gpuVram   = Math.Round(regBytes / 1_048_576.0, 0);
                if (gpuName.Length   == 0) gpuName   = regName;
                if (gpuDriver.Length == 0) gpuDriver = regDrv;
            }
        }

        return new ExtendedSystemInfo(cpuCores, cpuThreads, cpuCacheMb,
            ramSpeed, ramSlots, ramUsed, gpuVram, gpuName, gpuDriver);
    });

    // Clase de dispositivos de pantalla en el registro (GUID fijo de Windows).
    private const string DisplayClassKey =
        @"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}";

    // VRAM real (bytes) desde HardwareInformation.qwMemorySize del subkey cuyo
    // DriverDesc coincide con el nombre de la GPU. Recorre 0000, 0001... por si hay
    // varias GPU. Devuelve 0 si no la encuentra.
    private static long GetVramBytesFromRegistry(string gpuName)
    {
        try
        {
            using var cls = Registry.LocalMachine.OpenSubKey(DisplayClassKey);
            if (cls == null) return 0;
            foreach (string sub in cls.GetSubKeyNames())
            {
                if (sub.Length != 4 || !int.TryParse(sub, out _)) continue;
                using var k = cls.OpenSubKey(sub);
                if (k == null) continue;
                string desc = k.GetValue("DriverDesc")?.ToString() ?? "";
                if (gpuName.Length > 0 && !string.Equals(desc, gpuName, StringComparison.OrdinalIgnoreCase))
                    continue;
                long bytes = ReadQwMemorySize(k);
                if (bytes > 0) return bytes;
            }
        }
        catch { }
        return 0;
    }

    // GPU con mas VRAM dedicada segun el registro (nombre, bytes, driver).
    private static (string Name, long Bytes, string Driver) GetPrimaryGpuFromRegistry()
    {
        string bestName = "", bestDrv = ""; long bestBytes = 0;
        try
        {
            using var cls = Registry.LocalMachine.OpenSubKey(DisplayClassKey);
            if (cls != null)
                foreach (string sub in cls.GetSubKeyNames())
                {
                    if (sub.Length != 4 || !int.TryParse(sub, out _)) continue;
                    using var k = cls.OpenSubKey(sub);
                    if (k == null) continue;
                    long bytes = ReadQwMemorySize(k);
                    if (bytes > bestBytes)
                    {
                        bestBytes = bytes;
                        bestName  = k.GetValue("DriverDesc")?.ToString() ?? "";
                        bestDrv   = k.GetValue("DriverVersion")?.ToString() ?? "";
                    }
                }
        }
        catch { }
        return (bestName, bestBytes, bestDrv);
    }

    // qwMemorySize puede venir como QWORD (long) o Binary de 8 bytes segun el driver.
    private static long ReadQwMemorySize(RegistryKey k)
    {
        try
        {
            object? v = k.GetValue("HardwareInformation.qwMemorySize");
            if (v is long l)       return l;
            if (v is int i)        return i;
            if (v is byte[] b && b.Length >= 8) return BitConverter.ToInt64(b, 0);
        }
        catch { }
        return 0;
    }

    // ── Limpieza del Driver Store (F2.19) ─────────────────────────────────────
    // Mirror de pnputil /enum-drivers + Parse-PnpUtilOutput + Get-ObsoleteDriverPackages.
    internal async Task<IReadOnlyList<DriverPackage>> ScanObsoleteDriversAsync() => await Task.Run(() =>
    {
        string raw = RunCapture("pnputil", "/enum-drivers");
        var all    = ParsePnpUtil(raw);
        return GetObsolete(all);
    });

    private static List<DriverPackage> ParsePnpUtil(string raw)
    {
        var list = new List<DriverPackage>();
        string published = "", original = "", version = "", date = "";

        void Flush()
        {
            if (published.Length > 0)
                list.Add(new DriverPackage(published, original, version, date));
            published = original = version = date = "";
        }

        foreach (string rawLine in raw.Split('\n'))
        {
            string line = rawLine.Trim();
            if (line.Length == 0) { Flush(); continue; }

            // pnputil /enum-drivers se localiza segun el idioma de Windows: en es-ES
            // los campos son "Nombre publicado", "Nombre original", "Versi(o)n del
            // controlador", etc. Matchear ambos idiomas o el scan siempre da vacio.
            // Las etiquetas ASCII se matchean directo; en "Versi.n" el '.' absorbe el
            // acento sin depender de la codificacion con la que se capturo la salida.
            var m = Regex.Match(line, @"^(?:Published Name|Nombre publicado)\s*:\s*(.+)$", RegexOptions.IgnoreCase);
            if (m.Success) { Flush(); published = m.Groups[1].Value.Trim(); continue; }
            if (published.Length == 0) continue;

            if ((m = Regex.Match(line, @"^(?:Original Name|Nombre original)\s*:\s*(.+)$", RegexOptions.IgnoreCase)).Success)
                original = m.Groups[1].Value.Trim();
            else if ((m = Regex.Match(line, @"^(?:Driver Version|Versi.n del controlador)\s*:\s*(.+)$", RegexOptions.IgnoreCase)).Success)
                version = m.Groups[1].Value.Trim();
            else if ((m = Regex.Match(line, @"^(?:Driver Date|Fecha del controlador)\s*:\s*(.+)$", RegexOptions.IgnoreCase)).Success)
                date = m.Groups[1].Value.Trim();
        }
        Flush();
        return list;
    }

    // Agrupa por OriginalName; en grupos con 2+ versiones, todo lo que no sea la
    // mas nueva es obsoleto (mirror de Get-ObsoleteDriverPackages).
    private static List<DriverPackage> GetObsolete(List<DriverPackage> packages)
    {
        var obsolete = new List<DriverPackage>();
        foreach (var grp in packages.GroupBy(p => p.OriginalName, StringComparer.OrdinalIgnoreCase))
        {
            var items = grp.ToList();
            if (items.Count < 2) continue;
            // Ordenar por ranking real (version numerica y luego fecha), NO por string
            // ordinal: el campo de version suele venir como "MM/DD/YYYY V.V.V.V", y
            // comparar eso como texto da resultados incorrectos (ej. "9..." > "10...").
            var sorted = items.OrderByDescending(DriverRank).ToList();
            for (int i = 1; i < sorted.Count; i++) obsolete.Add(sorted[i]);
        }
        return obsolete;
    }

    // Ranking de un paquete: (version numerica, fecha). pnputil combina fecha y
    // version en un mismo campo ("08/21/2025 25.30.0.1"); se extrae la version con
    // puntos y la fecha con barras por separado para comparar de forma confiable.
    private static (Version, DateTime) DriverRank(DriverPackage p)
    {
        string raw = $"{p.DriverVersion} {p.DriverDate}";

        Version ver = new(0, 0, 0, 0);
        var mv = Regex.Match(raw, @"\d+(?:\.\d+){1,3}");        // version (con puntos)
        if (mv.Success && Version.TryParse(mv.Value, out var parsed)) ver = parsed;

        DateTime dt = DateTime.MinValue;
        var md = Regex.Match(raw, @"\d{1,2}/\d{1,2}/\d{4}");    // fecha (con barras)
        if (md.Success)
            DateTime.TryParse(md.Value, System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out dt);

        return (ver, dt);
    }

    // Mirror del btnDriverBackup: Export-WindowsDriver -Online a una carpeta en BACKUP_ROOT.
    internal async Task<string> ExportDriverBackupAsync() => await Task.Run(() =>
    {
        string dir = Path.Combine(App.Settings.Current.BackupRoot,
            "DriverStore_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
        Directory.CreateDirectory(dir);
        RunCapture("powershell",
            $"-NoProfile -NonInteractive -Command \"Export-WindowsDriver -Online -Destination '{dir}' | Out-Null\"");
        return dir;
    });

    // Mirror del btnDriverDelete: pnputil /delete-driver <name> /uninstall. true si exit 0.
    internal async Task<bool> DeleteDriverAsync(string publishedName) => await Task.Run(() =>
    {
        try
        {
            using var p = new Process
            {
                StartInfo = new ProcessStartInfo("pnputil",
                    $"/delete-driver {publishedName} /uninstall")
                { UseShellExecute = false, CreateNoWindow = true,
                  RedirectStandardOutput = true, RedirectStandardError = true }
            };
            p.Start();
            p.StandardOutput.ReadToEnd();
            p.StandardError.ReadToEnd();
            p.WaitForExit(60_000);
            return p.ExitCode == 0;
        }
        catch { return false; }
    });

    // ── Helpers ───────────────────────────────────────────────────────────────
    private static void EnsureBackupSession()
    {
        if (!App.Backup.HasSession) App.Backup.NewBackupSession();
    }

    private static string RunCapture(string exe, string args)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo(exe, args)
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true }
        };
        p.Start();
        string output = p.StandardOutput.ReadToEnd();
        p.WaitForExit(60_000);
        return output;
    }
}
