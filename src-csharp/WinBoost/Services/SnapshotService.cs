using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Management;
using System.ServiceProcess;
using System.Xml.Linq;

namespace WinBoost.Services;

public sealed record StateSnapshot(
    DateTime Timestamp,
    int      CpuIdle,       // porcentaje 0-100 (100-load)
    int      RamFreeMb,
    int      SvcCount,      // servicios en estado Running
    int      Score,         // audit score 0-100; -1 si no calculado
    int      ProcCount,
    long     DiskFreeMb,    // disco del sistema
    int      BootTimeSec);  // -1 si no disponible

public sealed record CompareRow(
    string Label,
    int    Before,
    int    After,
    int    Delta,
    bool   HigherBetter,
    string Status);         // "better" | "neutral" | "worse"

public sealed class SnapshotService
{
    // ── Take ─────────────────────────────────────────────────────────────────

    // score = -1 omite el calculo (caller lo pasa si ya lo tiene)
    public Task<StateSnapshot> TakeSnapshotAsync(int score = -1) =>
        Task.Run(() => TakeSnapshot(score));

    private static StateSnapshot TakeSnapshot(int score)
    {
        int  cpuIdle    = GetCpuIdle();
        int  ramFreeMb  = GetRamFreeMb();
        int  svcCount   = GetRunningServiceCount();
        int  procCount  = GetProcessCount();
        int  bootSec    = GetBootTimeSec();
        long diskFreeMb = GetDiskFreeMb();

        return new StateSnapshot(
            DateTime.Now, cpuIdle, ramFreeMb, svcCount,
            Math.Max(score, 0), procCount, diskFreeMb, bootSec);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Lee CPU load de Win32_Processor (promedio de nucleos) y devuelve 100-load
    private static int GetCpuIdle()
    {
        try
        {
            using var q = new ManagementObjectSearcher("SELECT LoadPercentage FROM Win32_Processor");
            double sum = 0; int n = 0;
            foreach (ManagementObject o in q.Get())
            { sum += Convert.ToDouble(o["LoadPercentage"]); n++; }
            if (n > 0) return (int)Math.Round(100.0 - sum / n);
        }
        catch { }
        return 0;
    }

    // Lee FreePhysicalMemory de Win32_OperatingSystem (en KB) y convierte a MB
    private static int GetRamFreeMb()
    {
        try
        {
            using var q = new ManagementObjectSearcher(
                "SELECT FreePhysicalMemory FROM Win32_OperatingSystem");
            foreach (ManagementObject o in q.Get())
                return (int)(Convert.ToInt64(o["FreePhysicalMemory"]) / 1024);
        }
        catch { }
        return 0;
    }

    // Cuenta servicios en estado Running (equivalente a Get-Service | Where Status Running)
    private static int GetRunningServiceCount()
    {
        try
        {
            return ServiceController.GetServices()
                .Count(s => s.Status == ServiceControllerStatus.Running);
        }
        catch { return 0; }
    }

    // Equivalente a Get-Process (conteo simple)
    private static int GetProcessCount()
    {
        try { return Process.GetProcesses().Length; }
        catch { return 0; }
    }

    // Lee el ultimo evento ID=100 del log de rendimiento de arranque (F0.3 en PS1)
    // y devuelve BootTime en segundos. Retorna -1 si no disponible.
    private static int GetBootTimeSec()
    {
        try
        {
            var query = new EventLogQuery(
                "Microsoft-Windows-Diagnostics-Performance/Operational",
                PathType.LogName,
                "*[System[EventID=100]]");
            using var reader = new EventLogReader(query);
            using var record = reader.ReadEvent();
            if (record == null) return -1;

            var doc = XDocument.Parse(record.ToXml());
            XNamespace ns = "http://schemas.microsoft.com/win/2004/08/events/event";
            var node = doc.Descendants(ns + "Data")
                .FirstOrDefault(n => (string?)n.Attribute("Name") == "BootTime");

            if (node != null && long.TryParse(node.Value, out long ms))
                return (int)(ms / 1000);
        }
        catch { }
        return -1;
    }

    // Espacio libre en disco del sistema en MB (equivalente a $drv.Free / 1MB)
    private static long GetDiskFreeMb()
    {
        try
        {
            string sysDrive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:") + "\\";
            return new System.IO.DriveInfo(sysDrive).AvailableFreeSpace / (1024L * 1024L);
        }
        catch { return 0; }
    }

    // ── Compare ──────────────────────────────────────────────────────────────

    // Mirror exacto de Compare-Snapshots del PS1 (modulo 11B)
    public IReadOnlyList<CompareRow> CompareSnapshots(StateSnapshot before, StateSnapshot after)
    {
        // (Label, selector, higherIsBetter)
        var defs = new (string Label, Func<StateSnapshot, int> Get, bool Higher)[]
        {
            ("Score de salud",          s => s.Score,            true),
            ("CPU libre (%)",           s => s.CpuIdle,          true),
            ("RAM disponible (MB)",     s => s.RamFreeMb,        true),
            ("Disco libre (MB)",        s => (int)s.DiskFreeMb,  true),
            ("Servicios activos",       s => s.SvcCount,         false),
            ("Procesos activos",        s => s.ProcCount,        false),
            ("Tiempo de arranque (s)",  s => s.BootTimeSec,      false),
        };

        var rows = new List<CompareRow>(defs.Length);
        foreach (var (label, get, higher) in defs)
        {
            int bv    = get(before);
            int av    = get(after);
            int delta = av - bv;
            string status = delta == 0 ? "neutral"
                : ((higher && delta > 0) || (!higher && delta < 0)) ? "better" : "worse";
            rows.Add(new CompareRow(label, bv, av, delta, higher, status));
        }
        return rows;
    }
}
