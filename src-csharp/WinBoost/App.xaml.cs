using System.Windows;
using WinBoost.Services;

namespace WinBoost;

public partial class App : Application
{
    internal const  string          Version  = "4.1";
    internal static SettingsService Settings { get; } = new();
    internal static AppLogger       Logger   { get; set; } = null!;
    internal static ProgressService Progress { get; set; } = null!;
    internal static WorkRunner      Worker   { get; } = new();
    internal static BackupService       Backup     { get; } = new();
    internal static SystemInfoService  SystemInfo  { get; } = new();
    internal static SnapshotService    Snapshots   { get; } = new();
    internal static ThermalService     Thermal     { get; } = new();
    internal static ProcessService     Processes   { get; } = new();
    internal static DeviceService      Devices     { get; } = new();
    internal static OptimizationService Optimizer  { get; } = new();
    internal static BloatwareService    Bloatware  { get; } = new();
    internal static StartupService      StartupMgr { get; } = new();
    internal static MaintenanceService  Maintenance{ get; } = new();
    internal static GameFocusService    GameFocus  { get; } = new();
    internal static RamService          Ram        { get; } = new();
    internal static HistoryService      History    { get; } = new();
    internal static ReportService       Report     { get; } = new();
    internal static LicenseService      License    { get; } = new();
    internal static UpdateService       Updater    { get; } = new();
    internal static TuningService       Tuning     { get; } = new();
    // Captura tomada justo antes de optimizar (FASE 3 la escribe, FASE 4+ la lee)
    internal static StateSnapshot?     SnapshotBefore { get; set; }

    // ── Startup ───────────────────────────────────────────────────────────────

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var args = CliArgs.Parse(e.Args);

        if (args.ShowHelp)
        {
            System.Windows.MessageBox.Show(CliArgs.UsageText, "WinBoost — Ayuda",
                MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown(0);
            return;
        }

        if (args.Silent)
        {
            await RunSilentAsync(args);
            // Pequeña espera para que el toast sea visible antes de salir
            await Task.Delay(6000);
            Shutdown(0);
        }
        else
        {
            ShutdownMode = ShutdownMode.OnMainWindowClose;
            Settings.Load();
            var win = new MainWindow();
            MainWindow = win;
            win.Show();
        }
    }

    // ── Modo silencioso (3.5) ─────────────────────────────────────────────────

    private static async Task RunSilentAsync(CliArgs args)
    {
        string logPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".OptimizarPC", "silent_run.log");

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
            Settings.Load();
            Backup.NewBackupSession();

            var sel     = Services.OptimizationService.GetPreset(args.Preset);
            var sysInfo = await SystemInfo.GetSystemInfoAsync();
            string sysDrv = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:") + @"\";

            OptResult? result = null;
            bool ok = await Worker.RunAsync(async ct =>
            {
                var svc = new Services.OptimizationService();
                result = await svc.RunAsync(
                    sel,
                    hasSsd:   sysInfo.HasSsd,
                    isLaptop: sysInfo.IsLaptop,
                    totalRamGb: sysInfo.TotalRamGb,
                    sysDrive:   sysDrv,
                    dnsIndex:   args.DnsIndex,
                    altDriveForPageFile: null,
                    movePageFileToAlt:   false,
                    ct);
            },
            startMsg: $"[Silent] Preset {args.Preset} iniciado...",
            doneMsg:  $"[Silent] Preset {args.Preset} completado");

            if (ok && result is { } res)
            {
                Backup.SaveSessionMetadata(
                    (int)Math.Round(res.FreedMb), 0, 0, args.Preset);

                string line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] OK" +
                              $" | Preset:{args.Preset}" +
                              $" | Applied:{res.Applied}" +
                              $" | Skipped:{res.Skipped}" +
                              $" | Freed:{Math.Round(res.FreedMb, 1)} MB";
                File.AppendAllText(logPath, line + Environment.NewLine);

                string toastMsg = $"Preset {args.Preset}: {res.Applied} acciones" +
                    (res.FreedMb > 0.1 ? $" · {Math.Round(res.FreedMb, 1)} MB liberados" : "");
                ToastService.Show("WinBoost", toastMsg);
            }
            else
            {
                string line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] CANCELADO | Preset:{args.Preset}";
                File.AppendAllText(logPath, line + Environment.NewLine);
            }
        }
        catch (Exception ex)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
                string line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] ERROR | {ex.Message}";
                File.AppendAllText(logPath, line + Environment.NewLine);
            }
            catch { }
            ToastService.Show("WinBoost", $"Error en modo silencioso: {ex.Message}");
        }
    }
}
