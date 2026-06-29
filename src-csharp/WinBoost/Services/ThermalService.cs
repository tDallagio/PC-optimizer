using System.Management;

namespace WinBoost.Services;

public sealed record CpuThermal(
    bool   Available,
    float  TempC,
    float  TempMax,
    int    ZoneCount,
    string Status);     // "normal" | "warning" | "critical" | "unavailable"

public sealed record GpuThermal(
    bool   Available,
    float  TempC,
    string Source,      // "lhm" | "ohm" | "unavailable"
    string Status);

public sealed record ThermalStatus(
    CpuThermal Cpu,
    GpuThermal Gpu,
    string     OverallStatus);

public sealed class ThermalService
{
    public Task<ThermalStatus> GetThermalStatusAsync() => Task.Run(GetThermalStatus);

    private static ThermalStatus GetThermalStatus()
    {
        var cpu = GetCpuThermal();
        var gpu = GetGpuThermal();

        string overall = "normal";
        if      (cpu.Status == "critical" || gpu.Status == "critical")           overall = "critical";
        else if (cpu.Status == "warning"  || gpu.Status == "warning")            overall = "warning";
        else if (cpu.Status == "unavailable" && gpu.Status == "unavailable")     overall = "unavailable";

        return new ThermalStatus(cpu, gpu, overall);
    }

    // ── CPU ──────────────────────────────────────────────────────────────────

    // Mirror de Get-CPUTemperature del PS1 (modulo 6A).
    // Lee MSAcpi_ThermalZoneTemperature del namespace root\wmi.
    // Conversion: decimos de Kelvin → Celsius = (raw - 2732) / 10
    private static CpuThermal GetCpuThermal()
    {
        var none = new CpuThermal(false, -1, -1, 0, "unavailable");
        try
        {
            var scope   = new ManagementScope(@"\\.\root\wmi");
            var query   = new ObjectQuery(
                "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
            using var s = new ManagementObjectSearcher(scope, query);

            var temps = new List<float>();
            foreach (ManagementObject o in s.Get())
            {
                double raw = Convert.ToDouble(o["CurrentTemperature"]);
                if (raw > 0)
                {
                    float c = (float)Math.Round((raw - 2732) / 10.0, 1);
                    if (c >= 0 && c <= 120) temps.Add(c);
                }
            }

            if (temps.Count == 0) return none;

            float avg    = (float)Math.Round(temps.Average(), 1);
            float max    = temps.Max();
            string status = max >= 85 ? "critical" : max >= 70 ? "warning" : "normal";
            return new CpuThermal(true, avg, max, temps.Count, status);
        }
        catch { return none; }
    }

    // ── GPU ──────────────────────────────────────────────────────────────────

    // Mirror de Get-GPUTemperature del PS1.
    // Intento 1: LibreHardwareMonitor WMI namespace
    // Intento 2: OpenHardwareMonitor WMI namespace
    private static GpuThermal GetGpuThermal()
    {
        var none = new GpuThermal(false, -1, "unavailable", "unavailable");

        var result = TryGpuFromNamespace("root\\LibreHardwareMonitor", "lhm");
        if (result != null) return result;

        result = TryGpuFromNamespace("root\\OpenHardwareMonitor", "ohm");
        if (result != null) return result;

        return none;
    }

    private static GpuThermal? TryGpuFromNamespace(string ns, string source)
    {
        try
        {
            var scope   = new ManagementScope($@"\\.\{ns}");
            var query   = new ObjectQuery("SELECT Value,SensorType,Name FROM Sensor");
            using var s = new ManagementObjectSearcher(scope, query);

            foreach (ManagementObject o in s.Get())
            {
                string stype = o["SensorType"]?.ToString() ?? "";
                string name  = o["Name"]?.ToString()       ?? "";
                if (stype == "Temperature" &&
                    name.Contains("GPU", StringComparison.OrdinalIgnoreCase))
                {
                    float  c      = (float)Math.Round(Convert.ToDouble(o["Value"]), 1);
                    string status = c >= 85 ? "critical" : c >= 70 ? "warning" : "normal";
                    return new GpuThermal(true, c, source, status);
                }
            }
        }
        catch { }
        return null;
    }
}
