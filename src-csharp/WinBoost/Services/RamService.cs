using System.Diagnostics;
using System.Management;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────

public record RamInfo(double TotalGb, double UsedGb, double FreeGb);

public record FreeRamResult(
    double WorkingSetFreedMb,
    double StandbyFreedMb,
    bool   StandbyPurged,
    int    ProcessCount);

// ─────────────────────────────────────────────────────────────────────────────

// Equivalente al modulo "LIBERADOR DE RAM" del PS1 (Standby Purge).
public sealed class RamService
{
    // Mirror de Update-RAMDisplay: total/usado/libre en GB.
    public Task<RamInfo> GetRamInfoAsync() =>
        Task.Run(() =>
        {
            try
            {
                using var searcher = new ManagementObjectSearcher(
                    "SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem");
                foreach (var mo in searcher.Get())
                {
                    double totalKb = Convert.ToDouble(mo["TotalVisibleMemorySize"]);
                    double freeKb  = Convert.ToDouble(mo["FreePhysicalMemory"]);
                    double totalGb = Math.Round(totalKb / 1048576.0, 1);
                    double freeGb  = Math.Round(freeKb  / 1048576.0, 1);
                    double usedGb  = Math.Round((totalKb - freeKb) / 1048576.0, 1);
                    return new RamInfo(totalGb, usedGb, freeGb);
                }
            }
            catch { }
            return new RamInfo(0, 0, 0);
        });

    // Mirror del Add_Click de btnFreeRAM del PS1.
    // Paso 1: EmptyWorkingSet en todos los procesos accesibles.
    // Paso 2: purga de Standby List (requiere admin), midiendo con PerformanceCounter.
    public async Task<FreeRamResult> FreeRamAsync()
    {
        double freeBeforeKb = await Task.Run(GetFreePhysicalKb);

        // Paso 1: EmptyWorkingSet en todos los procesos accesibles
        int count = await Task.Run(EmptyAllWorkingSets);

        double freeAfterWsKb  = await Task.Run(GetFreePhysicalKb);
        double workingSetMb   = Math.Round((freeAfterWsKb - freeBeforeKb) / 1024.0, 0);

        // Paso 2: purgar Standby List y medir delta con PerformanceCounter
        double standbyMb     = 0;
        bool   standbyPurged = false;
        try
        {
            using var pcFree = new PerformanceCounter("Memory", "Free & Zero Page List Bytes");
            pcFree.NextValue();
            await Task.Delay(150);
            float freeBytesBefore = pcFree.NextValue();

            bool purgeOk = await Task.Run(PurgeStandby);
            if (purgeOk)
            {
                standbyPurged = true;
                await Task.Delay(1000);
                float freeBytesAfter = pcFree.NextValue();
                standbyMb = Math.Max(0, Math.Round(
                    (freeBytesAfter - freeBytesBefore) / (1024.0 * 1024.0), 0));
            }
        }
        catch { }

        return new FreeRamResult(workingSetMb, standbyMb, standbyPurged, count);
    }

    // ── Helpers privados ──────────────────────────────────────────────────────

    private static double GetFreePhysicalKb()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT FreePhysicalMemory FROM Win32_OperatingSystem");
            foreach (var mo in searcher.Get())
                return Convert.ToDouble(mo["FreePhysicalMemory"]);
        }
        catch { }
        return 0;
    }

    private static int EmptyAllWorkingSets()
    {
        int count = 0;
        foreach (var proc in Process.GetProcesses())
        {
            try
            {
                if (NativeMethods.EmptyWorkingSet(proc.Handle)) count++;
            }
            catch { }
            finally { proc.Dispose(); }
        }
        return count;
    }

    // Mirror de Invoke-StandbyListPurge: NTSTATUS 0 = exito.
    private static bool PurgeStandby()
    {
        try
        {
            NativeMethods.EnablePrivilege("SeProfileSingleProcessPrivilege");
            uint ntstatus = NativeMethods.PurgeStandbyList();
            if (ntstatus != 0)
                App.Logger.Log($"Standby purge NTSTATUS: 0x{ntstatus:X8}", "skip");
            return ntstatus == 0;
        }
        catch { return false; }
    }
}
