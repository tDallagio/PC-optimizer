using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using WinBoost.Services;
using AuditResult   = WinBoost.Services.AuditResult;
using StateSnapshot = WinBoost.Services.StateSnapshot;
using ThermalStatus = WinBoost.Services.ThermalStatus;
using ProcessEntry   = WinBoost.Services.ProcessEntry;
using ProblemDevice  = WinBoost.Services.ProblemDevice;
using DetectedApp    = WinBoost.Services.DetectedApp;
using BackupSessionInfo = WinBoost.Services.BackupSessionInfo;

namespace WinBoost;

public partial class MainWindow : Wpf.Ui.Controls.FluentWindow
{
    private readonly DispatcherTimer _monitorTimer = new() { Interval = TimeSpan.FromSeconds(1) };

    private long _prevIdle, _prevKernel, _prevUser;
    private bool _firstCpuRead = true;
    private NativeMethods.MEMORYSTATUSEX _memStatus;
    private PerformanceCounter? _diskCounter;

    private AuditResult? _lastAuditResult;

    // Thermal (2.3): ticker cada 5 ticks (~5s), guard de lectura concurrente
    private int  _thermalTick    = 0;
    private bool _thermalReading = false;


    // Procesos (2.4): timer de auto-refresh + guard de lectura concurrente
    private DispatcherTimer? _procTimer;
    private bool             _procTimerRunning  = false;
    private bool             _procRefreshing    = false;
    private bool             _procLoaded        = false;  // carga lazy al entrar a Herramientas
    private const int        ProcTimerIntervalSec = 3;

    // Optimizacion (3.1): cache del system info + score previo
    private SystemSnapshot?  _systemInfo;
    private int              _scoreBefore;

    // Bloatware (4.1): cache de la lista detectada + checks por indice
    private IReadOnlyList<DetectedApp>? _bloatList;
    private readonly Dictionary<int, CheckBox> _bloatChecks = [];
    private bool _bloatLoaded = false;   // carga lazy: escanea al entrar a la tab la 1ra vez

    // Startup manager (4.2): cache de la lista de items de arranque
    private IReadOnlyList<StartupItem>? _startupItems;
    private bool _startupLoaded = false;

    // Historial (4.6): flag de carga lazy
    private bool _historyLoaded = false;

    // Ajustes (BUG 3): flag de carga lazy del calculo de tamano de backups
    private bool _settingsLoaded = false;

    // Toast in-app (BUG 6): timer unico reutilizable que oculta el toast; se
    // reinicia con cada nuevo toast para que no queden colgados.
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(4) };

    // Onboarding (5.2): evita relanzar el wizard mas de una vez por sesion
    private bool _onboardingChecked = false;

    // Info de componentes (tab Info): cache de la info extendida (WMI) leida una vez
    private ExtendedSystemInfo? _extendedInfo;

    // Tuning Avanzado (6.1): carga lazy + estado del Driver Store
    private bool _tuningLoaded = false;
    // true mientras se setea IsChecked de los ToggleSwitch por codigo (init o revert tras error):
    // los handlers Checked/Unchecked lo chequean primero para no auto-aplicar el tweak (16B).
    private bool _tuningSyncing = false;
    private IReadOnlyList<DriverPackage> _driverPackages = [];
    private readonly List<CheckBox> _driverChecks = [];
    private bool _driverBackupDone = false;

    // Reporte HTML (4.7): estado de la ultima optimizacion para el reporte
    private double                _lastFreedMb;
    private StateSnapshot?        _snapshotAfter;
    private IReadOnlyList<string> _lastReportActions = [];

    private static readonly string _optProfilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "opt_profile.json");

    private static readonly SolidColorBrush BrushGreen  = FreezeBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
    private static readonly SolidColorBrush BrushYellow = FreezeBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
    private static readonly SolidColorBrush BrushRed    = FreezeBrush(Color.FromRgb(0xEF, 0x44, 0x44));
    private static readonly SolidColorBrush BrushBlue   = FreezeBrush(Color.FromRgb(0x00, 0xC8, 0xFF));
    private static readonly SolidColorBrush BrushGray   = FreezeBrush(Color.FromRgb(0x55, 0x55, 0x55));

    // Licencias (5.1): brushes congelados del modulo 12C (brLicFree + fondos del banner trial)
    private static readonly SolidColorBrush BrushLicFree = FreezeBrush(Color.FromRgb(0x88, 0x88, 0x88));
    private static readonly SolidColorBrush BrushTrialBg = FreezeBrush(Color.FromRgb(0x1A, 0x12, 0x00));
    private static readonly SolidColorBrush BrushTrialBd = FreezeBrush(Color.FromRgb(0x3A, 0x28, 0x00));
    private static readonly SolidColorBrush BrushExpBg   = FreezeBrush(Color.FromRgb(0x1A, 0x0A, 0x0A));
    private static readonly SolidColorBrush BrushExpBd   = FreezeBrush(Color.FromRgb(0x3A, 0x15, 0x15));

    // Tuning (6.1): colores de las filas del Driver Store
    private static readonly SolidColorBrush BrushRowBg     = FreezeBrush(Color.FromRgb(0x11, 0x11, 0x11));
    private static readonly SolidColorBrush BrushDriverName = FreezeBrush(Color.FromRgb(0xDD, 0xDD, 0xDD));
    private static readonly SolidColorBrush BrushDriverDate = FreezeBrush(Color.FromRgb(0x66, 0x66, 0x66));

    // nav buttons indexed 0-9 (navTuning = index 9, Tuning Avanzado)
    private Button[] _navButtons = [];

    public MainWindow()
    {
        InitializeComponent();
        _memStatus.dwLength = NativeMethods.MemoryStatusExSize;
        Loaded += OnLoaded;
        StateChanged += OnStateChanged;
    }

    // Ventana de tamano fijo: ResizeMode=CanMinimize ya saca WS_MAXIMIZEBOX y WS_THICKFRAME, lo
    // que tapa los caminos de usuario (borde arrastrable, Win+flecha arriba, snap al borde
    // superior, Maximizar del menu de sistema y del click derecho en la taskbar), y la TitleBar
    // va con ShowMaximize/CanMaximize en False. Lo que NINGUNO de esos tapa es el maximizado por
    // codigo: verificado que con CanMinimize un WindowState=Maximized (o un WM_SYSCOMMAND
    // SC_MAXIMIZE) igual agranda la ventana a pantalla completa. Este guard es el cierre final:
    // si algo la maximiza, vuelve a Normal. Solo mira Maximized, asi que no interfiere con
    // minimizar.
    private void OnStateChanged(object? sender, EventArgs e)
    {
        if (WindowState == WindowState.Maximized)
            WindowState = WindowState.Normal;
    }

    private static SolidColorBrush FreezeBrush(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _navButtons =
        [
            navOptimizar,    // 0
            navHerramientas, // 1
            navInfo,         // 2
            navArranque,     // 3
            navBloatware,    // 4
            navConsola,      // 5
            navHistorial,    // 6
            navAjustes,      // 7
            navLicencia,     // 8
            navTuning,       // 9
        ];

        navOptimizar.Click    += (_, _) => SetActiveNav(0);
        navHerramientas.Click += (_, _) => SetActiveNav(1);
        navInfo.Click         += (_, _) => SetActiveNav(2);
        navArranque.Click     += (_, _) => SetActiveNav(3);
        navBloatware.Click    += (_, _) => SetActiveNav(4);
        navConsola.Click      += (_, _) => SetActiveNav(5);
        navHistorial.Click    += (_, _) => SetActiveNav(6);
        navAjustes.Click      += (_, _) => SetActiveNav(7);
        navLicencia.Click     += (_, _) => SetActiveNav(8);
        navTuning.Click       += (_, _) => SetActiveNav(9);

        App.Settings.Load();
        App.Settings.Apply(this);

        App.Logger   = new AppLogger(rtbLog, logScroll, btnErrBadge, lblErrCount);
        App.Progress = new ProgressService(progressBar, lblProgress, lblPct);

        // Badge de errores -> abre la Consola (indice 5 en el orden nuevo)
        btnErrBadge.Click += (_, _) => SetActiveNav(5);
        // Consola: limpiar el log visible (mirror del btnClearLog del PS1)
        btnClearLog.Click += (_, _) =>
        {
            rtbLog.Document.Blocks.Clear();
            lblLogStatus.Text = "Log limpiado";
        };
        // Consola: exportar el log a .txt (mirror del btnExportLog del PS1)
        btnExportLog.Click += (_, _) => ExportConsoleLog();

        try { _diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total"); }
        catch { }

        _monitorTimer.Tick += OnMonitorTick;
        _monitorTimer.Start();

        mainTabs.SelectionChanged += OnMainTabsSelectionChanged;
        scoreWidget.MouseLeftButtonUp += (_, _) => SetActiveNav(2);
        btnRecalcScore.Click += async (_, _) => await RecalcScoreAsync();

        // Procesos (2.4)
        btnRefreshProcs.Click     += async (_, _) => await RefreshProcessListAsync();
        btnToggleProcTimer.Click  += (_, _) => ToggleProcTimer();
        chkShowSysProcs.Click     += async (_, _) => await RefreshProcessListAsync();

        // Optimizacion (3.1)
        btnPresetGaming.Click += (_, _) => ApplyPreset("Gaming");
        btnPresetProd.Click   += (_, _) => ApplyPreset("Prod");
        btnPresetSafe.Click   += (_, _) => ApplyPreset("Safe");
        btnSaveProfile.Click  += (_, _) => SaveProfile();
        btnSelAll.Click       += (_, _) => SelectAll(true);
        btnSelNone.Click      += (_, _) => SelectAll(false);
        chkDNS.Click          += (_, _) => UpdatePlanSummary();
        cboDNSProvider.SelectionChanged += (_, _) => UpdatePlanSummary();
        btnRun.Click          += async (_, _) => await OnRunOptimizationAsync();
        btnCancelOpt.Click    += (_, _) => App.Worker.Cancel();
        // Wire todos los checkboxes para actualizar resumen en tiempo real (3.2)
        foreach (var (_, cb) in AllOptCheckboxes())
            cb.Click += (_, _) => UpdatePlanSummary();
        cboDNSProvider.SelectedIndex = 0;
        LoadProfile(); // llama UpdatePlanSummary al final

        // Dispositivos con problemas (2.5)
        btnScanDevices.Click    += async (_, _) => await ScanDevicesAsync();
        btnOpenDevMgmt.Click    += (_, _) =>
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("devmgmt.msc") { UseShellExecute = true });

        // Bloatware (4.1)
        btnScanBloat.Click    += async (_, _) => await ScanBloatwareAsync();
        btnRemoveBloat.Click  += async (_, _) => await InvokeRemoveBloatAsync();
        btnBloatSelAll.Click  += (_, _) => BloatSelectSafe();
        btnBloatSelNone.Click += (_, _) => BloatSelectNone();
        cboBloatFilter.SelectionChanged += OnBloatFilterChanged;

        // Startup manager (4.2)
        btnRefreshStartup.Click += async (_, _) => await RefreshStartupAsync();

        // Mantenimiento (4.3)
        for (int h = 0; h <= 23; h++)
            cboMaintHour.Items.Add(new ComboBoxItem { Content = $"{h:D2}:00" });
        cboMaintHour.SelectedIndex = 10;
        cboMaintFreq.SelectionChanged += (_, _) =>
            cboMaintHour.IsEnabled = cboMaintFreq.SelectedIndex != 2;
        tglMaintenance.Click   += async (_, _) => await ToggleMaintenanceAsync();
        btnRunMaintNow.Click   += async (_, _) => await RunMaintenanceNowAsync();
        _ = UpdateMaintUIAsync();

        // Limpieza profunda de cache (Herramientas)
        btnDeepClean.Click += async (_, _) => await DeepCleanAsync();

        // Liberador de RAM (4.5) — los labels RAM los mantiene el monitor (1s);
        // solo cableamos el boton de purga.
        btnFreeRAM.Click += async (_, _) => await FreeRamAsync();

        // Historial + score history (4.6)
        btnRefreshHistory.Click   += async (_, _) => await RefreshHistoryAsync();
        btnOpenBackupFolder.Click += (_, _) => OpenBackupFolder();
        btnRevertLast.Click       += async (_, _) => await RevertLastSessionAsync();

        // Reporte HTML (4.7)
        btnExportHTML.Click += async (_, _) => await ExportHtmlReportAsync();

        // Licencias + trial (5.1, modulo 12C)
        btnCopyHWID.Click        += (_, _) => CopyHardwareId();
        btnActivateLicense.Click += (_, _) => ActivateLicense();
        btnGetLicense.Click      += (_, _) => GetLicense();
        btnTrialUpgrade.Click    += (_, _) => SetActiveNav(8);
        _ = InitLicenseAsync();

        // Auto-updater (5.3, modulo 14)
        Title             = $"WinBoost v{App.Version}";
        lblVersion.Text   = $"v{App.Version}";
        lblVersionAbout.Text = $"v{App.Version}";
        badgeUpdate.MouseLeftButtonUp += (_, _) => OnUpdateBadgeClick();
        btnCheckUpdatesSettings.Click += async (_, _) => await CheckForUpdatesAsync(manual: true);
        _ = CheckForUpdatesAsync(manual: false);

        // Tuning Avanzado (6.1, modulo F2.18/F2.19) — 3 ui:ToggleSwitch (16B, ex pares de
        // botones Activar/Desactivar). Wpf.Ui.Controls.ToggleSwitch hereda de ToggleButton:
        // no tiene IsOn/Toggled (API de WinUI), se cablea con IsChecked + Checked/Unchecked.
        // _tuningSyncing evita que el set programatico de IsChecked (carga inicial o revert
        // tras error) dispare el Set* real — ver Update*Ui, que es quien lo prende/apaga.
        swPrio.Checked   += (_, _) => { if (!_tuningSyncing) SetPrio(true); };
        swPrio.Unchecked += (_, _) => { if (!_tuningSyncing) SetPrio(false); };
        swHags.Checked   += (_, _) => { if (!_tuningSyncing) SetHags(true); };
        swHags.Unchecked += (_, _) => { if (!_tuningSyncing) SetHags(false); };
        swCool.Checked   += async (_, _) => { if (!_tuningSyncing) await SetCoolingPolicyAsync(1); };
        swCool.Unchecked += async (_, _) => { if (!_tuningSyncing) await SetCoolingPolicyAsync(0); };
        btnScanDrvStore.Click += async (_, _) => await ScanObsoleteDriversAsync();
        btnDriverBackup.Click += async (_, _) => await ExportDriverBackupAsync();
        btnDriverDelete.Click += async (_, _) => await DeleteSelectedDriversAsync();

        // Ajustes: tema + seccion de mantenimiento/backup (BUG 3 y 4)
        WireSettingsControls();

        // Toast in-app (BUG 6): al vencer el timer, oculta el toast
        _toastTimer.Tick += (_, _) => { _toastTimer.Stop(); toastHost.Visibility = Visibility.Collapsed; };

        SetActiveNav(0);
        App.Logger.Log("WinBoost iniciado", "head");

        _ = LoadSystemInfoAsync();
    }

    // ── Toast in-app (BUG 6, mirror de Show-ToastNotification) ────────────────
    // Muestra el toast y (re)arranca el timer de auto-hide. Si aparece otro toast
    // antes de que venza, el Stop()+Start() reinicia la cuenta: no quedan colgados.
    private void ShowToast(string message)
    {
        void Run()
        {
            toastText.Text        = message;
            toastHost.Visibility  = Visibility.Visible;
            _toastTimer.Stop();
            _toastTimer.Start();
        }
        if (Dispatcher.CheckAccess()) Run();
        else Dispatcher.BeginInvoke(Run);
    }

    // ── Ajustes: tema + mantenimiento/backup (BUG 3 y 4) ──────────────────────
    // El tab Ajustes en C# habia quedado sin cablear: el combo de tema no hacia
    // nada, la ruta de backups estaba vacia y el tamano se colgaba en "Calculando...".
    private void WireSettingsControls()
    {
        // --- Tema: dark-only, selector fijo en "Oscuro" y deshabilitado (XAML) ---
        // WinBoost no tiene rama light/auto (decision de producto, ver CHANGELOG.md);
        // sin handler porque el combo no puede disparar cambios (IsEnabled="False").

        // --- Ruta de sesiones de backup (BUG 3) ---
        lblBackupPath.Text = App.Settings.Current.BackupRoot;

        // --- Retencion de backups (BUG 3) ---
        cboBackupRetention.SelectedIndex = App.Settings.Current.BackupRetainDays switch
        {
            7  => 0,
            14 => 1,
            30 => 2,
            60 => 3,
            0  => 4,   // Ilimitado
            _  => 2,
        };
        cboBackupRetention.SelectionChanged += (_, _) =>
        {
            App.Settings.Current.BackupRetainDays = cboBackupRetention.SelectedIndex switch
            {
                0 => 7,
                1 => 14,
                2 => 30,
                3 => 60,
                4 => 0,   // Ilimitado
                _ => 30,
            };
            App.Settings.Save();
        };

        // --- Abrir carpeta de backups (BUG 3) ---
        btnOpenBackups.Click += (_, _) => OpenBackupRootFolder();

        // --- Cambiar ruta de backups ---
        btnChangeBackupPath.Click += (_, _) =>
        {
            try
            {
                var dlg = new Microsoft.Win32.OpenFolderDialog
                {
                    Title = "Elegir carpeta de backups",
                    InitialDirectory = Directory.Exists(App.Settings.Current.BackupRoot)
                        ? App.Settings.Current.BackupRoot
                        : AppSettings.DefaultBackupRoot,
                };
                if (dlg.ShowDialog(this) == true && !string.IsNullOrWhiteSpace(dlg.FolderName))
                {
                    App.Settings.Current.BackupRoot = dlg.FolderName;
                    App.Settings.Save();
                    lblBackupPath.Text = dlg.FolderName;
                    _settingsLoaded = false;   // recalcular tamano con la nueva ruta
                    _ = LoadBackupInfoAsync();
                }
            }
            catch (Exception ex) { App.Logger.Log($"No se pudo cambiar la ruta de backups: {ex.Message}", "err"); }
        };
    }

    // Abre la carpeta raiz de backups en el Explorador (creandola si no existe).
    private void OpenBackupRootFolder()
    {
        try
        {
            string root = App.Settings.Current.BackupRoot;
            Directory.CreateDirectory(root);
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(root)
            { UseShellExecute = true });
        }
        catch (Exception ex) { App.Logger.Log($"No se pudo abrir la carpeta de backups: {ex.Message}", "err"); }
    }

    // Calcula tamano + conteo de sesiones de la carpeta de backups fuera del hilo UI
    // (BUG 3: antes se quedaba en "Calculando..." porque nunca se disparaba el calculo).
    private async Task LoadBackupInfoAsync()
    {
        if (_settingsLoaded) return;
        _settingsLoaded = true;

        lblBackupPath.Text   = App.Settings.Current.BackupRoot;
        lblBackupCount.Text  = "Calculando...";
        string root = App.Settings.Current.BackupRoot;

        var (count, mb) = await Task.Run(() =>
        {
            int sessions = 0; double sizeMb = 0;
            try
            {
                if (Directory.Exists(root))
                {
                    sessions = Directory.EnumerateDirectories(root).Count();
                    long bytes = 0;
                    foreach (var f in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
                    {
                        try { bytes += new FileInfo(f).Length; } catch { }
                    }
                    sizeMb = bytes / (1024.0 * 1024.0);
                }
            }
            catch { }
            return (sessions, Math.Round(sizeMb, 1));
        });

        lblBackupCount.Text = count == 0
            ? "Sin sesiones de backup guardadas"
            : $"{count} sesion(es) · {mb} MB";
    }

    private void SetActiveNav(int index)
    {
        mainTabs.SelectedIndex = index;

        var styleActive   = (Style)FindResource("BtnNavActive");
        var styleInactive = (Style)FindResource("BtnNav");

        for (int i = 0; i < _navButtons.Length; i++)
            _navButtons[i].Style = i == index ? styleActive : styleInactive;

        // footer solo visible en Optimizar (index 0)
        if (index == 0)
        {
            footerBar.Visibility = Visibility.Visible;
            footerBar.Height = double.NaN;
        }
        else
        {
            footerBar.Visibility = Visibility.Collapsed;
            footerBar.Height = 0;
        }

        // animacion de opacidad 0->1 sobre el contenido de la tab activa
        try
        {
            if (mainTabs.SelectedContent is UIElement content)
            {
                content.Opacity = 0;
                content.BeginAnimation(OpacityProperty,
                    new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(150)));
            }
        }
        catch { }
    }

    // ── Monitor async ────────────────────────────────────────────────────────

    private async void OnMonitorTick(object? sender, EventArgs e)
    {
        var data = await Task.Run(ReadMetrics);

        barCPUFill.Background = ThresholdBrush(data.CpuPct, 85, 60, BrushGreen);
        AnimateBar(barCPUFill, data.CpuPct / 100.0);
        lblCPUPct.Text = $"{data.CpuPct:F0}%";

        double ramPct = data.RamTotalGb > 0 ? data.RamUsedGb / data.RamTotalGb * 100.0 : 0;
        barRAMFill.Background = ThresholdBrush(ramPct, 85, 70, BrushBlue);
        AnimateBar(barRAMFill, ramPct / 100.0);
        lblRAMVal.Text   = $"{data.RamUsedGb:F1} GB";
        lblRAMTotal.Text = $"{data.RamTotalGb:F0} GB";
        lblRAMUsed.Text  = $"{data.RamUsedGb:F1} GB";
        lblRAMFree.Text  = $"{(data.RamTotalGb - data.RamUsedGb):F1} GB";

        barDiskFill.Background = ThresholdBrush(data.DiskPct, 85, 60, BrushGreen);
        AnimateBar(barDiskFill, data.DiskPct / 100.0);
        lblDiskPct.Text = $"{data.DiskPct:F0}%";

        // C: (uso) — umbral: >90% rojo, >75% amarillo, resto acento.
        barDiskUsageFill.Background = ThresholdBrush(data.SysDiskUsagePct, 90, 75, BrushBlue);
        AnimateBar(barDiskUsageFill, data.SysDiskUsagePct / 100.0);
        lblDiskUsagePct.Text = $"{data.SysDiskUsagePct:F0}%";

        // Thermal: leer cada 5 ticks (~5s), igual que PS1.
        // WMI de temperaturas es mas lento que PerformanceCounter — no leer en cada tick.
        _thermalTick++;
        if (_thermalTick >= 5 && !_thermalReading)
        {
            _thermalTick    = 0;
            _thermalReading = true;
            try
            {
                var thermal = await App.Thermal.GetThermalStatusAsync();
                UpdateThermalDisplay(thermal);
            }
            finally { _thermalReading = false; }
        }
    }

    private Metrics ReadMetrics()
    {
        float cpu = ReadCpuPct();

        _memStatus.dwLength = NativeMethods.MemoryStatusExSize;
        NativeMethods.GlobalMemoryStatusEx(ref _memStatus);
        double totalGb = _memStatus.ullTotalPhys / 1_073_741_824.0;
        double usedGb  = (_memStatus.ullTotalPhys - _memStatus.ullAvailPhys) / 1_073_741_824.0;

        double diskPct = 0;
        try { diskPct = Math.Clamp(_diskCounter?.NextValue() ?? 0f, 0f, 100f); }
        catch { }

        // % usado del disco del sistema (C:). Casi estatico, pero DriveInfo es
        // instantaneo y aca corremos fuera del hilo UI (Task.Run), sin costo.
        double sysUsagePct = 0;
        try
        {
            string sysRoot = System.IO.Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\";
            var di = new DriveInfo(sysRoot);
            if (di.IsReady && di.TotalSize > 0)
                sysUsagePct = Math.Clamp(
                    (di.TotalSize - di.TotalFreeSpace) / (double)di.TotalSize * 100.0, 0, 100);
        }
        catch { }

        return new Metrics(cpu, usedGb, totalGb, diskPct, sysUsagePct);
    }

    private float ReadCpuPct()
    {
        NativeMethods.GetSystemTimes(out var idle, out var kernel, out var user);
        long idleT   = NativeMethods.FileTimeToLong(idle);
        long kernelT = NativeMethods.FileTimeToLong(kernel);
        long userT   = NativeMethods.FileTimeToLong(user);

        if (_firstCpuRead)
        {
            _firstCpuRead = false;
            (_prevIdle, _prevKernel, _prevUser) = (idleT, kernelT, userT);
            return 0f;
        }

        long dIdle   = idleT   - _prevIdle;
        long dKernel = kernelT - _prevKernel;
        long dUser   = userT   - _prevUser;
        (_prevIdle, _prevKernel, _prevUser) = (idleT, kernelT, userT);

        long total = dKernel + dUser;
        return total == 0 ? 0f
            : (float)Math.Clamp((1.0 - (double)dIdle / total) * 100.0, 0, 100);
    }

    private static SolidColorBrush ThresholdBrush(double pct, double high, double mid, SolidColorBrush okBrush) =>
        pct > high ? BrushRed : pct > mid ? BrushYellow : okBrush;

    // Mirror de Update-ThermalDisplay del PS1 (modulo 6A).
    // Colores reactivos: verde <70 | amarillo 70-85 | rojo >85
    private void UpdateThermalDisplay(ThermalStatus thermal)
    {
        if (thermal.Cpu.Available)
        {
            float  c     = thermal.Cpu.TempC;
            var    brush = TempBrush(c);
            barCPUTempFill.Height     = Math.Max(2, Math.Round(110 * Math.Min(100f, c) / 100.0));
            barCPUTempFill.Background = brush;
            lblCPUTemp.Text           = $"{c}°C";
            lblCPUTemp.Foreground     = brush;
        }
        else
        {
            barCPUTempFill.Height     = 0;
            barCPUTempFill.Background = BrushGray;
            lblCPUTemp.Text           = "N/D";
            lblCPUTemp.Foreground     = BrushGray;
        }

        if (thermal.Gpu.Available)
        {
            float  c     = thermal.Gpu.TempC;
            var    brush = TempBrush(c);
            barGPUTempFill.Height       = Math.Max(2, Math.Round(110 * Math.Min(100f, c) / 100.0));
            barGPUTempFill.Background   = brush;
            lblGPUTemp.Text             = $"{c}°C";
            lblGPUTemp.Foreground       = brush;
            lblGPUTempSource.Visibility = Visibility.Visible;
        }
        else
        {
            barGPUTempFill.Height       = 0;
            barGPUTempFill.Background   = BrushGray;
            lblGPUTemp.Text             = "N/D";
            lblGPUTemp.Foreground       = BrushGray;
            lblGPUTempSource.Visibility = Visibility.Collapsed;
        }
    }

    private static SolidColorBrush TempBrush(float tempC) =>
        tempC >= 85 ? BrushRed : tempC >= 70 ? BrushYellow : BrushGreen;

    private static void AnimateBar(Border bar, double ratio)
    {
        double max = bar.Parent is Border parent && parent.ActualHeight > 1
            ? parent.ActualHeight : 110;
        double target = Math.Clamp(ratio * max, 0, max);

        bar.BeginAnimation(HeightProperty,
            new DoubleAnimation(target, TimeSpan.FromMilliseconds(200))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
            });
    }

    protected override void OnClosed(EventArgs e)
    {
        _monitorTimer.Stop();
        _procTimer?.Stop();
        _diskCounter?.Dispose();
        base.OnClosed(e);
    }

    private record struct Metrics(float CpuPct, double RamUsedGb, double RamTotalGb,
                                  double DiskPct, double SysDiskUsagePct);

    // ── System info + Score (2.1) ────────────────────────────────────────────

    private async Task LoadSystemInfoAsync()
    {
        try
        {
            var info = await App.SystemInfo.GetSystemInfoAsync();
            _systemInfo = info;
            PopulateSystemInfoControls(info);
        }
        catch { }
        // Queue score at background priority (same pattern as PS1 Add_ContentRendered)
        _ = Dispatcher.BeginInvoke(DispatcherPriority.Background,
            new Action(async () => await RunAndDisplayScoreAsync()));

        // Snapshot de arranque: captura async el estado inicial (sin bloquear UI)
        _ = Task.Run(async () =>
        {
            var snap = await App.Snapshots.TakeSnapshotAsync();
            App.SnapshotBefore = snap;
            string boot = snap.BootTimeSec >= 0 ? $"{snap.BootTimeSec}s" : "N/D";
            App.Logger.Log(
                $"Snapshot inicial: Boot {boot} | RAM libre {snap.RamFreeMb} MB | {snap.ProcCount} procesos",
                "info");
        });
    }

    private void PopulateSystemInfoControls(SystemSnapshot info)
    {
        string diskType = info.HasSsd ? "SSD" : "HDD";

        infoOS.Text   = info.OsCaption;
        infoCPU.Text  = info.CpuName;
        infoGPU.Text  = info.GpuName;
        infoRAM.Text  = $"{info.TotalRamGb} GB";
        infoDisk.Text = diskType;
        infoType.Text = info.IsLaptop ? "Laptop" : "PC Escritorio";

        if (info.IsLaptop) badgeLaptop.Visibility = Visibility.Visible;
    }

    // ── Limpieza profunda de cache (Herramientas) ────────────────────────────
    // Mirror del btnDeepClean del PS1. La logica vive en MaintenanceService;
    // aca solo va la confirmacion, el reporte al log y el estado en el label.
    private async Task DeepCleanAsync()
    {
        var r = System.Windows.MessageBox.Show(
            "Se limpiaran caches del sistema, reportes WER y logs no esenciales.\n" +
            "El Explorador se reiniciara brevemente.\n\nContinuar?",
            $"WinBoost v{App.Version}",
            MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (r != MessageBoxResult.Yes) return;

        btnDeepClean.IsEnabled = false;
        try
        {
            var res = await App.Maintenance.DeepCleanAsync(msg =>
                Dispatcher.Invoke(() => lblDeepCleanStatus.Text = msg));

            App.Logger.Log($"Cache Explorer: {res.IconMb} MB liberados", "ok");
            App.Logger.Log($"WER reports: {res.WerMb} MB liberados", "ok");
            App.Logger.Log($"Logs CBS/DISM: {res.LogMb} MB liberados", "ok");
            App.Logger.Log($"Shader cache: {res.ShaderMb} MB liberados", "ok");
            foreach (var err in res.Errors) App.Logger.Log(err, "err");
            App.Logger.Log($"LIMPIEZA PROFUNDA: {res.TotalMb} MB totales liberados", "head");

            lblDeepCleanStatus.Text = $"Listo  {res.TotalMb} MB liberados";
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Limpieza profunda: {ex.Message}", "err");
            lblDeepCleanStatus.Text = "Error";
        }
        finally
        {
            btnDeepClean.IsEnabled = true;
        }
    }

    private static SolidColorBrush BrushFromHex(string hex)
    {
        var c = (Color)ColorConverter.ConvertFromString(hex);
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    private async Task RunAndDisplayScoreAsync()
    {
        try
        {
            var result       = await App.SystemInfo.RunAuditAsync();
            _lastAuditResult = result;
            UpdateScoreWidget(result);
            UpdateScorePanel(result);
        }
        catch { }
        // Primer uso: lanzar onboarding ya con hardware + score disponibles (5.2)
        MaybeShowOnboarding();
    }

    // ── Primer uso + onboarding (5.2, modulos 15A/15B) ───────────────────────

    // Mirror de Test-FirstRun + el disparo de Show-OnboardingDialog del PS1.
    // El estado de primer uso vive en settings.json (FirstRunCompleted).
    private void MaybeShowOnboarding()
    {
        if (_onboardingChecked) return;
        _onboardingChecked = true;

        if (App.Settings.Current.FirstRunCompleted) return;

        var info     = _systemInfo;
        int score    = _lastAuditResult?.Score ?? 0;
        string cpu   = info?.CpuName ?? "N/D";
        string gpu   = info?.GpuName ?? "N/D";
        int ram      = info?.TotalRamGb ?? 0;
        string disk  = (info?.HasSsd ?? false) ? "SSD" : "HDD";
        bool laptop  = info?.IsLaptop ?? false;

        // Preset recomendado (mismo criterio que el PS1)
        string rec = laptop ? "prod" : ram >= 8 ? "gaming" : "safe";

        try
        {
            var dlg = new OnboardingDialog(cpu, gpu, ram, disk, laptop, score, rec) { Owner = this };
            dlg.ShowDialog();

            if (dlg.ChosenPreset is { } preset)
            {
                ApplyPreset(preset);                              // aplica el perfil elegido
                App.Settings.Current.FirstRunCompleted = true;   // Set-FirstRunComplete
                App.Settings.Save();
                App.Logger.Log($"Onboarding completado · perfil {preset}", "ok");
            }
        }
        catch { }
    }

    private async Task RecalcScoreAsync()
    {
        btnRecalcScore.IsEnabled  = false;
        lblScorePanelLabel.Text   = "Recalculando...";
        try
        {
            var result                 = await App.SystemInfo.RunAuditAsync();
            _lastAuditResult           = result;
            scoreDeltaBadge.Visibility = Visibility.Collapsed;
            UpdateScoreWidget(result);
            UpdateScorePanel(result);
            AnimateScoreCount(0, result.Score, 700);
        }
        catch { }
        finally { btnRecalcScore.IsEnabled = true; }
    }

    private void UpdateScoreWidget(AuditResult r)
    {
        var brush = ScoreBrush(r.Score);
        lblScoreValue.Text       = $"{r.Score}";
        lblScoreValue.Foreground = brush;
        scoreBar.Background      = brush;
        scoreBar.Opacity         = Math.Max(0.15, r.Score / 100.0);
        scoreWidget.BorderBrush  = brush;

        string label = r.Score >= 75 ? "Sistema bien optimizado"
                     : r.Score >= 45 ? "Optimizacion parcial"
                     : "Sin optimizar";
        lblScoreTooltipTitle.Text = $"{label}  ({r.Score}/100)";

        string detail = string.Join("  |  ", r.ByCategory.OrderBy(kv => kv.Key)
            .Select(kv => $"{kv.Key}: {kv.Value}"));
        var failLines = r.Items.Where(i => !i.Ok).Take(5).Select(i => $"  - {i.Label}");
        lblScoreTooltipDetail.Text = detail
            + (failLines.Any() ? "\nPendientes:\n" + string.Join("\n", failLines)
                               : "\nTodo optimizado.");
    }

    private void UpdateScorePanel(AuditResult r)
    {
        var brush = ScoreBrush(r.Score);
        lblScorePanelValue.Text       = $"{r.Score}";
        lblScorePanelValue.Foreground = brush;
        lblScorePanelLabel.Text       = r.Score >= 75 ? "Sistema bien optimizado"
                                      : r.Score >= 45 ? "Optimizacion parcial - hay margen de mejora"
                                      : "Sistema sin optimizar";

        AnimateCategoryBar("Rendimiento", barCatRendimiento, lblCatRendimiento, r);
        AnimateCategoryBar("Privacidad",  barCatPrivacidad,  lblCatPrivacidad,  r);
        AnimateCategoryBar("Red",         barCatRed,         lblCatRed,         r);
        AnimateCategoryBar("Servicios",   barCatServicios,   lblCatServicios,   r);
    }

    private static void AnimateCategoryBar(string category, Border bar, TextBlock lbl, AuditResult r)
    {
        var items = r.Items.Where(i => i.Category == category).ToList();
        if (items.Count == 0) return;
        int ok  = items.Count(i => i.Ok);
        lbl.Text = $"{ok}/{items.Count}";
        double pct = (double)ok / items.Count;
        bar.Background = ScoreBrush(pct >= 0.75 ? 80 : pct >= 0.45 ? 50 : 0);

        if (bar.Parent is not FrameworkElement parent || parent.ActualWidth <= 0)
        { bar.Width = 0; return; }

        bar.BeginAnimation(WidthProperty,
            new DoubleAnimation(bar.ActualWidth, parent.ActualWidth * pct, TimeSpan.FromMilliseconds(500))
            { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
    }

    private void OnMainTabsSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.Source != mainTabs) return;

        // Tab Herramientas (1): carga lazy de procesos pesados la primera vez +
        // arranca el auto-refresh (ON por defecto). El scan corre async, no traba la UI.
        if (mainTabs.SelectedIndex == 1 && !_procLoaded)
        {
            _procLoaded = true;
            _ = InitProcessesAsync();
        }

        // Tab Info (2): re-dibuja las barras de categoria del score
        if (mainTabs.SelectedIndex == 2 && _lastAuditResult is { } r)
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => UpdateScorePanel(r)));

        // Tab Info (2): info de componentes (carga WMI lazy la primera vez; luego
        // re-render instantaneo desde cache para refrescar el estado de HAGS).
        if (mainTabs.SelectedIndex == 2)
            _ = LoadComponentsInfoAsync();

        // Tab Arranque (3): carga lazy de la lista de startup la primera vez
        if (mainTabs.SelectedIndex == 3 && !_startupLoaded)
        {
            _startupLoaded = true;
            _ = RefreshStartupAsync();
        }

        // Tab Bloatware (4): escanea lazy la primera vez (el scan enumera AppX y
        // tarda; dispararlo aca y no en el arranque evita penalizar el startup).
        // El boton "Actualizar lista" sigue refrescando manualmente despues.
        if (mainTabs.SelectedIndex == 4 && !_bloatLoaded)
        {
            _bloatLoaded = true;
            _ = ScanBloatwareAsync();
        }

        // Tab Historial (6): carga lazy la primera vez
        if (mainTabs.SelectedIndex == 6 && !_historyLoaded)
        {
            _historyLoaded = true;
            _ = RefreshHistoryAsync();
        }

        // Tab Ajustes (7): calcula el tamano de la carpeta de backups la primera vez
        // (async, fuera del hilo UI; BUG 3)
        if (mainTabs.SelectedIndex == 7 && !_settingsLoaded)
            _ = LoadBackupInfoAsync();

        // Tab Tuning Avanzado (9): carga lazy de estados + info la primera vez
        if (mainTabs.SelectedIndex == 9 && !_tuningLoaded)
        {
            _tuningLoaded = true;
            _ = LoadTuningTabAsync();
        }
    }

    private void AnimateScoreCount(int from, int to, int durationMs = 800)
    {
        int steps    = 20;
        int interval = Math.Max(20, durationMs / steps);
        int step     = 0;
        var timer    = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(interval) };
        timer.Tick += (_, _) =>
        {
            step++;
            double progress = Math.Min(1.0, (double)step / steps);
            double eased    = 1.0 - Math.Pow(1.0 - progress, 3);
            lblScoreValue.Text = $"{from + (int)Math.Round((to - from) * eased)}";
            if (progress >= 1.0) timer.Stop();
        };
        timer.Start();
    }

    private static SolidColorBrush ScoreBrush(int score) =>
        score >= 75 ? BrushGreen : score >= 45 ? BrushYellow : BrushRed;

    // ── Procesos (2.4) ───────────────────────────────────────────────────────

    // Mirror de Refresh-ProcessList del PS1 (módulo 5B).
    private async Task RefreshProcessListAsync()
    {
        if (_procRefreshing) return;
        _procRefreshing        = true;
        lblProcsStatus.Text    = "Actualizando...";
        try
        {
            bool showSys = chkShowSysProcs.IsChecked == true;
            var  procs   = await App.Processes.GetHeavyProcessesAsync(15, showSys);

            float cpuTotal = procs.Sum(p => p.CpuPct);
            lblProcsCpuTotal.Text = $"{Math.Round(cpuTotal, 1)}%";
            lblProcsCount.Text    = $"{procs.Count}";

            RenderProcessList(procs);

            lblProcsStatus.Text = $"Actualizado {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error al actualizar procesos: {ex.Message}", "err");
            lblProcsStatus.Text = "Error — ver consola";
        }
        finally { _procRefreshing = false; }
    }

    // Mirror de Render-ProcessList del PS1 (módulo 5B).
    // Construye las filas de la lista de procesos en código (mismo layout que el PS1).
    private void RenderProcessList(IReadOnlyList<ProcessEntry> procs)
    {
        icProcs.Items.Clear();

        if (procs.Count == 0)
        {
            var empty = new TextBlock
            {
                Text       = "Sin actividad pesada",
                Foreground = BrushGray,
                FontSize   = 13,
                Margin     = new Thickness(16, 20, 16, 20),
            };
            icProcs.Items.Add(empty);
            return;
        }

        var styleDanger = (Style)FindResource("BtnDanger");

        foreach (var p in procs)
        {
            // ── Row border ──────────────────────────────────────────────────
            var rowBdr = new Border
            {
                Padding         = new Thickness(14, 6, 14, 6),
                BorderThickness = new Thickness(0, 0, 0, 1),
                BorderBrush     = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
                Background      = p.IsSystem
                    ? new SolidColorBrush(Color.FromRgb(0x0A, 0x0A, 0x0F))
                    : null,
            };

            // ── Grid 6 columns: Name | PID | CPU% | RAM | Company | Action ─
            var grid = new Grid();
            foreach (var w in new double[] { 160, 55, 90, 90 })
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(w) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(85) });

            // Col 0 — Name + description
            var namePanel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var nameTxt   = new TextBlock
            {
                Text          = p.Name,
                FontSize      = 12,
                FontWeight    = FontWeights.SemiBold,
                Foreground    = p.IsSystem ? BrushGray : new SolidColorBrush(Colors.White),
                TextTrimming  = TextTrimming.CharacterEllipsis,
            };
            namePanel.Children.Add(nameTxt);
            if (!string.IsNullOrEmpty(p.Description))
            {
                namePanel.Children.Add(new TextBlock
                {
                    Text         = p.Description,
                    FontSize     = 10,
                    Foreground   = BrushGray,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                });
            }
            Grid.SetColumn(namePanel, 0);

            // Col 1 — PID
            var pidTxt = new TextBlock
            {
                Text              = $"{p.Pid}",
                FontSize          = 11,
                Foreground        = BrushGray,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(pidTxt, 1);

            // Col 2 — CPU% + mini bar
            var cpuBrush = p.CpuPct >= 50 ? BrushRed : p.CpuPct >= 20 ? BrushYellow : BrushBlue;
            var cpuPanel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            cpuPanel.Children.Add(new TextBlock
            {
                Text       = $"{p.CpuPct}%",
                FontSize   = 12,
                FontWeight = FontWeights.SemiBold,
                Foreground = cpuBrush,
            });

            // Mini bar using a 2-column star grid (mirrors PS1 cpuBarGrid)
            float cpuClamped = Math.Clamp(p.CpuPct, 0, 100);
            var   barGrid    = new Grid { Height = 3, Margin = new Thickness(0, 2, 8, 0) };
            barGrid.ColumnDefinitions.Add(new ColumnDefinition
                { Width = new GridLength(cpuClamped, GridUnitType.Star) });
            barGrid.ColumnDefinitions.Add(new ColumnDefinition
                { Width = new GridLength(Math.Max(0, 100 - cpuClamped), GridUnitType.Star) });
            var bdrFill  = new Border
                { Background = cpuBrush, CornerRadius = new CornerRadius(2) };
            var bdrEmpty = new Border
                { Background = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
                  CornerRadius = new CornerRadius(2) };
            Grid.SetColumn(bdrFill,  0);
            Grid.SetColumn(bdrEmpty, 1);
            barGrid.Children.Add(bdrFill);
            barGrid.Children.Add(bdrEmpty);
            cpuPanel.Children.Add(barGrid);
            Grid.SetColumn(cpuPanel, 2);

            // Col 3 — RAM
            var ramBrush = p.RamMb >= 1024 ? BrushRed : p.RamMb >= 300 ? BrushYellow : BrushGreen;
            string ramLabel = p.RamMb >= 1024
                ? $"{Math.Round(p.RamMb / 1024f, 1)} GB"
                : $"{p.RamMb} MB";
            var ramTxt = new TextBlock
            {
                Text              = ramLabel,
                FontSize          = 11,
                Foreground        = ramBrush,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(ramTxt, 3);

            // Col 4 — Company / path (star column)
            var companyTxt = new TextBlock
            {
                Text              = !string.IsNullOrEmpty(p.Company) ? p.Company : p.Path,
                FontSize          = 10,
                Foreground        = BrushGray,
                TextTrimming      = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
                Margin            = new Thickness(8, 0, 8, 0),
            };
            Grid.SetColumn(companyTxt, 4);

            // Col 5 — Kill button or "Sistema" badge
            if (!p.IsSystem)
            {
                int  capturedPid  = p.Pid;
                string capturedName = p.Name;
                var  killBtn = new Button
                {
                    Content             = "Terminar",
                    Style               = styleDanger,
                    Tag                 = capturedPid,
                    Padding             = new Thickness(8, 3, 8, 3),
                    FontSize            = 10,
                    VerticalAlignment   = VerticalAlignment.Center,
                    HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                    ToolTip             = $"Terminar {capturedName} (PID {capturedPid})",
                };
                killBtn.Click += async (_, _) => await OnKillProcessAsync(capturedPid, capturedName);
                Grid.SetColumn(killBtn, 5);
                grid.Children.Add(killBtn);
            }
            else
            {
                var sysBdr = new Border
                {
                    CornerRadius        = new CornerRadius(3),
                    Padding             = new Thickness(6, 3, 6, 3),
                    VerticalAlignment   = VerticalAlignment.Center,
                    HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                    Background          = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x2A)),
                    Child = new TextBlock
                    {
                        Text       = "Sistema",
                        FontSize   = 10,
                        Foreground = BrushGray,
                    },
                };
                Grid.SetColumn(sysBdr, 5);
                grid.Children.Add(sysBdr);
            }

            grid.Children.Add(namePanel);
            grid.Children.Add(pidTxt);
            grid.Children.Add(cpuPanel);
            grid.Children.Add(ramTxt);
            grid.Children.Add(companyTxt);

            rowBdr.Child = grid;
            icProcs.Items.Add(rowBdr);
        }
    }

    // Carga lazy de la tab Herramientas (mirror del patron usado en Bloatware):
    // trae la lista una vez al entrar y, si el auto-refresh esta habilitado en
    // settings (ON por defecto), arranca el timer. Todo async, no traba la UI.
    private async Task InitProcessesAsync()
    {
        await RefreshProcessListAsync();
        if (App.Settings.Current.ProcAutoRefresh && !_procTimerRunning)
            StartProcTimer();
    }

    // Mirror de Start-ProcTimer / Stop-ProcTimer del PS1.
    private void ToggleProcTimer()
    {
        if (_procTimerRunning) StopProcTimer();
        else                   StartProcTimer();
        // Persistir la eleccion del usuario (default ON al primer arranque)
        App.Settings.Current.ProcAutoRefresh = _procTimerRunning;
        App.Settings.Save();
    }

    private void StartProcTimer()
    {
        if (_procTimerRunning) return;
        int sec = App.Settings.Current.ProcRefreshSec > 0
            ? App.Settings.Current.ProcRefreshSec : ProcTimerIntervalSec;
        _procTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(sec) };
        _procTimer.Tick += async (_, _) => await RefreshProcessListAsync();
        _procTimer.Start();
        _procTimerRunning              = true;
        btnToggleProcTimer.Content     = "Auto-refresh ON";
        btnToggleProcTimer.Foreground  = BrushBlue;
    }

    private void StopProcTimer()
    {
        if (!_procTimerRunning) return;
        _procTimer?.Stop();
        _procTimerRunning              = false;
        btnToggleProcTimer.Content     = "Auto-refresh OFF";
        btnToggleProcTimer.Foreground  = BrushGray;
    }

    // ── Dispositivos + Drivers (2.5) ─────────────────────────────────────────

    // Mirror de Scan-DeviceProblems del PS1 (módulo F1.7).
    private async Task ScanDevicesAsync()
    {
        btnScanDevices.IsEnabled     = false;
        lblDeviceProblemsStatus.Text = "Escaneando...";
        try
        {
            var devs = await App.Devices.GetProblemDevicesAsync();
            RenderProblemDevices(devs);
            int n = devs.Count;
            badgeDeviceProblems.Visibility = n > 0 ? Visibility.Visible : Visibility.Collapsed;
            lblDeviceProblemsStatus.Text   = n == 0
                ? "Sin problemas"
                : $"{n} dispositivo(s) con problemas";
        }
        catch
        {
            lblDeviceProblemsStatus.Text = "Error al escanear";
        }
        finally { btnScanDevices.IsEnabled = true; }
    }

    // Mirror de Render-ProblemDevices del PS1.
    // Grid 3 columnas: Nombre (Star) | Status badge (120) | Código (80)
    private void RenderProblemDevices(IReadOnlyList<ProblemDevice> devices)
    {
        icDeviceProblems.Items.Clear();

        if (devices.Count == 0)
        {
            icDeviceProblems.Items.Add(new TextBlock
            {
                Text       = "Sin problemas detectados — todos los dispositivos responden correctamente.",
                Foreground = BrushGreen,
                FontSize   = 12,
                Margin     = new Thickness(8, 16, 8, 16),
                TextWrapping = TextWrapping.Wrap,
            });
            return;
        }

        foreach (var dev in devices)
        {
            bool  isError   = dev.Status == "Error";
            var   bgColor   = Color.FromRgb(isError ? (byte)0x2A : (byte)0x2A,
                                             isError ? (byte)0x0A : (byte)0x1A,
                                             isError ? (byte)0x0A : (byte)0x00);
            var   fgColor   = isError
                ? Color.FromRgb(0xEF, 0x44, 0x44)
                : Color.FromRgb(0xF5, 0x9E, 0x0B);

            var rowBdr = new Border
            {
                Padding         = new Thickness(8, 6, 8, 6),
                BorderThickness = new Thickness(0, 0, 0, 1),
                BorderBrush     = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });

            // Col 0 — device name
            var lblName = new TextBlock
            {
                Text              = dev.FriendlyName,
                FontSize          = 12,
                Foreground        = new SolidColorBrush(Color.FromRgb(0xCC, 0xCC, 0xCC)),
                TextTrimming      = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(lblName, 0);

            // Col 1 — status badge
            var statusBdr = new Border
            {
                CornerRadius      = new CornerRadius(4),
                Padding           = new Thickness(6, 2, 6, 2),
                VerticalAlignment = VerticalAlignment.Center,
                Background        = new SolidColorBrush(bgColor),
                Child = new TextBlock
                {
                    Text       = dev.Status,
                    FontSize   = 11,
                    Foreground = new SolidColorBrush(fgColor),
                },
            };
            Grid.SetColumn(statusBdr, 1);

            // Col 2 — error code
            var codeTxt = new TextBlock
            {
                Text                = $"{dev.ErrorCode}",
                FontSize            = 11,
                Foreground          = new SolidColorBrush(Color.FromRgb(0x88, 0x88, 0x88)),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                VerticalAlignment   = VerticalAlignment.Center,
            };
            Grid.SetColumn(codeTxt, 2);

            grid.Children.Add(lblName);
            grid.Children.Add(statusBdr);
            grid.Children.Add(codeTxt);
            rowBdr.Child = grid;
            icDeviceProblems.Items.Add(rowBdr);
        }
    }

    // ── Optimizacion (3.1) ───────────────────────────────────────────────────

    private void ApplyPreset(string name)
    {
        var preset = OptimizationService.GetPreset(name);
        foreach (var (key, cb) in AllOptCheckboxes())
            cb.IsChecked = preset.TryGetValue(key, out bool val) && val;
        UpdatePlanSummary();
        App.Logger.Log($"Preset '{name}' aplicado", "info");
    }

    private Dictionary<string, CheckBox> AllOptCheckboxes() => new()
    {
        ["TempUser"]    = chkTempUser,    ["TempSys"]     = chkTempSys,     ["Prefetch"]    = chkPrefetch,
        ["WinUpdate"]   = chkWinUpdate,   ["Browsers"]    = chkBrowsers,    ["Thumb"]       = chkThumb,
        ["Recycle"]     = chkRecycle,     ["EventLogs"]   = chkEventLogs,
        ["Power"]       = chkPower,       ["HPET"]        = chkHPET,        ["GPUPrio"]     = chkGPUPrio,
        ["PowerThrot"]  = chkPowerThrot,  ["Visual"]      = chkVisual,      ["MouseAccel"]  = chkMouseAccel,
        ["Startup"]     = chkStartup,     ["FastStartup"] = chkFastStartup, ["PageFile"]    = chkPageFile,
        ["TrimDesfrag"] = chkTrimDesfrag,
        ["GameDVR"]     = chkGameDVR,     ["GameMode"]    = chkGameMode,    ["Telemetry"]   = chkTelemetry,
        ["Cortana"]     = chkCortana,     ["Notif"]       = chkNotif,       ["Tasks"]       = chkTasks,
        ["Nagle"]       = chkNagle,       ["TCP"]         = chkTCP,         ["DNS"]         = chkDNS,
        ["DNSFlush"]    = chkDNSFlush,    ["DisableIPv6"] = chkDisableIPv6,
        ["SvcXbox"]     = chkSvcXbox,     ["SvcDiag"]     = chkSvcDiag,     ["SvcWER"]      = chkSvcWER,
        ["SvcSysMain"]  = chkSvcSysMain,  ["SvcMaps"]     = chkSvcMaps,     ["SvcFax"]      = chkSvcFax,
        ["SvcWSearch"]  = chkSvcWSearch,
    };

    private IReadOnlyDictionary<string, bool> GetCurrentSel() =>
        AllOptCheckboxes().ToDictionary(kv => kv.Key, kv => kv.Value.IsChecked == true);

    private void SelectAll(bool value)
    {
        foreach (var (_, cb) in AllOptCheckboxes())
            cb.IsChecked = value;
        // EventLogs siempre off en seleccionar todo (destructivo)
        if (value) chkEventLogs.IsChecked = false;
        UpdatePlanSummary();
    }

    private void UpdateDnsHint()
    {
        if (chkDNS.IsChecked != true) { lblDNSHint.Text = ""; return; }
        int idx = Math.Clamp(cboDNSProvider.SelectedIndex, 0, OptimizationService.DnsProviders.Count - 1);
        var p   = OptimizationService.DnsProviders[idx];
        lblDNSHint.Text = $"{p.Primary} / {p.Secondary}";
    }

    // Mirror de Build-ActionPlan del PS1: cuenta acciones y categorias en tiempo real (3.2)
    private void UpdatePlanSummary()
    {
        UpdateDnsHint();

        var sel  = GetCurrentSel();
        int dnsIdx = Math.Clamp(cboDNSProvider.SelectedIndex, 0, OptimizationService.DnsProviders.Count - 1);
        var plan = OptimizationService.BuildActionPlan(sel, dnsIdx);

        if (plan.Count == 0)
        {
            lblPlanSummary.Text       = "Nada seleccionado";
            lblPlanSummary.Foreground = BrushGray;
            lblPlanWarning.Visibility = Visibility.Collapsed;
            return;
        }

        var cats = plan.Select(a => a.Category).Distinct().ToList();
        lblPlanSummary.Text       = $"{plan.Count} acciones · {string.Join(" · ", cats)}";
        lblPlanSummary.Foreground = BrushBlue;

        // Advertir si hay acciones de impacto alto (EventLogs, PageFile)
        bool hasHighImpact = plan.Any(a => a.Impact == "high");
        if (hasHighImpact)
        {
            var highLabels = plan.Where(a => a.Impact == "high").Select(a => a.Label);
            lblPlanWarning.Text       = $"Impacto alto: {string.Join(", ", highLabels)}";
            lblPlanWarning.Visibility = Visibility.Visible;
        }
        else
        {
            lblPlanWarning.Visibility = Visibility.Collapsed;
        }
    }

    private void SaveProfile()
    {
        try
        {
            var dir = Path.GetDirectoryName(_optProfilePath)!;
            Directory.CreateDirectory(dir);
            File.WriteAllText(_optProfilePath,
                System.Text.Json.JsonSerializer.Serialize(GetCurrentSel(),
                    new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
            App.Logger.Log("Perfil de optimizacion guardado", "ok");
            // Feedback al usuario (mirror del MessageBox del btnSaveProfile del PS1):
            // sin esto el boton parecia "no hacer nada" aunque el JSON se escribia bien.
            System.Windows.MessageBox.Show(
                $"Perfil guardado:\n{_optProfilePath}",
                "WinBoost", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error guardando perfil: {ex.Message}", "err");
            System.Windows.MessageBox.Show(
                $"Error al guardar el perfil:\n{ex.Message}",
                "WinBoost", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void LoadProfile()
    {
        try
        {
            if (!File.Exists(_optProfilePath)) { ApplyPreset("Safe"); return; }
            var dict = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, bool>>(
                File.ReadAllText(_optProfilePath));
            if (dict is null) { ApplyPreset("Safe"); return; }
            foreach (var (key, cb) in AllOptCheckboxes())
                cb.IsChecked = dict.TryGetValue(key, out bool v) && v;
            UpdatePlanSummary();
        }
        catch { ApplyPreset("Safe"); }
    }

    private async Task OnRunOptimizationAsync()
    {
        // Gate Pro: tweaks de registro y servicios (5.1)
        if (LockProFeature("Tweaks de registro y servicios")) return;

        if (App.Worker.IsRunning) return;

        var sel    = GetCurrentSel();
        int dnsIdx = Math.Clamp(cboDNSProvider.SelectedIndex, 0, OptimizationService.DnsProviders.Count - 1);

        if (!sel.Values.Any(v => v))
        {
            System.Windows.MessageBox.Show(
                "Selecciona al menos una opcion antes de optimizar.",
                "WinBoost", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        // Dialogo de confirmacion / analisis (3.3)
        var plan   = OptimizationService.BuildActionPlan(sel, dnsIdx);
        var dialog = new ConfirmOptimizationDialog(plan) { Owner = this };
        if (dialog.ShowDialog() != true) return;

        // Capturar acciones para el reporte HTML (4.7)
        _lastReportActions = plan.Select(a => $"{a.Category}: {a.Label}").ToList();

        App.Backup.NewBackupSession();
        _scoreBefore       = _lastAuditResult?.Score ?? 0;
        App.SnapshotBefore = await App.Snapshots.TakeSnapshotAsync();

        btnRun.IsEnabled        = false;
        btnCancelOpt.Visibility = Visibility.Visible;
        btnSelAll.IsEnabled     = false;
        btnSelNone.IsEnabled    = false;

        var sysInfo   = _systemInfo ?? await App.SystemInfo.GetSystemInfoAsync();
        bool hasSsd   = sysInfo.HasSsd;
        bool isLaptop = sysInfo.IsLaptop;
        double ramGb  = sysInfo.TotalRamGb;
        string sysDrv = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:") + @"\";

        OptResult? optResult = null;

        SetActiveNav(5); // Consola — log en tiempo real

        bool ok = await App.Worker.RunAsync(async ct =>
        {
            var svc   = new OptimizationService();
            optResult = await svc.RunAsync(
                sel, hasSsd, isLaptop, ramGb, sysDrv, dnsIdx,
                altDriveForPageFile: null, movePageFileToAlt: false, ct);
        },
        startMsg: "Iniciando optimizacion WinBoost...",
        doneMsg:  "Optimizacion completada");

        btnRun.IsEnabled        = true;
        btnCancelOpt.Visibility = Visibility.Collapsed;
        btnSelAll.IsEnabled     = true;
        btnSelNone.IsEnabled    = true;

        if (ok && optResult is { } res)
        {
            lblSpaceFreed.Text = res.FreedMb > 0.1
                ? $"+{Math.Round(res.FreedMb, 1)} MB liberados"
                : "";
            App.Progress.Set(100, "Listo");
            await RecalcScoreAsync();
            await FinishOptimizationAsync(res, sel);
        }
    }

    // Mirror de Invoke-OptimizeFinish del PS1 (3.4): metadata + toast + score delta + dialogo resumen
    private async Task FinishOptimizationAsync(OptResult res, IReadOnlyDictionary<string, bool> sel)
    {
        int scoreAfter = _lastAuditResult?.Score ?? _scoreBefore;
        int delta      = scoreAfter - _scoreBefore;

        // Capturar estado para el reporte HTML (4.7)
        _lastFreedMb   = res.FreedMb;
        _snapshotAfter = await App.Snapshots.TakeSnapshotAsync(scoreAfter);

        // Score delta badge en el widget
        if (delta > 0)
        {
            lblScoreDelta.Text         = $"+{delta}";
            scoreDeltaBadge.Visibility = Visibility.Visible;
        }

        // Metadata de sesion
        App.Backup.SaveSessionMetadata(
            freedMb:     (int)Math.Round(res.FreedMb),
            scoreBefore: _scoreBefore,
            scoreAfter:  scoreAfter,
            preset:      "Manual");

        // Forzar recarga del historial al entrar al tab (4.6)
        _historyLoaded = false;

        // Toast
        string toastMsg = $"{res.Applied} acciones aplicadas"
            + (res.FreedMb > 0.1 ? $" · {Math.Round(res.FreedMb, 1)} MB liberados" : "")
            + (delta > 0 ? $" · score +{delta}" : "");
        ShowToast(toastMsg);

        // Dialogo de resumen — habilita "Ver comparativa" si hay ambos snapshots
        bool needsReboot = sel.TryGetValue("PageFile", out bool pf) && pf;
        bool canCompare  = App.SnapshotBefore != null && _snapshotAfter != null;
        var dlg = new FinishOptimizationDialog(res, _scoreBefore, scoreAfter, needsReboot, canCompare)
            { Owner = this };
        dlg.ShowDialog();

        if (dlg.GoToHistory) SetActiveNav(6); // Historial
        else if (dlg.ShowCompare) ShowCompareDialog(res.FreedMb);
    }

    // Muestra el modal comparativo (4.8) con la comparativa de snapshots.
    // Mirror del flujo Show-CompareDialog del PS1: "restart" | "later" | "log".
    private void ShowCompareDialog(double freedMb)
    {
        if (App.SnapshotBefore is not { } before || _snapshotAfter is not { } after) return;

        var compare = App.Snapshots.CompareSnapshots(before, after);
        var dlg = new CompareDialog(compare, freedMb) { Owner = this };
        dlg.ShowDialog();

        switch (dlg.Result)
        {
            case "restart":
                try
                {
                    Process.Start(new ProcessStartInfo("shutdown", "/r /t 0")
                        { UseShellExecute = false, CreateNoWindow = true });
                }
                catch (Exception ex) { App.Logger.Log($"No se pudo reiniciar: {ex.Message}", "err"); }
                break;
            case "log":
                SetActiveNav(5); // Consola
                break;
            // "later": no hacer nada
        }
    }

    // ── Mantenimiento (4.3) ──────────────────────────────────────────────────

    private static readonly SolidColorBrush BrushMaintOnBg  = FreezeBrush(Color.FromRgb(0x12, 0x2A, 0x12));
    private static readonly SolidColorBrush BrushMaintOffBg = FreezeBrush(Color.FromRgb(0x1E, 0x1E, 0x1E));
    private static readonly SolidColorBrush BrushMaintFg    = FreezeBrush(Color.FromRgb(0xCC, 0xCC, 0xCC));

    // Mirror de Update-MaintUI del PS1.
    private async Task UpdateMaintUIAsync()
    {
        // Deshabilitar TRIM si el equipo no tiene SSD (igual que el PS1)
        var sysInfo = _systemInfo ?? await App.SystemInfo.GetSystemInfoAsync();
        _systemInfo = sysInfo;
        if (!sysInfo.HasSsd)
        {
            chkMaintTRIM.IsChecked = false;
            chkMaintTRIM.IsEnabled = false;
        }

        var info = await App.Maintenance.GetTaskAsync();

        if (info.Exists && info.Enabled)
        {
            tglMaintenance.Content    = "Desactivar";
            tglMaintenance.Background = BrushMaintOnBg;
            tglMaintenance.Foreground = BrushGreen;
            lblMaintStatus.Text       = "Activo";
            lblMaintStatus.Foreground = BrushGreen;
            btnRunMaintNow.IsEnabled  = true;
        }
        else
        {
            tglMaintenance.Content    = "Activar";
            tglMaintenance.Background = BrushMaintOffBg;
            tglMaintenance.Foreground = BrushMaintFg;
            lblMaintStatus.Text       = info.Exists ? "Desactivado" : "No configurado";
            lblMaintStatus.Foreground = BrushGray;
            btnRunMaintNow.IsEnabled  = false;
        }

        lblLastMaint.Text = info.LastRun is { } lr
            ? $"Ultimo mantenimiento: {lr:dd/MM/yyyy HH:mm}"
            : "Ultimo mantenimiento: Nunca";
        lblNextMaint.Text = info.NextRun is { } nr
            ? $"Proximo: {nr:dd/MM/yyyy HH:mm}"
            : "Proximo: --";

        cboMaintHour.IsEnabled = cboMaintFreq.SelectedIndex != 2;
    }

    // Mirror del Add_Click de tglMaintenance del PS1.
    private async Task ToggleMaintenanceAsync()
    {
        // Gate Pro: mantenimiento automatico (5.1)
        if (LockProFeature("Mantenimiento automatico")) return;

        tglMaintenance.IsEnabled = false;
        try
        {
            var info = await App.Maintenance.GetTaskAsync();
            if (info.Exists && info.Enabled)
            {
                await App.Maintenance.RemoveTaskAsync();
            }
            else
            {
                string freq = cboMaintFreq.SelectedIndex switch
                {
                    0 => "Daily",
                    2 => "AtStartup",
                    _ => "Weekly",
                };
                int hour = cboMaintHour.SelectedIndex < 0 ? 10 : cboMaintHour.SelectedIndex;
                bool ok = await App.Maintenance.CreateTaskAsync(freq, hour);
                if (!ok)
                    System.Windows.MessageBox.Show(
                        "No se pudo registrar la tarea de mantenimiento.\n\n" +
                        "Asegurate de ejecutar WinBoost como administrador.",
                        "WinBoost - Mantenimiento",
                        MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error en mantenimiento: {ex.Message}", "err");
        }

        await UpdateMaintUIAsync();
        tglMaintenance.IsEnabled = true;
    }

    // Mirror del Add_Click de btnRunMaintNow del PS1.
    private async Task RunMaintenanceNowAsync()
    {
        // Gate Pro: mantenimiento automatico (5.1)
        if (LockProFeature("Mantenimiento automatico")) return;

        btnRunMaintNow.IsEnabled  = false;
        lblMaintStatus.Text       = "Ejecutando...";
        lblMaintStatus.Foreground = BrushGray;

        try
        {
            bool hasSsd = (_systemInfo ?? await App.SystemInfo.GetSystemInfoAsync()).HasSsd;
            var result = await App.Maintenance.RunCycleAsync(
                temp:    chkMaintTemp.IsChecked    == true,
                recycle: chkMaintRecycle.IsChecked == true,
                dns:     chkMaintDNS.IsChecked     == true,
                trim:    chkMaintTRIM.IsChecked    == true,
                hasSsd:  hasSsd);

            double mb = Math.Round(result.FreedMb, 1);
            lblMaintStatus.Text       = $"Completado  {mb} MB liberados";
            lblMaintStatus.Foreground = BrushGreen;
            lblLastMaint.Text         = $"Ultimo mantenimiento: {DateTime.Now:dd/MM/yyyy HH:mm}";

            ShowToast($"Mantenimiento completado. {mb} MB liberados.");
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error en mantenimiento: {ex.Message}", "err");
            lblMaintStatus.Text       = "Error en mantenimiento";
            lblMaintStatus.Foreground = BrushRed;
        }
        finally { btnRunMaintNow.IsEnabled = true; }
    }

    // ── Historial + score history (4.6) ──────────────────────────────────────

    // Refresca lista de sesiones + cards de estadisticas + mini grafico.
    private async Task RefreshHistoryAsync()
    {
        lblHistoryStatus.Text = "Cargando...";
        try
        {
            var sessions = await Task.Run(() => App.Backup.GetBackupSessions());
            RenderHistoryItems(sessions);

            var stats   = await App.History.GetHistoryStatsAsync();
            UpdateHistoryStats(stats);

            var history = await App.History.GetSessionHistoryAsync();
            RenderScoreHistory(history);

            lblHistoryStatus.Text = sessions.Count == 0
                ? "Sin sesiones guardadas"
                : $"{sessions.Count} sesion(es) guardada(s)";
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error cargando historial: {ex.Message}", "err");
            lblHistoryStatus.Text = "Error - ver consola";
        }
    }

    // Mirror de Render-HistoryItems del PS1.
    // Grid 6 cols: Fecha(150) | Preset(90) | Acciones(70) | MB(75) | Estado(Star) | Revertir(110)
    private void RenderHistoryItems(IReadOnlyList<BackupSessionInfo> sessions)
    {
        icHistory.Items.Clear();
        rtbRestoreLog.Document.Blocks.Clear();
        lblRestoreLog.Text = "Sin actividad";

        if (sessions.Count == 0)
        {
            icHistory.Items.Add(new TextBlock
            {
                Text         = "Sin historial — Ejecuta una optimizacion para crear la primera sesion de backup.",
                Foreground   = BrushGray,
                FontSize     = 12,
                Margin       = new Thickness(8, 24, 8, 24),
                TextWrapping = TextWrapping.Wrap,
            });
            return;
        }

        for (int i = 0; i < sessions.Count; i++)
        {
            var s       = sessions[i];
            bool isFirst = i == 0;

            var rowBdr = new Border
            {
                Padding         = new Thickness(14, 8, 14, 8),
                BorderThickness = new Thickness(0, 0, 0, 1),
                BorderBrush     = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
                Background      = isFirst ? new SolidColorBrush(Color.FromRgb(0x0D, 0x1A, 0x0D)) : null,
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(75) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });

            // Col 0 — Fecha
            var tsTxt = new TextBlock
            {
                Text              = s.Timestamp,
                FontSize          = 11,
                Foreground        = new SolidColorBrush(isFirst
                    ? Color.FromRgb(0xEE, 0xEE, 0xEE) : Color.FromRgb(0xCC, 0xCC, 0xCC)),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(tsTxt, 0);

            // Col 1 — Preset badge
            var (presetBg, presetFg) = s.Preset switch
            {
                "Gaming"        => (Color.FromRgb(0x0D, 0x1F, 0x2D), Color.FromRgb(0x00, 0xC8, 0xFF)),
                "Productividad" => (Color.FromRgb(0x1A, 0x1A, 0x0D), Color.FromRgb(0xF5, 0x9E, 0x0B)),
                "Conservador"   => (Color.FromRgb(0x1A, 0x0D, 0x1A), Color.FromRgb(0xA8, 0x55, 0xF7)),
                _               => (Color.FromRgb(0x1A, 0x1A, 0x1A), Color.FromRgb(0x88, 0x88, 0x88)),
            };
            var presetBdr = new Border
            {
                CornerRadius        = new CornerRadius(3),
                Padding             = new Thickness(6, 2, 6, 2),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
                Background          = new SolidColorBrush(presetBg),
                Child = new TextBlock { Text = s.Preset, FontSize = 10, Foreground = new SolidColorBrush(presetFg) },
            };
            Grid.SetColumn(presetBdr, 1);

            // Col 2 — Acciones
            var actTxt = new TextBlock
            {
                Text              = $"{s.Actions} acc.",
                FontSize          = 11,
                Foreground        = new SolidColorBrush(Color.FromRgb(0x88, 0x88, 0x88)),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(actTxt, 2);

            // Col 3 — MB liberados
            var mbTxt = new TextBlock
            {
                Text              = $"{s.FreedMb} MB",
                FontSize          = 11,
                Foreground        = BrushGreen,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(mbTxt, 3);

            // Col 4 — Estado (tiene metadata o no)
            var (stateBg, stateFg, stateLbl) = s.HasMeta
                ? (Color.FromRgb(0x0A, 0x2A, 0x0A), Color.FromRgb(0x22, 0xC5, 0x5E), "Completo")
                : (Color.FromRgb(0x2A, 0x2A, 0x0A), Color.FromRgb(0xF5, 0x9E, 0x0B), "Sin metadata");
            var stateBdr = new Border
            {
                CornerRadius        = new CornerRadius(3),
                Padding             = new Thickness(6, 2, 6, 2),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
                Margin              = new Thickness(8, 0, 0, 0),
                Background          = new SolidColorBrush(stateBg),
                Child = new TextBlock { Text = stateLbl, FontSize = 10, Foreground = new SolidColorBrush(stateFg) },
            };
            Grid.SetColumn(stateBdr, 4);

            // Col 5 — Boton revertir
            var revertBtn = new Button
            {
                Content             = "Revertir",
                Style               = (Style)FindResource("BtnDanger"),
                Padding             = new Thickness(10, 4, 10, 4),
                FontSize            = 11,
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                ToolTip             = $"Revertir sesion del {s.Timestamp}",
            };
            string capturedPath = s.Path;
            revertBtn.Click += async (_, _) => await InvokeRevertSessionAsync(capturedPath);
            Grid.SetColumn(revertBtn, 5);

            grid.Children.Add(tsTxt);
            grid.Children.Add(presetBdr);
            grid.Children.Add(actTxt);
            grid.Children.Add(mbTxt);
            grid.Children.Add(stateBdr);
            grid.Children.Add(revertBtn);

            rowBdr.Child = grid;
            icHistory.Items.Add(rowBdr);
        }
    }

    // Mirror de Update-HistoryStats del PS1: rellena los 4 cards.
    private void UpdateHistoryStats(HistoryStats? stats)
    {
        if (stats == null)
        {
            lblHistTotalSessions.Text  = "0";
            lblHistTotalMB.Text        = "0";
            lblHistAvgImprovement.Text = "--";
            lblHistDaysSince.Text      = "--";
            return;
        }
        lblHistTotalSessions.Text  = $"{stats.TotalSessions}";
        lblHistTotalMB.Text        = $"{stats.TotalFreedMb}";
        string sign = stats.AvgImprovement >= 0 ? "+" : "";
        lblHistAvgImprovement.Text = $"{sign}{stats.AvgImprovement}";
        lblHistDaysSince.Text      = $"{stats.DaysSince}";
    }

    // Mirror de Render-ScoreHistory del PS1: mini grafico de barras (8 ultimas,
    // de mas antigua a reciente) en el Canvas icScoreHistory.
    private void RenderScoreHistory(IReadOnlyList<SessionHistoryEntry> history)
    {
        icScoreHistory.Children.Clear();

        if (history.Count == 0)
        {
            var ph = new TextBlock
            {
                Text              = "Sin datos de sesiones aun",
                FontSize          = 11,
                Foreground        = new SolidColorBrush(Color.FromRgb(0x3A, 0x3A, 0x3A)),
                VerticalAlignment = VerticalAlignment.Center,
            };
            icScoreHistory.Children.Add(ph);
            return;
        }

        const int maxH = 56;
        int take = Math.Min(8, history.Count);
        // Tomar las `take` mas recientes (history es descendente) y revertir
        var sessions = history.Take(take).Reverse().ToList();

        double canvasW = icScoreHistory.ActualWidth;
        if (canvasW < 10) canvasW = 320;
        const int gap = 6;
        int barWidth = Math.Min(28, Math.Max(8, (int)((canvasW - (take - 1) * gap) / take)));
        int totalW   = take * barWidth + (take - 1) * gap;
        int xOffset  = Math.Max(0, (int)((canvasW - totalW) / 2));

        for (int i = 0; i < sessions.Count; i++)
        {
            int score = Math.Max(0, Math.Min(100, sessions[i].ScoreAfter));
            int barH  = Math.Max(2, score * maxH / 100);
            int barX  = xOffset + i * (barWidth + gap);

            var track = new Border
            {
                Width        = barWidth,
                Height       = maxH,
                CornerRadius = new CornerRadius(2),
                Background   = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
            };
            Canvas.SetLeft(track, barX);
            Canvas.SetBottom(track, 0);
            icScoreHistory.Children.Add(track);

            var barColor = score >= 75 ? BrushGreen : score >= 45 ? BrushYellow : BrushRed;
            var bar = new Border
            {
                Width        = barWidth,
                Height       = barH,
                CornerRadius = new CornerRadius(2, 2, 0, 0),
                Background   = barColor,
            };
            Canvas.SetLeft(bar, barX);
            Canvas.SetBottom(bar, 0);
            icScoreHistory.Children.Add(bar);
        }
    }

    // Mirror del Add_Click de btnOpenBackupFolder del PS1.
    private void OpenBackupFolder()
    {
        try
        {
            string root = App.Settings.Current.BackupRoot;
            if (!Directory.Exists(root)) Directory.CreateDirectory(root);
            Process.Start(new ProcessStartInfo("explorer.exe", root) { UseShellExecute = true });
        }
        catch { }
    }

    // Mirror del Add_Click de btnRevertLast del PS1.
    private async Task RevertLastSessionAsync()
    {
        var sessions = await Task.Run(() => App.Backup.GetBackupSessions());
        if (sessions.Count == 0)
        {
            System.Windows.MessageBox.Show(
                "No hay sesiones de backup guardadas.",
                "WinBoost - Historial",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        await InvokeRevertSessionAsync(sessions[0].Path);
    }

    // Mirror de Invoke-RevertSession del PS1.
    private async Task InvokeRevertSessionAsync(string sessionPath)
    {
        // Gate Pro: revertir sesion (5.1)
        if (LockProFeature("Revertir sesion")) return;

        string folderName = Path.GetFileName(sessionPath.TrimEnd('\\'));

        var confirm = System.Windows.MessageBox.Show(
            $"Vas a revertir la sesion:\n{folderName}\n\n" +
            "Esto restaurara los valores de registro, servicios y red al estado anterior a esa optimizacion.\n\n" +
            "Continuar?",
            "WinBoost - Revertir sesion",
            MessageBoxButton.YesNo, MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes) return;

        btnRevertLast.IsEnabled     = false;
        btnRefreshHistory.IsEnabled = false;
        icHistory.IsEnabled         = false;
        rtbRestoreLog.Document.Blocks.Clear();

        bool ok = await Task.Run(() =>
            App.Backup.RestoreSession(sessionPath,
                (msg, type) => Dispatcher.Invoke(() => WriteRestoreLog(msg, type))));

        btnRevertLast.IsEnabled     = true;
        btnRefreshHistory.IsEnabled = true;
        icHistory.IsEnabled         = true;

        System.Windows.MessageBox.Show(
            ok
                ? "Sesion revertida correctamente.\n\nReinicia el equipo para que todos los cambios tomen efecto."
                : "La restauracion termino con algunos errores.\n\nRevisa el log de restauracion para ver los detalles.",
            ok ? "WinBoost - Restauracion completada" : "WinBoost - Restauracion con errores",
            MessageBoxButton.OK, ok ? MessageBoxImage.Information : MessageBoxImage.Warning);
    }

    // Mirror de Write-RestoreLog del PS1: logger dedicado a rtbRestoreLog.
    private void WriteRestoreLog(string msg, string type = "info")
    {
        var (colorHex, label) = type switch
        {
            "ok"   => (Color.FromRgb(0x22, 0xC5, 0x5E), "  OK   "),
            "err"  => (Color.FromRgb(0xEF, 0x44, 0x44), "  !!   "),
            "skip" => (Color.FromRgb(0x66, 0x66, 0x66), "  --   "),
            "head" => (Color.FromRgb(0x00, 0xC8, 0xFF), " ====  "),
            "info" => (Color.FromRgb(0xF5, 0x9E, 0x0B), "  >>   "),
            _      => (Color.FromRgb(0x88, 0x88, 0x88), "  >>   "),
        };

        var brush = new SolidColorBrush(colorHex);
        var para  = new System.Windows.Documents.Paragraph { Margin = new Thickness(0) };
        para.Inlines.Add(new System.Windows.Documents.Run($"{DateTime.Now:HH:mm:ss}{label}{msg}")
        {
            Foreground = brush,
        });
        rtbRestoreLog.Document.Blocks.Add(para);
        restoreLogScroll.ScrollToEnd();

        lblRestoreLog.Text       = msg[..Math.Min(msg.Length, 55)];
        lblRestoreLog.Foreground = brush;
        badgeRestoreStatus.Background = new SolidColorBrush(type switch
        {
            "err" => Color.FromRgb(0x2A, 0x0A, 0x0A),
            "ok"  => Color.FromRgb(0x0A, 0x2A, 0x0A),
            _     => Color.FromRgb(0x1A, 0x1A, 0x1A),
        });
    }

    // ── Consola: exportar log a .txt ─────────────────────────────────────────

    // Mirror del Add_Click de btnExportLog del PS1: vuelca el texto de la consola a
    // Documentos\WinBoost_Log_<fecha>.txt (UTF-8) y avisa por MessageBox.
    private void ExportConsoleLog()
    {
        try
        {
            var range = new System.Windows.Documents.TextRange(
                rtbLog.Document.ContentStart, rtbLog.Document.ContentEnd);
            string docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            string ts   = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
            string outFile = System.IO.Path.Combine(docs, $"WinBoost_Log_{ts}.txt");
            System.IO.File.WriteAllText(outFile, range.Text, new System.Text.UTF8Encoding(false));
            lblLogStatus.Text = "Log exportado";
            System.Windows.MessageBox.Show($"Log exportado a:\n{outFile}",
                "WinBoost", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show($"Error al exportar: {ex.Message}",
                "WinBoost - Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    // ── Reporte HTML (4.7) ───────────────────────────────────────────────────

    // Mirror del Add_Click de btnExportHTML del PS1.
    private async Task ExportHtmlReportAsync()
    {
        // Gate Pro: exportar reporte HTML (5.1)
        if (LockProFeature("Exportar reporte HTML")) return;

        btnExportHTML.IsEnabled = false;
        try
        {
            var sysInfo = _systemInfo ?? await App.SystemInfo.GetSystemInfoAsync();
            string sysDrv = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
            int scoreAfter = _lastAuditResult?.Score ?? _scoreBefore;

            string? techName = !string.IsNullOrWhiteSpace(App.Settings.Current.TechnicianName)
                ? App.Settings.Current.TechnicianName
                : null;

            var data = new ReportData(
                Sys:            sysInfo,
                SysDrive:       sysDrv,
                ScoreBefore:    _scoreBefore,
                ScoreAfter:     scoreAfter,
                Before:         App.SnapshotBefore,
                After:          _snapshotAfter,
                FreedMb:        _lastFreedMb,
                Actions:        _lastReportActions,
                TechnicianName: techName);

            string? path = await App.Report.ExportAsync(data);
            if (path != null)
                App.Logger.Log($"Reporte HTML exportado: {path}", "ok");
            else
                App.Logger.Log("Error al exportar reporte HTML", "err");
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error al exportar reporte HTML: {ex.Message}", "err");
        }
        finally { btnExportHTML.IsEnabled = true; }
    }

    // ── Licencias + trial (5.1, modulos 12B/12C) ─────────────────────────────

    // Init en background: HWID + estado de licencia + trial fuera del hilo UI.
    private async Task InitLicenseAsync()
    {
        await Task.Run(() =>
        {
            App.License.RefreshFromStored();
            App.License.EvaluateTrial();
        });
        lblHardwareID.Text = App.License.GetHardwareId(); // cacheado por EvaluateTrial
        UpdateLicenseBadge();
        UpdateTrialBanner();
    }

    // Mirror de Lock-ProFeature: bloquea (true) si no hay Pro ni trial activo.
    private bool LockProFeature(string featureName = "")
    {
        if (App.License.IsPro) return false;

        string baseName = string.IsNullOrEmpty(featureName) ? "Esta funcion" : featureName;
        string msg = App.Settings.Current.TrialExpired
            ? $"{baseName} requiere licencia Pro.\n\nTu periodo de prueba ha vencido. Activa tu licencia en el tab Licencia."
            : $"{baseName} requiere licencia Pro.\n\nActiva tu licencia para desbloquear todas las funciones de WinBoost.";

        System.Windows.MessageBox.Show(
            msg, "WinBoost - Funcion Pro",
            MessageBoxButton.OK, MessageBoxImage.Information);
        return true;
    }

    // Mirror de Update-LicenseBadge: badge Free/Pro/Tecnico/Prueba + texto de estado segun tier/trial.
    // La deteccion de tier (IsTech/IsPro/IsTrial) no cambia; solo la variante visual por rama.
    private void UpdateLicenseBadge()
    {
        var lic = App.License;
        badgeLicenseFree.Visibility  = Visibility.Collapsed;
        badgeLicensePro.Visibility   = Visibility.Collapsed;
        badgeLicenseTech.Visibility  = Visibility.Collapsed;
        badgeLicenseTrial.Visibility = Visibility.Collapsed;

        if (lic.IsTech)
        {
            badgeLicenseTech.Visibility = Visibility.Visible;
            lblLicenseStatus.Text       = "WinBoost TECNICO activado - multi-PC";
            lblLicenseStatus.Foreground = BrushGreen;
        }
        else if (lic.IsPro && !lic.IsTrial)
        {
            badgeLicensePro.Visibility = Visibility.Visible;
            lblLicenseStatus.Text       = "WinBoost PRO activado";
            lblLicenseStatus.Foreground = BrushYellow;
        }
        else if (lic.IsPro && lic.IsTrial)
        {
            badgeLicenseTrial.Visibility = Visibility.Visible;
            lblLicenseTrialDays.Text     = $"· {lic.TrialDaysLeft}d";
            lblLicenseStatus.Text        = $"Periodo de prueba activo ({lic.TrialDaysLeft} dias restantes)";
            lblLicenseStatus.Foreground  = BrushYellow;
        }
        else
        {
            badgeLicenseFree.Visibility = Visibility.Visible;
            if (App.Settings.Current.TrialExpired)
            {
                lblLicenseStatus.Text       = "Periodo de prueba vencido";
                lblLicenseStatus.Foreground = BrushRed;
            }
            else
            {
                lblLicenseStatus.Text       = "Version gratuita activa";
                lblLicenseStatus.Foreground = BrushLicFree;
            }
        }
    }

    // Mirror de Update-TrialBanner: banner en el footer durante y post-trial.
    private void UpdateTrialBanner()
    {
        var lic = App.License;
        if (lic.IsPro && lic.IsTrial)
        {
            int d = lic.TrialDaysLeft;
            lblTrialText.Text = d == 1
                ? "Periodo de prueba: queda 1 dia. Activa Pro para no perder el acceso."
                : $"Periodo de prueba activo. Quedan {d} dias.";
            lblTrialText.Foreground     = BrushYellow;
            bannerTrial.Background      = BrushTrialBg;
            bannerTrial.BorderBrush     = BrushTrialBd;
            btnTrialUpgrade.Foreground  = BrushYellow;
            btnTrialUpgrade.BorderBrush = BrushYellow;
            bannerTrial.Visibility      = Visibility.Visible;
        }
        else if (!lic.IsPro && App.Settings.Current.TrialExpired)
        {
            lblTrialText.Text = "El periodo de prueba vencio. Activa Pro para seguir usando las funciones avanzadas.";
            lblTrialText.Foreground     = BrushRed;
            bannerTrial.Background      = BrushExpBg;
            bannerTrial.BorderBrush     = BrushExpBd;
            btnTrialUpgrade.Foreground  = BrushRed;
            btnTrialUpgrade.BorderBrush = BrushRed;
            bannerTrial.Visibility      = Visibility.Visible;
        }
        else
        {
            bannerTrial.Visibility = Visibility.Collapsed;
        }
    }

    // Mirror del btnCopyHWID: copia el HWID y muestra "Copiado" por 1.5s.
    private void CopyHardwareId()
    {
        try { System.Windows.Clipboard.SetText(lblHardwareID.Text); } catch { }
        btnCopyHWID.Content = "Copiado";
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
        timer.Tick += (_, _) => { btnCopyHWID.Content = "Copiar"; timer.Stop(); };
        timer.Start();
    }

    // Mirror del btnActivateLicense: valida y persiste la clave (tier Tecnico o Pro).
    private void ActivateLicense()
    {
        string key = txtLicenseKey.Text.Trim();
        if (string.IsNullOrWhiteSpace(key))
        {
            lblActivationResult.Text       = "Pega tu clave de activacion.";
            lblActivationResult.Foreground = BrushYellow;
            return;
        }

        // Tier Tecnico (TECH-<Base64>, multi-PC)
        if (key.StartsWith("TECH-", StringComparison.Ordinal))
        {
            if (App.License.ActivateTech(key))
            {
                UpdateLicenseBadge();
                UpdateTrialBanner();
                lblActivationResult.Text       = "Licencia Tecnico activada. Valida en cualquier equipo.";
                lblActivationResult.Foreground = BrushGreen;
            }
            else
            {
                lblActivationResult.Text       = "Clave Tecnico invalida. Asegurate de pegarla exactamente como la recibiste.";
                lblActivationResult.Foreground = BrushRed;
            }
            return;
        }

        // Tier Pro (firma RSA Base64, hardware-bound)
        if (App.License.ActivatePro(key))
        {
            UpdateLicenseBadge();
            UpdateTrialBanner();
            lblActivationResult.Text       = "Activacion exitosa. Bienvenido a WinBoost PRO.";
            lblActivationResult.Foreground = BrushGreen;
        }
        else
        {
            lblActivationResult.Text       = "Clave invalida o generada para otro equipo. Pega la clave exactamente como la recibiste.";
            lblActivationResult.Foreground = BrushRed;
        }
    }

    // Mirror del btnGetLicense: LICENSE_BUY_URL vacio -> aviso de contacto a soporte.
    private void GetLicense()
    {
        System.Windows.MessageBox.Show(
            "Contacta al soporte para obtener tu licencia Pro.",
            "WinBoost PRO", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    // ── Auto-updater (5.3, modulo 14) ────────────────────────────────────────

    private bool _updating = false;

    // Mirror de Check-ForUpdates: consulta version.json y muestra el badge si hay
    // version nueva. En chequeo manual avisa tambien cuando ya esta actualizado.
    private async Task CheckForUpdatesAsync(bool manual)
    {
        if (manual) btnCheckUpdatesSettings.IsEnabled = false;
        try
        {
            var meta = await App.Updater.CheckAsync();
            if (meta != null)
            {
                lblUpdateBadge.Text     = $"v{meta.Version} disponible";
                badgeUpdate.Visibility  = Visibility.Visible;
                if (manual) OnUpdateBadgeClick();
            }
            else if (manual)
            {
                System.Windows.MessageBox.Show(
                    $"Estas usando la ultima version (v{App.Version}).",
                    "WinBoost - Actualizaciones",
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        finally
        {
            if (manual) btnCheckUpdatesSettings.IsEnabled = true;
        }
    }

    // Mirror del click en badgeUpdate: muestra el changelog y procesa la accion.
    private void OnUpdateBadgeClick()
    {
        var meta = App.Updater.Latest;
        if (meta == null) return;

        var dlg = new ChangelogDialog(meta.Version, App.Version, meta.Changelog,
            downloadAvailable: !string.IsNullOrWhiteSpace(meta.DownloadUrl)) { Owner = this };
        dlg.ShowDialog();

        switch (dlg.Result)
        {
            case ChangelogResult.Download:
                _ = DownloadAndApplyAsync(meta);
                break;
        }
    }

    // Mirror de Start-UpdateDownload + Apply-Update: descarga con progreso en el
    // footer, verifica SHA256 y aplica. No bloquea el hilo UI.
    private async Task DownloadAndApplyAsync(UpdateMeta meta)
    {
        if (_updating) return;
        if (string.IsNullOrWhiteSpace(meta.DownloadUrl))
        {
            System.Windows.MessageBox.Show(
                "No hay URL de descarga disponible.\nDescarga manualmente desde GitHub.",
                "WinBoost - Actualizacion", MessageBoxButton.OK, MessageBoxImage.Information);
            OpenUrl(meta.ReleaseUrl);
            return;
        }

        _updating = true;
        SetActiveNav(0); // mostrar footer con la progressBar
        App.Progress.Set(0, $"Iniciando descarga de v{meta.Version}...");

        string? dlFile;
        try
        {
            var progress = new Progress<int>(p =>
                App.Progress.Set(p, $"Descargando v{meta.Version}..."));
            dlFile = await App.Updater.DownloadAsync(meta, progress, CancellationToken.None);
        }
        catch (Exception ex)
        {
            App.Progress.Set(0, $"Error en la descarga: {ex.Message}");
            _updating = false;
            return;
        }

        if (dlFile == null)
        {
            App.Progress.Set(0, "Error en la descarga.");
            _updating = false;
            return;
        }

        App.Progress.Set(100, "Verificando integridad SHA256...");

        if (!File.Exists(dlFile))
        {
            System.Windows.MessageBox.Show(
                "La actualizacion se descargo pero el archivo no esta disponible. Es posible que el antivirus lo haya puesto en cuarentena. Se abrira la pagina del release para descargarla manualmente.",
                "WinBoost - Actualizacion", MessageBoxButton.OK, MessageBoxImage.Warning);
            OpenUrl(meta.ReleaseUrl);
            App.Progress.Set(0, "Actualizacion cancelada.");
            _updating = false;
            return;
        }
        if (string.IsNullOrWhiteSpace(meta.Sha256))
        {
            System.Windows.MessageBox.Show(
                "No se puede verificar la integridad de la actualizacion porque falta el hash. Por seguridad no se instalara. Descargala manualmente desde GitHub.",
                "WinBoost - Actualizacion", MessageBoxButton.OK, MessageBoxImage.Warning);
            OpenUrl(meta.ReleaseUrl);
            App.Progress.Set(0, "Actualizacion cancelada.");
            _updating = false;
            return;
        }
        if (!await Task.Run(() => UpdateService.VerifySha256(dlFile, meta.Sha256)))
        {
            System.Windows.MessageBox.Show(
                "La verificacion de la actualizacion fallo: el archivo no coincide con el esperado. Por seguridad no se instalara.",
                "WinBoost - Actualizacion", MessageBoxButton.OK, MessageBoxImage.Error);
            App.Progress.Set(0, "Error: verificacion de integridad fallida.");
            _updating = false;
            return;
        }

        App.Progress.Set(100, "Aplicando actualizacion...");

        bool launched = App.Updater.ApplyUpdate(dlFile);
        if (!launched)
        {
            // Modo desarrollo: no se aplica automaticamente, se abre el release.
            System.Windows.MessageBox.Show(
                "Actualizacion descargada. En modo desarrollo no se aplica automaticamente. Se abrira la pagina del release.",
                "WinBoost - Actualizacion", MessageBoxButton.OK, MessageBoxImage.Information);
            OpenUrl(meta.ReleaseUrl);
            App.Progress.Set(0, "Listo");
            _updating = false;
            return;
        }

        App.Progress.Set(100, "Cerrando para instalar la actualizacion...");
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1000) };
        timer.Tick += (_, _) => { timer.Stop(); Close(); };
        timer.Start();
    }

    private static void OpenUrl(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return;
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch { }
    }

    // ── Tuning Avanzado (6.1, modulos F2.18/F2.19) ───────────────────────────
    // 3 ui:ToggleSwitch (16B). Convencion comun a los 3 Update*Ui: setean SIEMPRE el
    // texto de estado + el IsChecked del switch (bajo _tuningSyncing=true, asi el
    // Checked/Unchecked que dispara nunca re-entra a Set*) — se llaman tanto en la
    // carga inicial (LoadTuningTabAsync) como para revertir el switch si el Set* real
    // tira excepcion o devuelve false, para que la UI nunca muestre un estado que no
    // se pudo aplicar de verdad.

    // Carga lazy del tab: los 3 estados reales del sistema (Politica termica es la
    // unica que pega afuera del proceso -powercfg-, off-UI-thread).
    private async Task LoadTuningTabAsync()
    {
        UpdatePrioUi(App.Tuning.GetWin32PrioritySep());
        UpdateHagsUi(App.Tuning.GetHagsState());

        int cool = await Task.Run(() => App.Tuning.GetCoolingPolicyState());
        UpdateCoolingUi(cool);
    }

    // Scheduler de CPU (Win32PrioritySeparation). ON = 0x28 (decision del usuario,
    // reemplaza el viejo preset "Responsividad" 0x24 - mejores 1% low en su hardware).
    // OFF = default de Windows (2). Estado desconocido (valor tocado por fuera, ni 2 ni
    // 0x28) se muestra OFF: no hay forma honesta de representarlo como "activo" y no
    // debe crashear ni mentir sobre que tweak esta aplicado.
    private void UpdatePrioUi(int value)
    {
        bool isResp = value == 0x28;
        string label = value switch
        {
            0x28 => "Responsividad (0x28) - prioridad al proceso activo",
            2    => "Default de Windows (2) - sin cambio",
            _    => $"Personalizado ({value}, 0x{value:X}) - valor no reconocido, mostrado como inactivo",
        };
        lblPrioState.Text       = $"Estado: {label}";
        lblPrioState.Foreground = isResp ? BrushGreen : BrushLicFree;
        _tuningSyncing = true;
        try { swPrio.IsChecked = isResp; } finally { _tuningSyncing = false; }
    }

    // Mirror del ex btnApplyPrio (ahora Checked/Unchecked de swPrio).
    private void SetPrio(bool on)
    {
        int newVal = on ? 0x28 : 2;
        try
        {
            App.Tuning.SetWin32PrioritySep(newVal);
            UpdatePrioUi(newVal);
            lblPrioStatus.Text       = $"Aplicado: {newVal} (0x{newVal:X}) - efectivo al reiniciar sesion.";
            lblPrioStatus.Foreground = BrushGreen;
            App.Logger.Log($"Win32PrioritySeparation -> {newVal} (0x{newVal:X})", "ok");
        }
        catch (Exception ex)
        {
            UpdatePrioUi(App.Tuning.GetWin32PrioritySep()); // revierte el switch al valor real
            lblPrioStatus.Text       = $"Error al aplicar: {ex.Message}";
            lblPrioStatus.Foreground = BrushRed;
        }
    }

    private void UpdateHagsUi(bool state)
    {
        lblHagsState.Text       = state ? "Estado: Activo" : "Estado: Inactivo";
        lblHagsState.Foreground = state ? BrushGreen : BrushLicFree;
        _tuningSyncing = true;
        try { swHags.IsChecked = state; } finally { _tuningSyncing = false; }
    }

    // Mirror del ex btnHagsOn/btnHagsOff (ahora Checked/Unchecked de swHags).
    private void SetHags(bool enable)
    {
        try
        {
            App.Tuning.SetHagsState(enable);
            UpdateHagsUi(enable);
            lblHagsResult.Text       = "Reinicia el equipo para que tenga efecto.";
            lblHagsResult.Foreground = BrushYellow;
            App.Logger.Log(enable ? "HAGS activado - reinicio requerido"
                                  : "HAGS desactivado - reinicio requerido", "ok");
        }
        catch (Exception ex)
        {
            UpdateHagsUi(!enable); // revierte el switch: la escritura de registro fallo
            lblHagsResult.Text       = $"Error: {ex.Message}";
            lblHagsResult.Foreground = BrushRed;
        }
    }

    private void UpdateCoolingUi(int state)
    {
        (string label, SolidColorBrush brush, bool isOn) = state switch
        {
            1 => ("Activa (ventiladores priorizados)",      BrushGreen,   true),
            0 => ("Pasiva (ahorro antes que temperatura)",  BrushYellow,  false),
            _ => ("No disponible / plan personalizado",     BrushLicFree, false),
        };
        lblCoolState.Text       = $"Modo actual: {label}";
        lblCoolState.Foreground = brush;
        _tuningSyncing = true;
        try { swCool.IsChecked = isOn; } finally { _tuningSyncing = false; }
    }

    // Mirror del ex btnCoolActive/btnCoolPassive (ahora Checked/Unchecked de swCool).
    private async Task SetCoolingPolicyAsync(int value)
    {
        bool ok = await Task.Run(() => App.Tuning.SetCoolingPolicy(value));
        if (ok)
        {
            UpdateCoolingUi(value);
            lblCoolResult.Text       = value == 1 ? "Politica termica activa aplicada."
                                                  : "Politica termica pasiva aplicada.";
            lblCoolResult.Foreground = BrushGreen;
            App.Logger.Log(value == 1 ? "Cooling policy -> Activa" : "Cooling policy -> Pasiva", "ok");
        }
        else
        {
            UpdateCoolingUi(1 - value); // revierte el switch: powercfg no lo acepto
            lblCoolResult.Text       = "No se pudo aplicar. El plan de energia personalizado puede no soportarlo.";
            lblCoolResult.Foreground = BrushRed;
        }
    }

    // Info de componentes (tab Info del sistema; movida desde Tuning).
    // Mirror de New-InfoRow del PS1 (label 160px + valor). La fila de HAGS aca es
    // SOLO informativa; el control de activar/desactivar HAGS vive en la tab Tuning.
    private void RenderComponentsInfo(ExtendedSystemInfo i)
    {
        icComponentsInfo.Items.Clear();
        string cores   = $"{i.CpuCores} nucleos / {i.CpuThreads} hilos";
        string cache   = i.CpuCacheMB > 0 ? $"{i.CpuCacheMB} MB L3" : "N/D";
        string ramSpd  = i.RamSpeedMHz > 0 ? $"{i.RamSpeedMHz} MHz" : "N/D";
        string ramSlot = i.RamSlots > 0 ? $"{i.RamUsedSlots} / {i.RamSlots} slots usados"
                                        : $"{i.RamUsedSlots} modulos";
        string vram    = i.GpuVramMB > 0 ? $"{i.GpuVramMB} MB ({Math.Round(i.GpuVramMB / 1024, 1)} GB)" : "N/D";
        string drv     = string.IsNullOrEmpty(i.GpuDriver) ? "N/D" : i.GpuDriver;
        string hags    = App.Tuning.GetHagsState() ? "Si (activo)" : "No (inactivo)";

        AddInfoRow("CPU - Nucleos/Hilos:", cores);
        AddInfoRow("CPU - Cache L3:",      cache);
        AddInfoRow("RAM - Velocidad:",     ramSpd);
        AddInfoRow("RAM - Slots:",         ramSlot);
        AddInfoRow("GPU:",                 i.GpuName);
        AddInfoRow("GPU - VRAM:",          vram);
        AddInfoRow("GPU - Driver:",        drv);
        AddInfoRow("HAGS:",                hags);
    }

    private void AddInfoRow(string label, string val)
    {
        var g = new Grid { Margin = new Thickness(0, 0, 0, 5) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var l = new TextBlock
        {
            Text = label, FontSize = 12,
            Foreground = (System.Windows.Media.Brush)FindResource("BrushFgMuted"),
        };
        var v = new TextBlock
        {
            Text = val, FontSize = 12, TextWrapping = TextWrapping.Wrap,
            Foreground = (System.Windows.Media.Brush)FindResource("BrushFg1"),
        };
        Grid.SetColumn(v, 1);
        g.Children.Add(l);
        g.Children.Add(v);
        icComponentsInfo.Items.Add(g);
    }

    // Carga la info de componentes en la tab Info. La info extendida (WMI) se lee
    // una sola vez y se cachea; cada vez que se entra a la tab se re-renderiza desde
    // la cache para reflejar el estado actual de HAGS (que puede cambiarse en Tuning).
    private async Task LoadComponentsInfoAsync()
    {
        if (_extendedInfo == null)
        {
            _extendedInfo = await App.Tuning.GetExtendedInfoAsync();
        }
        RenderComponentsInfo(_extendedInfo);
    }

    // Mirror del btnScanDrivers (sin Start-Job: ScanObsoleteDriversAsync corre en Task.Run).
    private async Task ScanObsoleteDriversAsync()
    {
        btnScanDrvStore.IsEnabled  = false;
        btnScanDrvStore.Content    = "Escaneando...";
        lblDriverStatus.Text       = "Ejecutando pnputil /enum-drivers...";
        lblDriverStatus.Foreground = BrushLicFree;
        icDrvStore.Items.Clear();
        _driverChecks.Clear();
        drvListScroll.Visibility = Visibility.Collapsed;

        try
        {
            var pkgs        = await App.Tuning.ScanObsoleteDriversAsync();
            _driverPackages = pkgs;
            icDrvStore.Items.Clear();
            _driverChecks.Clear();

            if (pkgs.Count == 0)
            {
                lblDriverStatus.Text       = "No se encontraron drivers obsoletos en el Driver Store.";
                lblDriverStatus.Foreground = BrushGreen;
                btnDriverBackup.IsEnabled  = false;
                drvListScroll.Visibility   = Visibility.Collapsed;
            }
            else
            {
                foreach (var pkg in pkgs) icDrvStore.Items.Add(BuildDriverRow(pkg));
                lblDriverStatus.Text       = $"{pkgs.Count} driver(s) obsoleto(s) encontrado(s). Haz backup antes de eliminar.";
                lblDriverStatus.Foreground = BrushYellow;
                btnDriverBackup.IsEnabled  = true;
                drvListScroll.Visibility   = Visibility.Visible;
            }
        }
        catch (Exception ex)
        {
            lblDriverStatus.Text       = $"Error al escanear: {ex.Message}";
            lblDriverStatus.Foreground = BrushRed;
        }
        finally
        {
            btnScanDrvStore.IsEnabled = true;
            btnScanDrvStore.Content   = "Escanear drivers";
        }
    }

    private Border BuildDriverRow(DriverPackage pkg)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });

        var chk = new CheckBox { Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        _driverChecks.Add(chk);

        var name = new TextBlock
        {
            Text = $"{pkg.PublishedName}  {pkg.OriginalName}", FontSize = 11,
            Foreground = BrushDriverName, TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(name, 1);

        var ver = new TextBlock
        {
            Text = pkg.DriverVersion, FontSize = 10, Foreground = BrushLicFree,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(ver, 2);

        var date = new TextBlock
        {
            Text = pkg.DriverDate, FontSize = 10, Foreground = BrushDriverDate,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(date, 3);

        grid.Children.Add(chk);
        grid.Children.Add(name);
        grid.Children.Add(ver);
        grid.Children.Add(date);

        return new Border
        {
            Padding = new Thickness(8, 5, 8, 5), Margin = new Thickness(0, 0, 0, 2),
            Background = BrushRowBg, CornerRadius = new CornerRadius(4), Child = grid,
        };
    }

    // Mirror del btnDriverBackup (Export-WindowsDriver).
    private async Task ExportDriverBackupAsync()
    {
        btnDriverBackup.IsEnabled  = false;
        btnDriverBackup.Content    = "Exportando...";
        lblDriverStatus.Text       = "Exportando backup de drivers...";
        lblDriverStatus.Foreground = BrushLicFree;
        try
        {
            string dir = await App.Tuning.ExportDriverBackupAsync();
            _driverBackupDone          = true;
            btnDriverDelete.IsEnabled  = true;
            lblDriverStatus.Text       = $"Backup exportado a: {dir}";
            lblDriverStatus.Foreground = BrushGreen;
            App.Logger.Log($"Driver backup exportado: {dir}", "ok");
        }
        catch (Exception ex)
        {
            lblDriverStatus.Text       = $"Error al exportar backup: {ex.Message}";
            lblDriverStatus.Foreground = BrushRed;
            btnDriverBackup.IsEnabled  = true;
        }
        finally { btnDriverBackup.Content = "Exportar backup de drivers"; }
    }

    // Mirror del btnDriverDelete (pnputil /delete-driver, requiere backup previo).
    private async Task DeleteSelectedDriversAsync()
    {
        if (!_driverBackupDone) return;

        var toDelete = new List<DriverPackage>();
        for (int i = 0; i < _driverPackages.Count && i < _driverChecks.Count; i++)
            if (_driverChecks[i].IsChecked == true) toDelete.Add(_driverPackages[i]);

        if (toDelete.Count == 0)
        {
            lblDriverStatus.Text       = "Selecciona al menos un driver para eliminar.";
            lblDriverStatus.Foreground = BrushYellow;
            return;
        }

        btnDriverDelete.IsEnabled = false;
        int ok = 0, fail = 0;
        foreach (var pkg in toDelete)
        {
            if (await App.Tuning.DeleteDriverAsync(pkg.PublishedName))
            { ok++; App.Logger.Log($"Driver eliminado: {pkg.PublishedName} ({pkg.OriginalName})", "ok"); }
            else
            { fail++; App.Logger.Log($"No se pudo eliminar {pkg.PublishedName}", "err"); }
        }

        lblDriverStatus.Text       = $"{ok} eliminado(s) correctamente. {fail} error(es). Ejecuta 'Escanear' para actualizar la lista.";
        lblDriverStatus.Foreground = fail == 0 ? BrushGreen : BrushYellow;
        _driverBackupDone          = false;
    }

    // ── Liberador de RAM (4.5) ───────────────────────────────────────────────

    // Mirror de Update-RAMDisplay del PS1.
    private async Task UpdateRamDisplayAsync()
    {
        try
        {
            var info = await App.Ram.GetRamInfoAsync();
            lblRAMTotal.Text = $"{info.TotalGb} GB";
            lblRAMUsed.Text  = $"{info.UsedGb} GB";
            lblRAMFree.Text  = $"{info.FreeGb} GB";
        }
        catch { }
    }

    // Mirror del Add_Click de btnFreeRAM del PS1.
    private async Task FreeRamAsync()
    {
        btnFreeRAM.IsEnabled   = false;
        lblRAMFreeStatus.Text  = "Liberando procesos...";
        try
        {
            var result = await App.Ram.FreeRamAsync();

            string sign = result.WorkingSetFreedMb >= 0 ? "+" : "";
            App.Logger.Log(
                $"Working Set liberado: {sign}{result.WorkingSetFreedMb} MB ({result.ProcessCount} procesos)", "ok");

            if (result.StandbyPurged)
                App.Logger.Log(
                    $"Standby List purgada: +{result.StandbyFreedMb} MB adicionales liberados", "ok");
            else
                App.Logger.Log("Purga de Standby List omitida (requiere admin)", "skip");

            await UpdateRamDisplayAsync();

            double totalMb     = result.WorkingSetFreedMb + result.StandbyFreedMb;
            string standbyInfo = result.StandbyFreedMb > 0 ? $" + {result.StandbyFreedMb} MB standby" : "";
            lblRAMFreeStatus.Text =
                $"Completado  |  +{result.WorkingSetFreedMb} MB Working Set{standbyInfo}" +
                $"  |  Total: +{totalMb} MB  |  {result.ProcessCount} procesos";
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error al liberar RAM: {ex.Message}", "err");
            lblRAMFreeStatus.Text = "Error - ver consola";
        }
        finally { btnFreeRAM.IsEnabled = true; }
    }

    // ── Startup manager (4.2) ────────────────────────────────────────────────

    // Mirror de Load-StartupItems + Render-StartupItems del PS1.
    private async Task RefreshStartupAsync()
    {
        btnRefreshStartup.IsEnabled = false;
        lblStartupStatus.Text       = "Actualizando...";
        try
        {
            _startupItems = await App.StartupMgr.GetStartupItemsAsync();
            RenderStartupItems(_startupItems);
            lblStartupStatus.Text = "Lista actualizada";
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error en arranque: {ex.Message}", "err");
            lblStartupStatus.Text = "Error - ver consola";
        }
        finally { btnRefreshStartup.IsEnabled = true; }
    }

    // Mirror de Render-StartupItems del PS1.
    // Grid 5 columnas: Estado-badge(80) | Nombre(180) | Origen-badge(75) | Ruta(Star) | Toggle(95)
    private void RenderStartupItems(IReadOnlyList<StartupItem> items)
    {
        icStartup.Items.Clear();

        var styleOn  = (Style)FindResource("BtnToggleOn");
        var styleOff = (Style)FindResource("BtnToggleOff");

        foreach (var item in items)
        {
            var rowBdr = new Border
            {
                Padding         = new Thickness(12, 5, 12, 5),
                BorderThickness = new Thickness(0, 0, 0, 1),
                BorderBrush     = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(75) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(95) });

            // Col 0 — Badge estado
            var stateBdr = new Border
            {
                CornerRadius        = new CornerRadius(3),
                Padding             = new Thickness(6, 2, 6, 2),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
                Background          = new SolidColorBrush(item.Enabled
                    ? Color.FromRgb(0x0A, 0x2A, 0x0A)
                    : Color.FromRgb(0x22, 0x22, 0x22)),
                Child = new TextBlock
                {
                    Text       = item.Enabled ? "Activo" : "Inactivo",
                    FontSize   = 10,
                    Foreground = item.Enabled ? BrushGreen : BrushGray,
                },
            };
            Grid.SetColumn(stateBdr, 0);

            // Col 1 — Nombre
            var nameTxt = new TextBlock
            {
                Text              = item.Name,
                FontSize          = 12,
                Foreground        = new SolidColorBrush(Color.FromRgb(0xD3, 0xD3, 0xD3)),
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming      = TextTrimming.CharacterEllipsis,
                Margin            = new Thickness(0, 0, 6, 0),
            };
            Grid.SetColumn(nameTxt, 1);

            // Col 2 — Badge origen
            var srcBdr = new Border
            {
                CornerRadius        = new CornerRadius(3),
                Padding             = new Thickness(5, 2, 5, 2),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
                Background          = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x2A)),
                Child = new TextBlock
                {
                    Text       = item.Source,
                    FontSize   = 10,
                    Foreground = new SolidColorBrush(Color.FromRgb(0x77, 0x88, 0xAA)),
                },
            };
            Grid.SetColumn(srcBdr, 2);

            // Col 3 — Ruta
            var pathTxt = new TextBlock
            {
                Text              = item.Path,
                FontSize          = 11,
                Foreground        = new SolidColorBrush(Color.FromRgb(0x44, 0x44, 0x44)),
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming      = TextTrimming.CharacterEllipsis,
                Margin            = new Thickness(8, 0, 8, 0),
            };
            Grid.SetColumn(pathTxt, 3);

            // Col 4 — Boton toggle
            var toggleBtn = new Button
            {
                Content             = item.Enabled ? "Deshabilitar" : "Habilitar",
                Style               = item.Enabled ? styleOn : styleOff,
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            };
            var captured = item;
            toggleBtn.Click += async (_, _) => await ToggleStartupItemAsync(captured);
            Grid.SetColumn(toggleBtn, 4);

            grid.Children.Add(stateBdr);
            grid.Children.Add(nameTxt);
            grid.Children.Add(srcBdr);
            grid.Children.Add(pathTxt);
            grid.Children.Add(toggleBtn);

            rowBdr.Child = grid;
            icStartup.Items.Add(rowBdr);
        }

        int total   = items.Count;
        int activos = items.Count(i => i.Enabled);
        lblStartupCount.Text = $"{total} programas en total  |  {activos} activos  |  {total - activos} deshabilitados";
    }

    // Mirror de Toggle-StartupItem del PS1.
    private async Task ToggleStartupItemAsync(StartupItem item)
    {
        try
        {
            bool newState = await App.StartupMgr.ToggleAsync(item);
            lblStartupStatus.Text = $"{(newState ? "Habilitado" : "Deshabilitado")}: {item.Name}";
            if (_startupItems != null) RenderStartupItems(_startupItems);
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error en arranque: {ex.Message}", "err");
            lblStartupStatus.Text = "Error - ver consola";
        }
    }

    // ── Bloatware (4.1) ──────────────────────────────────────────────────────

    // Mirror de Start-BloatScan del PS1 (modulo 4B).
    private async Task ScanBloatwareAsync()
    {
        btnScanBloat.IsEnabled   = false;
        btnRemoveBloat.IsEnabled = false;
        lblBloatStatus.Text      = "Escaneando...";
        lblBloatCount.Text       = "...";
        lblBloatMB.Text          = "...";

        try
        {
            var list    = await App.Bloatware.GetBloatwareListAsync();
            _bloatList  = list;
            var summary = App.Bloatware.GetSummary(list);

            lblBloatCount.Text   = $"{summary.Count}";
            lblBloatMB.Text      = $"{summary.TotalMB}";
            lblBloatSafe.Text    = $"{summary.SafeCount}";
            lblBloatCaution.Text = $"{summary.CautionCount}";

            bool wingetOk = await Task.Run(() => App.Bloatware.IsWingetAvailable());
            lblBloatWinget.Text = wingetOk
                ? "winget disponible"
                : "winget no detectado - apps Win32/OEM no escaneadas";

            string filter = GetBloatFilterText();
            RenderBloatItems(list, filter);

            lblBloatStatus.Text = summary.Count == 0
                ? "Sin bloatware detectado"
                : "Escaneo completado";
        }
        catch (Exception ex)
        {
            App.Logger.Log($"Error en escaneo bloatware: {ex.Message}", "err");
            lblBloatStatus.Text = "Error - ver consola";
        }
        finally { btnScanBloat.IsEnabled = true; }
    }

    // Mirror de Render-BloatItems del PS1 (modulo 4B).
    // Grid 6 columnas: Checkbox(32) | Nombre(Star) | Categoria(100) | Metodo(70) | MB(75) | Riesgo(80)
    private void RenderBloatItems(IReadOnlyList<DetectedApp> list, string filterCategory)
    {
        icBloat.Items.Clear();
        _bloatChecks.Clear();

        var filtered = filterCategory == "Todas las categorias"
            ? list
            : (IReadOnlyList<DetectedApp>)list
                .Where(a => a.Category == filterCategory)
                .ToList();

        if (filtered.Count == 0)
        {
            icBloat.Items.Add(new TextBlock
            {
                Text         = list.Count == 0
                    ? "✓  Sistema limpio — No se detecto bloatware instalado en este equipo."
                    : "Sin apps en esta categoria.",
                Foreground   = BrushGreen,
                FontSize     = 12,
                Margin       = new Thickness(8, 16, 8, 16),
                TextWrapping = TextWrapping.Wrap,
            });
            btnRemoveBloat.IsEnabled = false;
            lblBloatSelected.Text    = "0 apps seleccionadas  |  0 MB estimados";
            return;
        }

        for (int i = 0; i < filtered.Count; i++)
        {
            var app = filtered[i];
            int idx = i;

            var rowBdr = new Border
            {
                Padding         = new Thickness(14, 7, 14, 7),
                BorderThickness = new Thickness(0, 0, 0, 1),
                BorderBrush     = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(75) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });

            // Col 0 — Checkbox (pre-marcado si es "safe")
            var chk = new CheckBox
            {
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                IsChecked           = app.Risk == "safe",
            };
            chk.Click += (_, _) => UpdateBloatStats();
            Grid.SetColumn(chk, 0);
            _bloatChecks[idx] = chk;

            // Col 1 — Nombre
            var nameTxt = new TextBlock
            {
                Text              = app.Name,
                FontSize          = 12,
                Foreground        = new SolidColorBrush(Color.FromRgb(0xCC, 0xCC, 0xCC)),
                TextTrimming      = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
                Margin            = new Thickness(0, 0, 8, 0),
            };
            Grid.SetColumn(nameTxt, 1);

            // Col 2 — Badge categoria
            var (catFg, catBg) = app.Category switch
            {
                "Juegos"       => (Color.FromRgb(0x00, 0xC8, 0xFF), Color.FromRgb(0x0D, 0x1F, 0x2D)),
                "Comunicacion" => (Color.FromRgb(0xA8, 0x55, 0xF7), Color.FromRgb(0x1A, 0x0D, 0x2D)),
                "Telemetria"   => (Color.FromRgb(0xEF, 0x44, 0x44), Color.FromRgb(0x2A, 0x0A, 0x0A)),
                "OEM"          => (Color.FromRgb(0xF5, 0x9E, 0x0B), Color.FromRgb(0x2A, 0x1A, 0x00)),
                _              => (Color.FromRgb(0x88, 0x88, 0x88), Color.FromRgb(0x1A, 0x1A, 0x1A)),
            };
            var catBdr = new Border
            {
                CornerRadius      = new CornerRadius(3),
                Padding           = new Thickness(6, 2, 6, 2),
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
                Background        = new SolidColorBrush(catBg),
                Child             = new TextBlock
                {
                    Text       = app.Category,
                    FontSize   = 10,
                    Foreground = new SolidColorBrush(catFg),
                },
            };
            Grid.SetColumn(catBdr, 2);

            // Col 3 — Badge metodo de remocion
            var (methodFg, methodLabel) = app.Method switch
            {
                "appx"        => (Color.FromRgb(0x55, 0x55, 0x55), "AppX"),
                "winget"      => (Color.FromRgb(0x22, 0xC5, 0x5E), "winget"),
                "appx+winget" => (Color.FromRgb(0x00, 0xC8, 0xFF), "AppX+wg"),
                _             => (Color.FromRgb(0x55, 0x55, 0x55), app.Method),
            };
            var mthBdr = new Border
            {
                CornerRadius        = new CornerRadius(3),
                Padding             = new Thickness(5, 2, 5, 2),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
                Background          = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
                Child               = new TextBlock
                {
                    Text       = methodLabel,
                    FontSize   = 10,
                    Foreground = new SolidColorBrush(methodFg),
                },
            };
            Grid.SetColumn(mthBdr, 3);

            // Col 4 — Espacio estimado
            var mbTxt = new TextBlock
            {
                Text              = $"~{app.EstimateMB} MB",
                FontSize          = 11,
                Foreground        = new SolidColorBrush(Color.FromRgb(0x66, 0x66, 0x66)),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(mbTxt, 4);

            // Col 5 — Badge riesgo
            bool   isSafe   = app.Risk == "safe";
            var    riskFg   = isSafe ? Color.FromRgb(0x22, 0xC5, 0x5E) : Color.FromRgb(0xF5, 0x9E, 0x0B);
            var    riskBg   = isSafe ? Color.FromRgb(0x0A, 0x2A, 0x0A) : Color.FromRgb(0x2A, 0x1A, 0x00);
            string riskLbl  = isSafe ? "Seguro" : "Precaucion";
            var riskBdr = new Border
            {
                CornerRadius        = new CornerRadius(3),
                Padding             = new Thickness(7, 2, 7, 2),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                Background          = new SolidColorBrush(riskBg),
                BorderBrush         = new SolidColorBrush(riskFg),
                BorderThickness     = new Thickness(1),
                Child               = new TextBlock
                {
                    Text       = riskLbl,
                    FontSize   = 10,
                    Foreground = new SolidColorBrush(riskFg),
                },
            };
            Grid.SetColumn(riskBdr, 5);

            grid.Children.Add(chk);
            grid.Children.Add(nameTxt);
            grid.Children.Add(catBdr);
            grid.Children.Add(mthBdr);
            grid.Children.Add(mbTxt);
            grid.Children.Add(riskBdr);

            rowBdr.Child = grid;
            icBloat.Items.Add(rowBdr);
        }

        UpdateBloatStats();
    }

    // Mirror de Update-BloatStats del PS1.
    private void UpdateBloatStats()
    {
        if (_bloatList == null) return;

        // Necesitamos alinear el indice de checks con la lista filtrada actual.
        // Como _bloatChecks se reconstruye en cada RenderBloatItems con indices 0..N-1
        // correspondientes a `filtered`, usamos solo lo que hay.
        int  selCount = 0;
        int  selMB    = 0;

        // Construir lista filtrada actual para acceder al EstimateMB por indice
        string filter   = GetBloatFilterText();
        var    filtered = filter == "Todas las categorias"
            ? _bloatList
            : (IReadOnlyList<DetectedApp>)_bloatList
                .Where(a => a.Category == filter)
                .ToList();

        foreach (var (idx, chk) in _bloatChecks)
        {
            if (chk.IsChecked == true && idx < filtered.Count)
            {
                selCount++;
                selMB += filtered[idx].EstimateMB;
            }
        }

        lblBloatSelected.Text    = $"{selCount} app(s) seleccionada(s)  |  ~{selMB} MB estimados";
        btnRemoveBloat.IsEnabled = selCount > 0;
    }

    // Selecciona solo los items marcados como "safe" en la vista actual.
    // Mirror de btnBloatSelAll del PS1.
    private void BloatSelectSafe()
    {
        if (_bloatList == null) return;
        string filter  = GetBloatFilterText();
        var    filtered = filter == "Todas las categorias"
            ? _bloatList
            : (IReadOnlyList<DetectedApp>)_bloatList.Where(a => a.Category == filter).ToList();

        foreach (var (idx, chk) in _bloatChecks)
        {
            if (idx < filtered.Count)
                chk.IsChecked = filtered[idx].Risk == "safe";
        }
        UpdateBloatStats();
    }

    private void BloatSelectNone()
    {
        foreach (var chk in _bloatChecks.Values)
            chk.IsChecked = false;
        UpdateBloatStats();
    }

    // Filtro de categoria: re-renderiza desde el cache.
    private void OnBloatFilterChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_bloatList == null) return;
        if (e.Source != cboBloatFilter) return;
        RenderBloatItems(_bloatList, GetBloatFilterText());
    }

    // Texto de la categoria seleccionada en el combo.
    private string GetBloatFilterText()
    {
        try
        {
            if (cboBloatFilter.SelectedItem is ComboBoxItem item)
                return item.Content?.ToString() ?? "Todas las categorias";
        }
        catch { }
        return "Todas las categorias";
    }

    // Mirror de Invoke-RemoveBloat del PS1 (modulo 4C).
    private async Task InvokeRemoveBloatAsync()
    {
        // Gate Pro: desinstalar bloatware (5.1)
        if (LockProFeature("Desinstalar bloatware")) return;

        if (_bloatList == null || App.Worker.IsRunning) return;

        // Recopilar items seleccionados en el orden del filtro actual
        string filter  = GetBloatFilterText();
        var    filtered = filter == "Todas las categorias"
            ? _bloatList
            : (IReadOnlyList<DetectedApp>)_bloatList.Where(a => a.Category == filter).ToList();

        var toRemove = _bloatChecks
            .Where(kv => kv.Value.IsChecked == true && kv.Key < filtered.Count)
            .OrderBy(kv => kv.Key)
            .Select(kv => filtered[kv.Key])
            .ToList();

        if (toRemove.Count == 0) return;

        // Separar seguros y de precaucion para el mensaje de confirmacion
        var safeItems    = toRemove.Where(a => a.Risk == "safe").ToList();
        var cautionItems = toRemove.Where(a => a.Risk == "caution").ToList();
        int totalMB      = toRemove.Sum(a => a.EstimateMB);

        string confirmMsg =
            $"Vas a desinstalar {toRemove.Count} app(s):\n" +
            $"  Seguras:    {safeItems.Count}\n" +
            $"  Precaucion: {cautionItems.Count}\n" +
            $"  Espacio estimado: ~{totalMB} MB\n\n";

        if (cautionItems.Count > 0)
        {
            confirmMsg += "Apps marcadas como Precaucion:\n";
            foreach (var a in cautionItems) confirmMsg += $"  - {a.Name}\n";
            confirmMsg += "\n";
        }
        confirmMsg += "Esta accion no es facilmente reversible.\nContinuar?";

        var confirm = System.Windows.MessageBox.Show(
            confirmMsg,
            "WinBoost - Desinstalar bloatware",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes) return;

        // Deshabilitar UI y navegar a la consola
        btnScanBloat.IsEnabled    = false;
        btnRemoveBloat.IsEnabled  = false;
        btnBloatSelAll.IsEnabled  = false;
        btnBloatSelNone.IsEnabled = false;
        SetActiveNav(5); // Consola — log en tiempo real

        // Guardar backup de lo que se va a eliminar
        if (App.Backup.ActiveSession is { } sessionPath)
            App.Bloatware.SaveBloatBackup(sessionPath, toRemove);
        else
        {
            App.Backup.NewBackupSession();
            if (App.Backup.ActiveSession is { } sp2)
                App.Bloatware.SaveBloatBackup(sp2, toRemove);
        }

        App.Logger.Log("DESINSTALACION DE BLOATWARE", "head");
        App.Logger.Log($"{toRemove.Count} app(s) seleccionadas - ~{totalMB} MB estimados", "info");

        int okCount   = 0;
        int failCount = 0;

        await App.Worker.RunAsync(async ct =>
        {
            for (int i = 0; i < toRemove.Count; i++)
            {
                ct.ThrowIfCancellationRequested();
                var app = toRemove[i];
                int pct = (int)Math.Round((i + 1.0) / toRemove.Count * 100);
                App.Progress?.Set(pct, $"Desinstalando: {app.Name}...");
                App.Logger.Log($"Desinstalando: {app.Name}", "info");

                var res = await App.Bloatware.RemoveAppAsync(app, ct);
                if (res.Ok)
                {
                    App.Logger.Log($"{app.Name} - {res.Message}", "ok");
                    okCount++;
                }
                else
                {
                    App.Logger.Log($"{app.Name} - {res.Message}", "err");
                    failCount++;
                }
            }
        },
        startMsg: "Iniciando desinstalacion de bloatware...",
        doneMsg:  $"Desinstalacion completada: {okCount} ok  {failCount} fallidos");

        App.Progress?.Set(100, "Desinstalacion completada");
        App.Logger.Log(
            $"Desinstalacion completada: {okCount} ok  {failCount} fallidos",
            failCount == 0 ? "ok" : "err");

        // Rehabilitar UI
        btnScanBloat.IsEnabled    = true;
        btnBloatSelAll.IsEnabled  = true;
        btnBloatSelNone.IsEnabled = true;

        // Re-escanear automaticamente para reflejar cambios
        SetActiveNav(4); // Bloatware
        await ScanBloatwareAsync();

        string resultMsg = okCount > 0
            ? $"Desinstalacion completada.\n\n{okCount} app(s) eliminadas correctamente." +
              (failCount > 0 ? $"\n{failCount} fallaron - revisa la consola para detalles." : "")
            : "No se pudo desinstalar ninguna app.\nRevisa la consola para ver los detalles de cada error.";

        System.Windows.MessageBox.Show(
            resultMsg,
            okCount > 0 ? "WinBoost - Bloatware eliminado" : "WinBoost - Error en desinstalacion",
            MessageBoxButton.OK,
            okCount > 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
    }

    // Confirmación + kill (mirror del Add_Click del killBtn en PS1).
    private async Task OnKillProcessAsync(int pid, string name)
    {
        var confirm = System.Windows.MessageBox.Show(
            $"Terminar el proceso '{name}' (PID {pid})?\n\nLos datos no guardados se perderan.",
            "WinBoost - Terminar proceso",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes) return;

        var result = await App.Processes.StopProcessAsync(pid);
        if (result.Ok)
        {
            App.Logger.Log(result.Message, "ok");
            await RefreshProcessListAsync();
        }
        else
        {
            App.Logger.Log(result.Message, "err");
            System.Windows.MessageBox.Show(result.Message, "WinBoost - Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
