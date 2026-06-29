using System.Diagnostics;

namespace WinBoost.Services;

public sealed record ProcessEntry(
    int    Pid,
    string Name,
    string Description,
    float  CpuPct,
    float  RamMb,
    string Company,
    string Path,
    bool   IsSystem,
    float  SortScore);

public sealed record StopResult(bool Ok, string Message);

public sealed class ProcessService
{
    // Mirror de $script:systemProcessNames del PS1 (módulo 5A)
    public static readonly HashSet<string> SystemProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        // Kernel y subsistemas Windows
        "System","Registry","smss","csrss","wininit","winlogon","lsass",
        "lsaiso","services","svchost","dwm","fontdrvhost","LogonUI","ntoskrnl","hal",
        // Session / seguridad
        "SecurityHealthService","SecurityHealthSystray","MsMpEng",
        "NisSrv","WinDefend","SgrmBroker","wscsvc",
        // Shell y explorer
        "explorer","ShellExperienceHost","StartMenuExperienceHost",
        "SearchIndexer","SearchHost","SearchProtocolHost","SearchFilterHost",
        "RuntimeBroker","ctfmon","TextInputHost",
        // Runtime y frameworks
        "conhost","condrv","dllhost","taskhost","taskhostw",
        "sihost","ApplicationFrameHost","WWAHost","WUDFHost",
        // Hardware / drivers
        "audiodg","WmiPrvSE","WmiApSrv","spoolsv","msdtc",
        "LsaIso","Idle","MemCompression","vmmem",
        // Update y store
        "TiWorker","TrustedInstaller","WaaSMedicAgent","UsoClient",
        "WaasMedic","wuauclt","msiexec","MoUsoCoreWorker",
        // El propio proceso
        "powershell","pwsh","cmd","WinBoost","OptimizarPC",
    };

    // CPU% cache — shared across calls, mirrors $script:_procSample1
    private Dictionary<int, double>? _sample1;
    private DateTime                 _sampleTime1;

    public Task<IReadOnlyList<ProcessEntry>> GetHeavyProcessesAsync(
        int  topN          = 15,
        bool includeSystem = false) => Task.Run(() => GetHeavyProcesses(topN, includeSystem));

    public Task<StopResult> StopProcessAsync(int pid) => Task.Run(() => StopProcess(pid));

    // ── Heavy process sampling (mirror de Get-HeavyProcesses del PS1) ────────

    private IReadOnlyList<ProcessEntry> GetHeavyProcesses(int topN, bool includeSystem)
    {
        // Snapshot actual
        var sample2    = new Dictionary<int, double>();
        var time2      = DateTime.Now;
        var rawProcs   = new List<Process>();

        foreach (var p in Process.GetProcesses())
        {
            try
            {
                sample2[p.Id] = p.TotalProcessorTime.TotalMilliseconds;
                rawProcs.Add(p);
            }
            catch { }
        }

        // Delta con snapshot anterior (primera llamada: elapsed=1ms → CPU=0)
        var    sample1  = _sample1 ?? sample2;
        double elapsed  = _sample1 != null
            ? (time2 - _sampleTime1).TotalMilliseconds
            : 1.0;
        int    cpuCount = Environment.ProcessorCount;

        _sample1     = sample2;
        _sampleTime1 = time2;

        // Calcular CPU% por proceso
        var procs = new List<(int Pid, string Name, float CpuPct, float RamMb, Process Proc)>();
        foreach (var p in rawProcs)
        {
            try
            {
                double cpu2    = sample2[p.Id];
                double cpu1    = sample1.TryGetValue(p.Id, out var v) ? v : cpu2;
                double delta   = cpu2 - cpu1;
                float  cpuPct  = (float)Math.Clamp(
                    Math.Round(delta / Math.Max(elapsed, 1) / cpuCount * 100.0, 1), 0, 100);
                float  ramMb   = (float)Math.Round(p.WorkingSet64 / 1_048_576.0, 1);
                procs.Add((p.Id, p.ProcessName, cpuPct, ramMb, p));
            }
            catch { }
        }

        // Top-N por CPU + Top-N por RAM, combinados y deduplicados (mirror del PS1)
        var byCpu = procs.OrderByDescending(x => x.CpuPct).Take(topN);
        var byRam = procs.OrderByDescending(x => x.RamMb).Take(topN);

        var combined = byCpu.Concat(byRam)
            .OrderByDescending(x => x.CpuPct * 1.5f + x.RamMb / 100f);

        var seen   = new HashSet<int>();
        var result = new List<ProcessEntry>();

        foreach (var p in combined)
        {
            if (!seen.Add(p.Pid)) continue;

            bool isSys = IsSystemProcess(p.Proc);
            if (!includeSystem && isSys) continue;

            var (desc, company, path) = GetProcessDetails(p.Proc);
            float sortScore = (float)Math.Round(p.CpuPct * 1.5f + p.RamMb / 100f, 1);

            result.Add(new ProcessEntry(
                p.Pid, p.Name, desc, p.CpuPct, p.RamMb, company, path, isSys, sortScore));

            if (result.Count >= topN * 2) break;
        }

        return result;
    }

    // Mirror de Test-SystemProcess del PS1
    public static bool IsSystemProcess(Process proc)
    {
        try
        {
            if (SystemProcessNames.Contains(proc.ProcessName)) return true;
            if (proc.Id <= 4) return true;

            string? path = null;
            try { path = proc.MainModule?.FileName; } catch { }

            if (path == null)
                return true;   // sin path = kernel/driver (conservador)

            var lower = path.ToLowerInvariant();
            if (lower.Contains(@"\windows\system32\")  ||
                lower.Contains(@"\windows\syswow64\")   ||
                lower.Contains(@"\windows\systemapps\"))
                return true;

            return false;
        }
        catch { return true; }   // si no se puede leer, asumir sistema
    }

    private static (string Desc, string Company, string Path) GetProcessDetails(Process proc)
    {
        string desc    = "";
        string company = "";
        string path    = "";

        try { path = proc.MainModule?.FileName ?? ""; } catch { }

        if (path != "" && File.Exists(path))
        {
            try
            {
                var fvi    = FileVersionInfo.GetVersionInfo(path);
                desc    = fvi.FileDescription ?? "";
                company = fvi.CompanyName     ?? "";
            }
            catch { }
        }

        return (desc, company, path);
    }

    // ── Stop process (mirror de Stop-ManagedProcess del PS1) ────────────────

    private static StopResult StopProcess(int pid)
    {
        try
        {
            var proc = Process.GetProcessById(pid);
            if (IsSystemProcess(proc))
                return new StopResult(false, "Operacion bloqueada: proceso del sistema");

            string name = proc.ProcessName;
            proc.Kill(entireProcessTree: false);
            return new StopResult(true, $"Proceso '{name}' (PID {pid}) terminado");
        }
        catch (ArgumentException)
        {
            return new StopResult(false, "Proceso no encontrado (ya cerro)");
        }
        catch (Exception ex)
        {
            return new StopResult(false, $"Error: {ex.Message}");
        }
    }
}
