using System.Windows;
using System.Windows.Media;
using Wpf.Ui.Appearance;
using WinBoost.Services;

namespace WinBoost;

public partial class App : Application
{
    internal const  string          Version  = "4.3";
    internal static SettingsService Settings { get; } = new();
    internal static IAppLogger        Logger   { get; set; } = Services.NullLogger.Instance;
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

        // Fundacion WPF-UI: tema oscuro fijo (igual al default actual de la app) + acento de
        // marca #00C8FF. updateAccent:false porque el accent se fija a mano justo abajo — no
        // dejar que ApplicationThemeManager lo pise con el accent de Windows. El swap
        // claro/oscuro propio de WinBoost (SettingsService.ApplyTheme) reconcilia esto en
        // runtime cuando el usuario cambia de tema.
        ApplicationThemeManager.Apply(ApplicationTheme.Dark, Wpf.Ui.Controls.WindowBackdropType.None, updateAccent: false);
        ApplicationAccentColorManager.Apply(
            (Color)ColorConverter.ConvertFromString("#00C8FF"),
            ApplicationTheme.Dark);

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
            int exitCode = await RunSilentAsync(args);
            await Task.Delay(6000);
            Shutdown(exitCode);
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

    private static async Task<int> RunSilentAsync(CliArgs args)
    {
        string logsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".OptimizarPC", "logs");
        string ts      = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string logPath = Path.Combine(logsDir, $"silent_{ts}.log");

        try
        {
            Directory.CreateDirectory(logsDir);
            Logger = new Services.SilentFileLogger(logPath);
            Logger.Log($"WinBoost v{Version} modo silencioso | Preset: {args.Preset}", "head");

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
                    hasSsd:              sysInfo.HasSsd,
                    isLaptop:            sysInfo.IsLaptop,
                    totalRamGb:          sysInfo.TotalRamGb,
                    sysDrive:            sysDrv,
                    dnsIndex:            args.DnsIndex,
                    altDriveForPageFile: null,
                    movePageFileToAlt:   false,
                    ct);
            },
            startMsg: $"Preset {args.Preset} iniciado...",
            doneMsg:  $"Preset {args.Preset} completado");

            if (ok && result is { } res)
            {
                Backup.SaveSessionMetadata((int)Math.Round(res.FreedMb), 0, 0, args.Preset);
                Logger.Log(
                    $"COMPLETADO | Preset:{args.Preset}" +
                    $" | Aplicados:{res.Applied} | Omitidos:{res.Skipped}" +
                    $" | Liberados:{Math.Round(res.FreedMb, 1)} MB", "head");
                ToastService.Show("WinBoost",
                    $"Preset {args.Preset}: {res.Applied} acciones" +
                    (res.FreedMb > 0.1 ? $" · {Math.Round(res.FreedMb, 1)} MB liberados" : ""));
                return 0;
            }
            else
            {
                Logger.Log($"CANCELADO | Preset:{args.Preset}", "err");
                return 1;
            }
        }
        catch (Exception ex)
        {
            try { Logger.Log($"ERROR FATAL | {ex.Message}", "err"); } catch { }
            ToastService.Show("WinBoost", $"Error en modo silencioso: {ex.Message}");
            return 2;
        }
    }
}
