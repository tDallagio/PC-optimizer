using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────

public record MaintenanceResult(
    string       Timestamp,
    List<string> Actions,
    double       FreedMb,
    List<string> Errors);

// Resultado de la limpieza profunda de cache (mirror del btnDeepClean del PS1).
public record DeepCleanResult(
    double       IconMb,
    double       WerMb,
    double       LogMb,
    double       ShaderMb,
    double       TotalMb,
    List<string> Errors);

public record MaintenanceTaskInfo(
    bool      Exists,
    bool      Enabled,
    string    State,
    DateTime? LastRun,
    DateTime? NextRun)
{
    public static MaintenanceTaskInfo NotFound() =>
        new(false, false, "NotFound", null, null);
}

// ─────────────────────────────────────────────────────────────────────────────

// Equivalente al modulo 7A del PS1 (motor de tareas programadas).
public sealed class MaintenanceService
{
    // Mismo nombre de tarea que el PS1 para compatibilidad de migracion.
    private const string TaskName = "OptimizarPC_Maintenance";

    private static string BaseDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".OptimizarPC");

    private static string LogPath    => Path.Combine(BaseDir, "maintenance_log.json");
    private static string ScriptPath => Path.Combine(BaseDir, "maintenance.ps1");

    // ── Ciclo de mantenimiento (mirror de Invoke-MaintenanceCycle) ───────────
    // Corre en Task.Run. Limpia segun los flags; el script standalone (tarea
    // programada) siempre limpia todo. TRIM solo si hasSsd.
    public Task<MaintenanceResult> RunCycleAsync(
        bool temp, bool recycle, bool dns, bool trim, bool hasSsd) =>
        Task.Run(() =>
        {
            var actions = new List<string>();
            var errors  = new List<string>();
            double freedMb = 0;

            // Temp usuario
            if (temp)
            {
                try
                {
                    string tmp = Path.GetTempPath();
                    double mb  = GetDirSizeMb(tmp);
                    ClearDirectory(tmp);
                    freedMb += mb;
                    actions.Add($"Temp usuario limpiado ({Math.Round(mb, 1)} MB)");
                }
                catch (Exception ex) { errors.Add($"Temp: {ex.Message}"); }
            }

            // Papelera
            if (recycle)
            {
                try
                {
                    NativeMethods.EmptyRecycleBin();
                    actions.Add("Papelera vaciada");
                }
                catch (Exception ex) { errors.Add($"Recycle: {ex.Message}"); }
            }

            // DNS flush
            if (dns)
            {
                try
                {
                    RunProcess("ipconfig", "/flushdns");
                    actions.Add("DNS flush");
                }
                catch (Exception ex) { errors.Add($"DNS: {ex.Message}"); }
            }

            // TRIM si SSD
            if (trim && hasSsd)
            {
                try
                {
                    string drv = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:")
                        .TrimEnd(':');
                    RunPowerShell(
                        $"Optimize-Volume -DriveLetter {drv} -ReTrim -NormalPriority -ErrorAction SilentlyContinue",
                        120_000);
                    actions.Add($"TRIM ejecutado en {drv}:");
                }
                catch (Exception ex) { errors.Add($"TRIM: {ex.Message}"); }
            }

            var result = new MaintenanceResult(
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                actions, Math.Round(freedMb, 1), errors);

            AppendToLog(result);
            return result;
        });

    // ── Limpieza profunda de cache (mirror del btnDeepClean del PS1) ─────────
    // Detiene Explorer, limpia cache del Explorador (icon/thumb), reportes WER,
    // logs no esenciales (CBS/DISM) y cache de shaders D3D, y reinicia Explorer.
    // Error por paso = se loguea y se continua (nunca frena todo). El reinicio de
    // Explorer va en finally para garantizarlo incluso ante excepcion.
    // Prompt 75: dejo de ser una card propia en Herramientas -- ahora la dispara el checkbox
    // "Cache profunda" de la seccion Limpieza (OptimizationService.CleanupTweaks). El unico
    // await era Task.Delay(1500); pasa a Thread.Sleep para poder esperarla de forma bloqueante
    // desde CleanupTweaks (que ya corre dentro de un Task.Run, sin SynchronizationContext).
    public Task<DeepCleanResult> DeepCleanAsync(Action<string>? progress = null) =>
        Task.Run(() =>
        {
            var errors = new List<string>();
            double iconMb = 0, werMb = 0, logMb = 0, shaderMb = 0;

            string local    = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string winDir   = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string progData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);

            // ── 1. Cache del Explorador (iconcache + thumbcache) ──────────────
            progress?.Invoke("Deteniendo Explorer...");
            try
            {
                foreach (var p in Process.GetProcessesByName("explorer"))
                {
                    try { p.Kill(); } catch { }
                }
                Thread.Sleep(1500);

                string oldIcon = Path.Combine(local, "IconCache.db");
                if (File.Exists(oldIcon))
                {
                    try { iconMb += new FileInfo(oldIcon).Length / (1024.0 * 1024.0); } catch { }
                    try { File.Delete(oldIcon); } catch { }
                }

                string cacheDir = Path.Combine(local, "Microsoft", "Windows", "Explorer");
                if (Directory.Exists(cacheDir))
                {
                    foreach (var f in Directory.EnumerateFiles(cacheDir)
                                 .Where(f => Path.GetFileName(f).StartsWith("iconcache_", StringComparison.OrdinalIgnoreCase)
                                          || Path.GetFileName(f).StartsWith("thumbcache_", StringComparison.OrdinalIgnoreCase)))
                    {
                        try { iconMb += new FileInfo(f).Length / (1024.0 * 1024.0); } catch { }
                        try { File.Delete(f); } catch { }
                    }
                }
            }
            catch (Exception ex) { errors.Add($"Cache Explorer: {ex.Message}"); }
            finally
            {
                // Garantizar reinicio de Explorer aunque algo haya fallado.
                if (Process.GetProcessesByName("explorer").Length == 0)
                {
                    try { Process.Start(new ProcessStartInfo("explorer.exe") { UseShellExecute = true }); }
                    catch { }
                }
            }
            iconMb = Math.Round(iconMb, 1);

            // ── 2. WER — reportes de errores ──────────────────────────────────
            progress?.Invoke("WER...");
            string[] werPaths =
            [
                Path.Combine(local,    "Microsoft", "Windows", "WER", "ReportQueue"),
                Path.Combine(local,    "Microsoft", "Windows", "WER", "ReportArchive"),
                Path.Combine(progData, "Microsoft", "Windows", "WER", "ReportQueue"),
                Path.Combine(progData, "Microsoft", "Windows", "WER", "ReportArchive"),
            ];
            foreach (var p in werPaths)
            {
                if (!Directory.Exists(p)) continue;
                try
                {
                    werMb += GetDirSizeMb(p);
                    ClearDirectory(p);
                }
                catch (Exception ex) { errors.Add($"WER ({Path.GetFileName(p)}): {ex.Message}"); }
            }
            werMb = Math.Round(werMb, 1);

            // ── 3. Logs de Windows (CBS, DISM) ────────────────────────────────
            progress?.Invoke("Logs...");
            string[] logTargets =
            [
                Path.Combine(winDir, "Logs", "CBS"),
                Path.Combine(winDir, "Logs", "DISM"),
            ];
            foreach (var p in logTargets)
            {
                if (!Directory.Exists(p)) continue;
                try
                {
                    logMb += GetDirSizeMb(p);
                    foreach (var f in Directory.EnumerateFiles(p)
                                 .Where(f => f.EndsWith(".log", StringComparison.OrdinalIgnoreCase)
                                          || f.EndsWith(".cab", StringComparison.OrdinalIgnoreCase)))
                    {
                        try { File.Delete(f); } catch { }
                    }
                }
                catch (Exception ex) { errors.Add($"Logs ({Path.GetFileName(p)}): {ex.Message}"); }
            }
            logMb = Math.Round(logMb, 1);

            // ── 4. Cache de shaders Direct3D ──────────────────────────────────
            progress?.Invoke("Shader cache...");
            string[] shaderPaths =
            [
                Path.Combine(local, "D3DSCache"),
                Path.Combine(local, "NVIDIA", "DXCache"),
                Path.Combine(local, "NVIDIA", "GLCache"),
                Path.Combine(local, "AMD",    "DxCache"),
            ];
            foreach (var p in shaderPaths)
            {
                if (!Directory.Exists(p)) continue;
                try
                {
                    shaderMb += GetDirSizeMb(p);
                    ClearDirectory(p);
                }
                catch (Exception ex) { errors.Add($"Shader ({Path.GetFileName(p)}): {ex.Message}"); }
            }
            shaderMb = Math.Round(shaderMb, 1);

            double totalMb = Math.Round(iconMb + werMb + logMb + shaderMb, 1);
            return new DeepCleanResult(iconMb, werMb, logMb, shaderMb, totalMb, errors);
        });

    // ── Estado de la tarea (mirror de Get-MaintenanceTask) ───────────────────
    public Task<MaintenanceTaskInfo> GetTaskAsync() =>
        Task.Run(() =>
        {
            try
            {
                string cmd =
                    $"$t=Get-ScheduledTask -TaskName '{TaskName}' -EA SilentlyContinue; " +
                    "if($t){" +
                    $"$i=Get-ScheduledTaskInfo -TaskName '{TaskName}' -EA SilentlyContinue; " +
                    "$en=$t.State -ne 'Disabled'; " +
                    "$lr=if($i -and $i.LastRunTime -and $i.LastRunTime.Year -gt 2000){$i.LastRunTime.ToString('o')}else{''}; " +
                    "$nr=if($i -and $i.NextRunTime -and $i.NextRunTime.Year -gt 2000){$i.NextRunTime.ToString('o')}else{''}; " +
                    "Write-Output ('EXISTS|'+$en+'|'+$t.State+'|'+$lr+'|'+$nr)" +
                    "} else { Write-Output 'NOTFOUND' }";

                string output = RunPowerShellCapture(cmd, 15_000).Trim();
                if (string.IsNullOrEmpty(output) || output.StartsWith("NOTFOUND"))
                    return MaintenanceTaskInfo.NotFound();

                // La salida puede traer lineas extra; tomar la que empieza con EXISTS
                string line = output
                    .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                    .FirstOrDefault(l => l.TrimStart().StartsWith("EXISTS")) ?? "";
                var parts = line.Trim().Split('|');
                if (parts.Length < 5) return MaintenanceTaskInfo.NotFound();

                bool   enabled = string.Equals(parts[1], "True", StringComparison.OrdinalIgnoreCase);
                string state   = parts[2];
                DateTime? last = ParseRoundTrip(parts[3]);
                DateTime? next = ParseRoundTrip(parts[4]);

                return new MaintenanceTaskInfo(true, enabled, state, last, next);
            }
            catch
            {
                return MaintenanceTaskInfo.NotFound();
            }
        });

    // ── Crear/registrar la tarea (mirror de New-MaintenanceTask) ─────────────
    // Frequency: "Daily" | "Weekly" | "AtStartup". Hour: 0-23.
    public Task<bool> CreateTaskAsync(string frequency, int hour) =>
        Task.Run(() =>
        {
            // 1) Escribir el script standalone de mantenimiento
            try
            {
                Directory.CreateDirectory(BaseDir);
                File.WriteAllText(ScriptPath, MaintScriptContent);
            }
            catch { return false; }

            // 2) Registrar la tarea via PowerShell (escribiendo un script de
            //    registro temporal con -File para evitar problemas de escaping)
            try
            {
                string hourStr = $"{hour:D2}:00";
                string triggerLine = frequency switch
                {
                    "Daily"     => $"$trigger = New-ScheduledTaskTrigger -Daily -At '{hourStr}'",
                    "AtStartup" => "$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME",
                    _           => $"$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '{hourStr}'",
                };

                string regScript =
                    "$ErrorActionPreference='Stop'\r\n" +
                    "try {\r\n" +
                    triggerLine + "\r\n" +
                    "$action = New-ScheduledTaskAction -Execute 'powershell.exe' " +
                    "-Argument '-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File \"" + ScriptPath + "\"'\r\n" +
                    "$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest\r\n" +
                    "$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -StartWhenAvailable -MultipleInstances IgnoreNew\r\n" +
                    "Register-ScheduledTask -TaskName '" + TaskName + "' -Action $action -Trigger $trigger " +
                    "-Principal $principal -Settings $settings -Description 'WinBoost - Mantenimiento automatico' -Force | Out-Null\r\n" +
                    "exit 0\r\n" +
                    "} catch { exit 1 }\r\n";

                string regPath = Path.Combine(BaseDir, "_register_task.ps1");
                File.WriteAllText(regPath, regScript);

                int exit = RunPowerShellFile(regPath, 30_000);
                try { File.Delete(regPath); } catch { }

                return exit == 0;
            }
            catch { return false; }
        });

    // ── Eliminar la tarea (mirror de Remove-MaintenanceTask) ─────────────────
    public Task<bool> RemoveTaskAsync() =>
        Task.Run(() =>
        {
            bool ok = true;
            try
            {
                int exit = RunPowerShell(
                    $"Unregister-ScheduledTask -TaskName '{TaskName}' -Confirm:$false -EA Stop",
                    15_000);
                if (exit != 0) ok = false;
            }
            catch { ok = false; }

            try { if (File.Exists(ScriptPath)) File.Delete(ScriptPath); } catch { }
            return ok;
        });

    // ── Helpers privados ──────────────────────────────────────────────────────

    private static void AppendToLog(MaintenanceResult result)
    {
        try
        {
            Directory.CreateDirectory(BaseDir);
            var history = new List<MaintenanceResult>();
            if (File.Exists(LogPath))
            {
                try
                {
                    var parsed = JsonSerializer.Deserialize<List<MaintenanceResult>>(
                        File.ReadAllText(LogPath));
                    if (parsed != null) history = parsed;
                }
                catch { }
            }
            history.Add(result);
            if (history.Count > 30)
                history = history.Skip(history.Count - 30).ToList();

            File.WriteAllText(LogPath,
                JsonSerializer.Serialize(history,
                    new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    private static double GetDirSizeMb(string path)
    {
        try
        {
            long bytes = 0;
            foreach (var f in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
            {
                try { bytes += new FileInfo(f).Length; } catch { }
            }
            return bytes / (1024.0 * 1024.0);
        }
        catch { return 0; }
    }

    private static void ClearDirectory(string path)
    {
        foreach (var f in Directory.EnumerateFiles(path))
        {
            try { File.Delete(f); } catch { }
        }
        foreach (var d in Directory.EnumerateDirectories(path))
        {
            try { Directory.Delete(d, recursive: true); } catch { }
        }
    }

    private static DateTime? ParseRoundTrip(string s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        return DateTime.TryParse(s, CultureInfo.InvariantCulture,
            DateTimeStyles.RoundtripKind, out var dt) ? dt : null;
    }

    private static void RunProcess(string exe, string args)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo(exe, args)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
            }
        };
        p.Start();
        p.WaitForExit(30_000);
    }

    private static int RunPowerShell(string command, int timeoutMs)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo("powershell",
                $"-NoProfile -NonInteractive -Command \"{command.Replace("\"", "\\\"")}\"")
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
            }
        };
        p.Start();
        p.WaitForExit(timeoutMs);
        return p.ExitCode;
    }

    private static int RunPowerShellFile(string scriptFile, int timeoutMs)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo("powershell",
                $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{scriptFile}\"")
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
            }
        };
        p.Start();
        p.WaitForExit(timeoutMs);
        return p.ExitCode;
    }

    private static string RunPowerShellCapture(string command, int timeoutMs)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo("powershell",
                $"-NoProfile -NonInteractive -Command \"{command.Replace("\"", "\\\"")}\"")
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
            }
        };
        p.Start();
        string output = p.StandardOutput.ReadToEnd();
        p.WaitForExit(timeoutMs);
        return output;
    }

    // Contenido del script standalone de mantenimiento (mirror del here-string
    // del PS1). Limpia todo siempre (sin WPF; corre headless via Task Scheduler).
    private const string MaintScriptContent = @"#Requires -RunAsAdministrator
$HAS_SSD  = $false
$SYSDRIVE = $env:SystemDrive
try {
    if (Get-PhysicalDisk -EA SilentlyContinue |
        Where-Object { $_.MediaType -eq 'SSD' }) { $HAS_SSD = $true }
} catch {}

$logPath = ""$env:USERPROFILE\.OptimizarPC\maintenance_log.json""
$log = @{ timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
          actions=@(); freedMB=0; errors=@() }

try {
    $sz = (Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue |
           Measure-Object -Property Length -Sum).Sum
    if (-not $sz) { $sz = 0 }
    Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue |
        Remove-Item -Recurse -Force -EA SilentlyContinue
    $mb = [math]::Round($sz/1MB,1)
    $log.freedMB += $mb; $log.actions += ""Temp ($mb MB)""
} catch { $log.errors += ""Temp: $_"" }

try { Clear-RecycleBin -Force -EA SilentlyContinue; $log.actions += 'Recycle' } catch { $log.errors += ""Recycle: $_"" }
try { ipconfig /flushdns 2>$null | Out-Null; $log.actions += 'DNS flush' }     catch { $log.errors += ""DNS: $_"" }

if ($HAS_SSD) {
    try {
        $d = $SYSDRIVE.TrimEnd(':')
        Optimize-Volume -DriveLetter $d -ReTrim -NormalPriority -EA SilentlyContinue
        $log.actions += ""TRIM $d""
    } catch { $log.errors += ""TRIM: $_"" }
}

try {
    $hist = @()
    if (Test-Path $logPath) {
        try {
            $raw = Get-Content $logPath -Raw | ConvertFrom-Json
            if ($raw -is [System.Array]) { $hist = $raw } else { $hist = @($raw) }
        } catch {}
    }
    $hist += [PSCustomObject]$log
    if ($hist.Count -gt 30) { $hist = $hist[-30..-1] }
    @($hist) | ConvertTo-Json -Depth 4 | Out-File $logPath -Encoding UTF8
} catch {}
";
}
