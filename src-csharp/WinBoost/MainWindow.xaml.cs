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

    // GPU usage (fix 30): counters persistentes de "GPU Engine" (rebuild periodico por churn de
    // instancias por-proceso). _lastGpuPct = -1 => no disponible / aun sin lectura.
    private readonly List<PerformanceCounter> _gpuCounters = [];
    private int   _gpuRebuildTick = 100; // fuerza (re)build en la primera lectura
    private float _lastGpuPct     = -1f;


    // Procesos (2.4): timer de auto-refresh + guard de lectura concurrente
    private DispatcherTimer? _procTimer;
    private bool             _procTimerRunning  = false;
    private bool             _procRefreshing    = false;
    private bool             _procLoaded        = false;  // carga lazy al entrar a Herramientas
    private const int        ProcTimerIntervalSec = 3;

    // Cache del system info, reusada por varias secciones (Limpieza, TRIM, Reporte HTML ex-3.1)
    private SystemSnapshot?  _systemInfo;

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

    // Estado del Driver Store (seccion Limpieza desde el prompt 75; antes en Herramientas).
    // _tuningLoaded/_tuningSyncing (6.1, los 3 toggles de la ex pestana Tuning Avanzado) se
    // eliminaron en el prompt 56 -- migraron a la seccion Tweaks (ver _tweaksSyncing abajo).
    private IReadOnlyList<DriverPackage> _driverPackages = [];
    private readonly List<CheckBox> _driverChecks = [];
    private bool _driverBackupDone = false;

    // Tweaks (piloto Fase A, 38_fase_a_registro_tweaks_piloto.txt): carga lazy + mismo patron
    // _syncing que Tuning Avanzado (evita que cargar el estado inicial dispare Aplicar/Revertir).
    private bool _tweaksLoaded  = false;
    private bool _tweaksSyncing = false;
    // ResetPanel (prompt 71): panel "Restablecer a default de Windows", != null solo para los 20
    // tweaks "Seguro" (def.RestablecerDefaultAsync != null). UpdateTweakCardUi decide su
    // visibilidad (On + sin Original capturado). null para el resto.
    private readonly Dictionary<string, (Wpf.Ui.Controls.ToggleSwitch Switch, TextBlock Status, StackPanel? ResetPanel)> _tweakCardRefs = [];

    // Card "Tweaks activos" del Home (prompt 62, reemplaza a la vieja "Ultima optimizacion" atada a
    // BackupSessionInfo). Cache en memoria SOLO -- no tiene sentido persistirla entre sesiones, es
    // un conteo "ahora mismo". null = todavia no se barrieron los 27 TweakDefinition ni una vez.
    private int? _activeTweaksCount;
    private bool _activeTweaksLoading;
    // Prompt 63: si un Aplicar/Revertir toca cualquier tweak MIENTRAS el barrido inicial todavia
    // esta en vuelo, el numero que ese barrido termine leyendo puede no reflejar ese cambio (el
    // LeerEstadoAsync de ESE tweak especifico pudo haber corrido antes del cambio real) -- y como
    // el mecanismo nunca vuelve a barrer despues del primer calculo (solo incrementa de ahi en
    // mas), ese desfasaje quedaria fijo por el resto de la sesion. AdjustActiveTweaksCache marca
    // esto en true mientras _activeTweaksLoading es true; UpdateActiveTweaksCardAsync lo usa para
    // descartar el resultado del barrido y repetirlo en vez de cachear un numero que ya sabe que
    // esta desactualizado.
    private bool _activeTweaksDirtyDuringSweep;
    // Ultimo TweakState conocido por Id, para poder calcular el delta (+1/-1) cuando un
    // Aplicar/Revertir individual cambia el estado real, sin tener que re-barrer los 27. Se
    // alimenta gratis desde UpdateTweakCardUi (todo render de una card pasa por ahi), tanto en la
    // carga inicial de Tweaks/Network como en cada Aplicar/Revertir.
    private readonly Dictionary<string, TweakState> _lastKnownTweakState = [];

    // Network (Fase C, Paso 1, 47_fase_c_paso1_seccion_network.txt): panel hermano de Tweaks, misma
    // mecanica de carga lazy -- comparte _tweakCardRefs/_tweaksSyncing con Tweaks (dict indexado por
    // Id de tweak, unico en todo el registro, asi que convive sin choques entre los dos paneles).
    private bool _networkLoaded = false;
    // Limpieza (Fase C, Paso 3, 49_fase_c_paso3_seccion_limpieza.txt): sin dictionary de card refs
    // propio -- es UNA sola card con checkboxes + boton, no una lista de N cards generadas.
    private bool _limpiezaLoaded = false;

    private static readonly SolidColorBrush BrushGreen  = FreezeBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
    private static readonly SolidColorBrush BrushYellow = FreezeBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
    private static readonly SolidColorBrush BrushRed    = FreezeBrush(Color.FromRgb(0xEF, 0x44, 0x44));
    private static readonly SolidColorBrush BrushBlue   = FreezeBrush(Color.FromRgb(0x00, 0xC8, 0xFF));
    private static readonly SolidColorBrush BrushGray   = FreezeBrush(Color.FromRgb(0x55, 0x55, 0x55));

    // Licencias (5.1): gris del estado Free (reusado por varias cards). Los brushes del
    // banner de trial (BrushTrialBg/Bd, BrushExpBg/Bd) se eliminaron con el trial (prompt 82).
    private static readonly SolidColorBrush BrushLicFree = FreezeBrush(Color.FromRgb(0x88, 0x88, 0x88));

    // Tuning (6.1): colores de las filas del Driver Store
    private static readonly SolidColorBrush BrushRowBg     = FreezeBrush(Color.FromRgb(0x11, 0x11, 0x11));
    private static readonly SolidColorBrush BrushDriverName = FreezeBrush(Color.FromRgb(0xDD, 0xDD, 0xDD));
    private static readonly SolidColorBrush BrushDriverDate = FreezeBrush(Color.FromRgb(0x66, 0x66, 0x66));

    // nav buttons indexados por TAB (0-10 tras eliminar la pestaña Consola, fix 27, y la pestaña
    // Tuning Avanzado, prompt 56; navTweaks = 8 desde el piloto Fase A). navConsola NO esta aca:
    // dejo de ser tab y ahora abre el overlay.
    private Button[] _navButtons = [];
    // Subconjunto que usa el estilo de ICONO (fila inferior del sidebar): Ajustes y Licencia.
    // navConsola tambien es icono pero se maneja aparte (no mapea a tab). Fix 27.
    private Button[] _iconNavButtons = [];

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
        // Indexado por TAB (0-9). Consola abre overlay (fuera del array). Fix 30: el tab index de
        // Home (ex Info del sistema) -> navHome ocupa esa posicion; navInfo se elimino.
        // Prompt 56: navTuning se elimino (pestana Tuning Avanzado retirada, migrada a Tweaks) --
        // Tweaks/Network/Limpieza corrieron un indice hacia abajo (9/10/11 -> 8/9/10).
        // Prompt 66: navOptimizar se elimino (tab Optimizar clasico retirado) -- TODOS los indices
        // corrieron un lugar hacia abajo (era 0-10 con Optimizar=0/Home=2, ahora 0-9 con Home=1).
        // Prompt 78: el sidebar se reordeno VISUALMENTE (Tweaks/Network/Limpieza pasaron a PRINCIPAL,
        // Herramientas a SISTEMA, se sacaron los headers de segmento) -- este array y el orden de las
        // TabItem NO cambiaron, solo el orden de los <Button> en el StackPanel del sidebar.
        _navButtons =
        [
            navHerramientas, // 0  (era 1)
            navHome,         // 1  (era navInfo; el tab index ahora es Home; era 2)
            navArranque,     // 2  (era 3)
            navBloatware,    // 3  (era 4)
            navHistorial,    // 4  (era 5)
            navAjustes,      // 5  — icono (era 6)
            navLicencia,     // 6  — icono (era 7)
            navTweaks,       // 7  — piloto Fase A (era 8)
            navNetwork,      // 8  — Fase C, Paso 1 (era 9)
            navLimpieza,     // 9  — Fase C, Paso 3 (era 10)
        ];
        _iconNavButtons = [navAjustes, navLicencia];

        navHerramientas.Click += (_, _) => SetActiveNav(0);   // era 1, prompt 66 (retiro tab Optimizar)
        navHome.Click         += (_, _) => SetActiveNav(1);   // Home (ex Info, fix 30; era 2)
        navArranque.Click     += (_, _) => SetActiveNav(2);   // era 3
        navBloatware.Click    += (_, _) => SetActiveNav(3);   // era 4
        navHistorial.Click    += (_, _) => SetActiveNav(4);   // era 5
        navAjustes.Click      += (_, _) => SetActiveNav(5);   // era 6
        navLicencia.Click     += (_, _) => SetActiveNav(6);   // era 7
        navTweaks.Click       += (_, _) => SetActiveNav(7);   // Tweaks (era 8, prompt 56 lo dejo en 8; era 9)
        navNetwork.Click      += (_, _) => SetActiveNav(8);   // Network, Fase C Paso 1 (era 9)
        navLimpieza.Click     += (_, _) => SetActiveNav(9);   // Limpieza, Fase C Paso 3 (era 10)
        // Consola: el icono ABRE EL OVERLAY en modo consulta (no navega a ninguna tab).
        navConsola.Click      += (_, _) => OpenConsoleOverlay(running: false);

        // Network / DNS (Fase C, Paso 2, 48_fase_c_paso2_dns_dnsflush.txt): card propia, no
        // generada por BuildTweakCard -- Aplicar/Restaurar son dos botones separados, no un toggle.
        btnNetDnsApply.Click += async (_, _) =>
        {
            btnNetDnsApply.IsEnabled = false;
            try
            {
                var provider = OptimizationService.DnsProviders[cboNetDnsProvider.SelectedIndex];
                await DnsPresetService.ApplyAsync(provider);
                await RefreshDnsCardAsync();
            }
            catch (Exception ex)
            {
                lblNetDnsStatus.Text       = $"Error al aplicar: {ex.Message}";
                lblNetDnsStatus.Foreground = BrushRed;
            }
            finally { btnNetDnsApply.IsEnabled = true; }
        };
        btnNetDnsRestore.Click += async (_, _) =>
        {
            btnNetDnsRestore.IsEnabled = false;
            try
            {
                await DnsPresetService.RestoreAsync();
                await RefreshDnsCardAsync(); // recalcula IsEnabled segun HasOriginalCaptured()
            }
            catch (Exception ex)
            {
                lblNetDnsStatus.Text       = $"Error al restaurar: {ex.Message}";
                lblNetDnsStatus.Foreground = BrushRed;
                btnNetDnsRestore.IsEnabled = true;
            }
        };

        // Limpieza (Fase C, Paso 3, 49_fase_c_paso3_seccion_limpieza.txt): dialogo de confirmacion
        // (mismo ConfirmOptimizationDialog del tab Optimizar clasico) + OptimizationService.
        // CleanupTweaks (subida a internal para reusarla sin duplicar las 8 rutinas de borrado).
        btnRunLimpieza.Click += async (_, _) => await RunLimpiezaAsync();

        // TRIM/Desfrag (Fase C, Paso 4, tab Herramientas): App.Worker.RunAsync + OpenConsoleOverlay,
        // el mismo mecanismo ya usado por la optimizacion completa y por Desinstalar bloatware --
        // "Detener" del overlay ya cancela via App.Worker.Cancel() de forma generica, sin cablear
        // un boton propio.
        btnRunTrim.Click += async (_, _) => await RunTrimAsync();

        // Home (fix 30): botones de bienvenida + card de tweaks activos (prompt 62).
        btnHomeSysInfo.Click     += (_, _) => OpenSystemInfoOverlay();
        // Prompt 66: el tab Optimizar clasico se retiro -- btnHomeOptimize ahora lleva a Tweaks
        // (antes SetActiveNav(0), el indice viejo del tab clasico).
        btnHomeOptimize.Click    += (_, _) => SetActiveNav(7);
        btnHomeViewTweaks.Click += (_, _) => SetActiveNav(7); // Tweaks (prompt 62, era 8; prompt 66 lo corrio a 7)
        // Fase C, Paso 5: QuickActionDefinition "RestorePoint" -- resultado via ShowToast, mismo
        // mecanismo que ya usa Home para el resumen post-optimizacion (no una card dedicada).
        btnHomeRestorePoint.Click += async (_, _) =>
        {
            btnHomeRestorePoint.IsEnabled = false;
            try
            {
                var action = App.QuickActions.Find("RestorePoint");
                if (action is not null) ShowToast(await action.EjecutarAsync());
            }
            catch (Exception ex) { ShowToast($"Error: {ex.Message}"); }
            finally { btnHomeRestorePoint.IsEnabled = true; }
        };
        // System Info overlay: siempre cerrable (no hay operacion que proteger).
        btnSysInfoClose.Click += (_, _) => CloseSystemInfoOverlay();
        systemInfoOverlay.MouseLeftButtonDown += (_, e) =>
        {
            if (e.OriginalSource == systemInfoOverlay) CloseSystemInfoOverlay();
        };

        App.Settings.Load();
        App.Settings.Apply(this);

        App.Logger   = new AppLogger(rtbLog, logScroll, btnErrBadge, lblErrCount);
        // Progreso SOLO en el overlay de consola (fix 28.3): la barra de Optimizar se removio,
        // asi que ProgressService apunta directo a los controles del overlay.
        App.Progress = new ProgressService(progressBarConsole, lblProgressConsole, lblPctConsole);

        // Badge de errores -> abre el OVERLAY en modo consulta Y limpia el cartel visible (fix 28.4):
        // ClearErrorBadge oculta el badge y resetea el conteo visible SIN borrar los errores del log.
        btnErrBadge.Click += (_, _) => { App.Logger.ClearErrorBadge(); OpenConsoleOverlay(running: false); };
        // Overlay de consola (fix 27): "Detener" cancela la operacion en curso via el CTS
        // compartido de App.Worker (mismo path que btnCancelOpt); "Cerrar" cierra el modal.
        btnConsoleStop.Click  += (_, _) => App.Worker.Cancel();
        btnConsoleClose.Click += (_, _) => CloseConsoleOverlay();
        // Cierre modal condicional (fix 28.6): click en el SCRIM (fuera del panel) cierra el overlay
        // SOLO si no hay operacion corriendo. e.OriginalSource == consoleOverlay identifica el click
        // en el area del scrim (no en el panel ni sus hijos). Mientras corre una operacion, no cierra.
        consoleOverlay.MouseLeftButtonDown += (_, e) =>
        {
            if (e.OriginalSource == consoleOverlay && !_consoleOperationRunning)
                CloseConsoleOverlay();
        };
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
        // Reestructuracion 25: el scoreWidget (SALUD) se saco del header y quedo parkeado
        // colapsado; su deep-link (click -> Info) se remueve por ser inalcanzable. La SALUD
        // visible/navegable vive ahora en Info Sistema.
        btnRecalcScore.Click += async (_, _) => await RecalcScoreAsync();

        // Procesos (2.4)
        btnRefreshProcs.Click     += async (_, _) => await RefreshProcessListAsync();
        btnToggleProcTimer.Click  += (_, _) => ToggleProcTimer();
        chkShowSysProcs.Click     += async (_, _) => await RefreshProcessListAsync();

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

        // Mantenimiento automatico (4.3) -- prompt 75: la seccion vive ahora en Limpieza (el
        // cableado no cambia, los controles son los mismos x:Name movidos en el arbol XAML).
        for (int h = 0; h <= 23; h++)
            cboMaintHour.Items.Add(new ComboBoxItem { Content = $"{h:D2}:00" });
        cboMaintHour.SelectedIndex = 10;
        cboMaintFreq.SelectionChanged += (_, _) =>
            cboMaintHour.IsEnabled = cboMaintFreq.SelectedIndex != 2;
        tglMaintenance.Click   += async (_, _) => await ToggleMaintenanceAsync();
        btnRunMaintNow.Click   += async (_, _) => await RunMaintenanceNowAsync();
        _ = UpdateMaintUIAsync();

        // Liberador de RAM (4.5) — los labels RAM los mantiene el monitor (1s);
        // solo cableamos el boton de purga.
        btnFreeRAM.Click += async (_, _) => await FreeRamAsync();

        // Historial + score history (4.6)
        btnRefreshHistory.Click   += async (_, _) => await RefreshHistoryAsync();
        btnOpenBackupFolder.Click += (_, _) => OpenBackupFolder();
        btnRevertLast.Click       += async (_, _) => await RevertLastSessionAsync();

        // Reporte HTML (4.7) -- prompt 66: sin fuente de datos tras retirar el tab Optimizar
        // clasico (ExportHtmlReportAsync dependia de _lastReportActions/_lastFreedMb/_scoreBefore,
        // solo poblados por ese flujo). btnExportHTML se oculta en el XAML del overlay de Consola
        // (Visibility="Collapsed") en vez de exportar datos vacios para siempre; sin caller,
        // ExportHtmlReportAsync se elimino del code-behind.

        // Licencias (5.1, modulo 12C). El banner de trial de Home y su boton "Activar Pro"
        // (btnTrialUpgrade) se eliminaron en el prompt 82 junto con el trial; la pestaña
        // Licencia sigue accesible desde el icono navLicencia del sidebar.
        btnCopyHWID.Click        += (_, _) => CopyHardwareId();
        btnActivateLicense.Click += (_, _) => ActivateLicense();
        btnGetLicense.Click      += (_, _) => GetLicense();
        _ = InitLicenseAsync();

        // Auto-updater (5.3, modulo 14)
        Title             = $"WinBoost v{App.Version}";
        lblVersion.Text   = $"v{App.Version}";
        lblVersionAbout.Text = $"v{App.Version}";
        badgeUpdate.MouseLeftButtonUp += (_, _) => OnUpdateBadgeClick();
        btnCheckUpdatesSettings.Click += async (_, _) => await CheckForUpdatesAsync(manual: true);
        _ = CheckForUpdatesAsync(manual: false);

        // Limpieza del Driver Store -- prompt 75: la seccion se movio de Herramientas a Limpieza
        // (el cableado y los handlers no cambian; TuningService sigue siendo el servicio). Los 3
        // ui:ToggleSwitch 16B de la ex pestana Tuning Avanzado migraron a Tweaks en el prompt 56.
        btnScanDrvStore.Click += async (_, _) => await ScanObsoleteDriversAsync();
        btnDriverBackup.Click += async (_, _) => await ExportDriverBackupAsync();
        btnDriverDelete.Click += async (_, _) => await DeleteSelectedDriversAsync();

        // Ajustes: tema + seccion de mantenimiento/backup (BUG 3 y 4)
        WireSettingsControls();

        // Toast in-app (BUG 6): al vencer el timer, oculta el toast
        _toastTimer.Tick += (_, _) => { _toastTimer.Stop(); toastHost.Visibility = Visibility.Collapsed; };

        SetActiveNav(1); // Home = entrada de la app (fix 30; era 2, prompt 66)
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

        var txtActive   = (Style)FindResource("BtnNavActive");
        var txtInactive = (Style)FindResource("BtnNav");
        var icoActive   = (Style)FindResource("BtnNavIconActive");
        var icoInactive = (Style)FindResource("BtnNavIcon");

        // Cada boton usa el estilo segun sea item de texto o icono (fila inferior, fix 27):
        // aplicar el estilo de texto a un boton-icono lo rompe visualmente, y viceversa.
        for (int i = 0; i < _navButtons.Length; i++)
        {
            bool active = i == index;
            bool isIcon = Array.IndexOf(_iconNavButtons, _navButtons[i]) >= 0;
            _navButtons[i].Style = isIcon
                ? (active ? icoActive : icoInactive)
                : (active ? txtActive : txtInactive);
        }
        // navConsola (icono, fuera del array) nunca queda activo por tab: pill solo en hover o
        // mientras el overlay esta abierto (eso lo maneja OpenConsoleOverlay/CloseConsoleOverlay).
        if (consoleOverlay.Visibility != Visibility.Visible)
            navConsola.Style = icoInactive;

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

    // ── Consola overlay (fix 27) ─────────────────────────────────────────────
    // La consola dejo de ser pestaña: ahora es un overlay MODAL. Se abre en modo OPERACION
    // (running:true) cuando arranca una tarea con output (optimizacion, bloatware) — muestra
    // "Detener" y bloquea "Cerrar" hasta terminar/cancelar; o en modo CONSULTA (running:false)
    // desde el icono navConsola o el badge de errores — sin "Detener", "Cerrar" habilitado,
    // mostrando el log acumulado de la sesion (el rtbLog nunca se limpio solo).
    // _consoleOperationRunning gobierna el cierre modal condicional (fix 28.6): mientras es true,
    // ni el click en el scrim ni "Cerrar" cierran el overlay (solo "Detener" o terminar).
    private bool _consoleOperationRunning;

    private void OpenConsoleOverlay(bool running)
    {
        _consoleOperationRunning = running;
        consoleOverlay.Visibility = Visibility.Visible;
        navConsola.Style = (Style)FindResource("BtnNavIconActive"); // pill mientras esta abierto

        if (running)
        {
            btnConsoleStop.Visibility = Visibility.Visible;
            btnConsoleStop.IsEnabled  = true;
            btnConsoleClose.IsEnabled = false;      // no se cierra el modal hasta terminar/cancelar
            SetConsoleChip("Ejecutando", BrushGreen);
        }
        else
        {
            btnConsoleStop.Visibility = Visibility.Collapsed;
            btnConsoleClose.IsEnabled = true;
            SetConsoleChip("Consulta", BrushGray);
        }

        // Mostrar lo ultimo del log al abrir (tras el layout del overlay recien visible).
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => logScroll.ScrollToEnd()));
    }

    // Llamar al terminar (o cancelar) la operacion: oculta "Detener" y habilita "Cerrar".
    private void ConsoleOperationCompleted()
    {
        _consoleOperationRunning = false; // ya se puede cerrar (Cerrar y click-afuera habilitados)
        btnConsoleStop.Visibility = Visibility.Collapsed;
        btnConsoleClose.IsEnabled = true;
        SetConsoleChip("Completado", BrushGreen);
    }

    private void CloseConsoleOverlay()
    {
        // Guard: mientras corre una operacion no se cierra (fix 28.6). El scrim ya lo chequea, pero
        // esto blinda cualquier otra via (p.ej. si "Cerrar" quedara habilitado por error).
        if (_consoleOperationRunning) return;

        consoleOverlay.Visibility = Visibility.Collapsed;
        navConsola.Style = (Style)FindResource("BtnNavIcon");

        // Reset de la barra y el estado al cerrar (fix 28.5): la proxima apertura arranca limpia.
        progressBarConsole.Value = 0;
        lblProgressConsole.Text  = "Listo";
        lblPctConsole.Text       = "";
        SetConsoleChip("En espera...", BrushGray);
    }

    private void SetConsoleChip(string text, SolidColorBrush brush)
    {
        lblLogStatus.Text       = text;
        lblLogStatus.Foreground = brush;
    }

    // ── Monitor async ────────────────────────────────────────────────────────

    // Fix 30: el monitor ahora alimenta los MEDIDORES CIRCULARES del Home (CPU/RAM/GPU) en vez de
    // las barras verticales de Info del sistema (eliminada). Sigue manteniendo los labels TOTAL/EN
    // USO/LIBRE del "Liberador de RAM" (Herramientas). Se dejaron de mostrar (junto con Info) la
    // actividad de disco, el % de C: y las temperaturas CPU/GPU.
    private async void OnMonitorTick(object? sender, EventArgs e)
    {
        var data = await Task.Run(ReadMetrics);

        SetGaugeArc(arcCpu, segCpu, lblGaugeCpu, data.CpuPct, available: true);

        double ramPct = data.RamTotalGb > 0 ? data.RamUsedGb / data.RamTotalGb * 100.0 : 0;
        SetGaugeArc(arcRam, segRam, lblGaugeRam, ramPct, available: true);

        // GPU: best-effort (Windows no lo expone tan limpio como CPU/RAM). -1 = no disponible.
        SetGaugeArc(arcGpu, segGpu, lblGaugeGpu, data.GpuPct, available: data.GpuPct >= 0);

        // Labels del "Liberador de RAM" (Herramientas): los mantiene el monitor cada segundo.
        lblRAMTotal.Text = $"{data.RamTotalGb:F0} GB";
        lblRAMUsed.Text  = $"{data.RamUsedGb:F1} GB";
        lblRAMFree.Text  = $"{(data.RamTotalGb - data.RamUsedGb):F1} GB";
    }

    // Medidor circular CUSTOM del Home (fix 31): ui:ProgressRing es un spinner indeterminado, no
    // sirve como gauge. Aca dibujamos el arco de progreso mutando el ArcSegment del Path: el track
    // gris (Ellipse) y el StartPoint (arriba, 12 en punto) son fijos en XAML; solo cambian el punto
    // final del arco, IsLargeArc, y el color por umbral. Geometria del XAML: centro 48, R=43.5.
    private static void SetGaugeArc(System.Windows.Shapes.Path arc, ArcSegment seg, TextBlock lbl,
                                    double pct, bool available)
    {
        if (!available) { arc.Visibility = Visibility.Collapsed; lbl.Text = "--"; return; }

        double v = Math.Clamp(pct, 0, 100);
        lbl.Text = $"{v:F0}%";

        if (v < 0.5) { arc.Visibility = Visibility.Collapsed; return; } // 0%: sin arco
        arc.Visibility = Visibility.Visible;
        arc.Stroke = v > 85 ? BrushRed : v > 60 ? BrushYellow : BrushBlue; // color por carga

        const double cx = 48, cy = 48, r = 43.5;
        double sweep    = Math.Min(359.9, v / 100.0 * 360.0);
        double endAngle = (-90.0 + sweep) * Math.PI / 180.0; // arranca arriba (-90), horario
        seg.Point      = new System.Windows.Point(cx + r * Math.Cos(endAngle), cy + r * Math.Sin(endAngle));
        seg.IsLargeArc = sweep > 180.0;
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

        return new Metrics(cpu, usedGb, totalGb, diskPct, sysUsagePct, ReadGpuPct());
    }

    // GPU usage best-effort (fix 30). Windows no expone el uso de GPU tan limpio como CPU/RAM:
    // se suma la utilizacion del engine 3D de "GPU Engine" (approx Task Manager). Counters
    // persistentes entre ticks (para lecturas validas, 1s de separacion) + rebuild periodico por
    // el churn de instancias por-proceso. -1 = categoria no disponible / aun sin lectura estable.
    // Corre dentro de Task.Run (fuera del hilo UI), sin costo perceptible.
    private float ReadGpuPct()
    {
        try
        {
            if (!PerformanceCounterCategory.Exists("GPU Engine")) return -1f;

            if (_gpuRebuildTick++ >= 10)
            {
                _gpuRebuildTick = 0;
                foreach (var c in _gpuCounters) { try { c.Dispose(); } catch { } }
                _gpuCounters.Clear();
                var cat = new PerformanceCounterCategory("GPU Engine");
                foreach (var inst in cat.GetInstanceNames())
                {
                    if (!inst.EndsWith("engtype_3D")) continue;
                    try
                    {
                        var c = new PerformanceCounter("GPU Engine", "Utilization Percentage", inst, readOnly: true);
                        c.NextValue(); // prime: la 1ra lectura de un rate counter es 0
                        _gpuCounters.Add(c);
                    }
                    catch { }
                }
                return _lastGpuPct; // tick de rebuild: counters recien primados -> devolver lo ultimo
            }

            float total = 0f;
            foreach (var c in _gpuCounters)
            {
                try { total += c.NextValue(); } catch { }
            }
            _lastGpuPct = Math.Clamp(total, 0f, 100f);
            return _lastGpuPct;
        }
        catch { return -1f; }
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

    // Fix 30: UpdateThermalDisplay/TempBrush se removieron con Info del sistema (las barras de
    // temperatura CPU/GPU ya no existen). El servicio App.Thermal queda disponible por si el
    // monitoreo de temperaturas se reincorpora (decision PawnIO/LHM, ver PENDIENTES).

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
        foreach (var c in _gpuCounters) { try { c.Dispose(); } catch { } } // fix 30
        base.OnClosed(e);
    }

    private record struct Metrics(float CpuPct, double RamUsedGb, double RamTotalGb,
                                  double DiskPct, double SysDiskUsagePct, float GpuPct);

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

        // fix 31: se quito el subtitulo de modelo de las cards de uso (CPU/RAM/GPU) — esa info ya
        // vive en el overlay System Info, era redundante. Las cards quedan con medidor + nombre.

        if (info.IsLaptop) badgeLaptop.Visibility = Visibility.Visible;
    }

    // ── Home: overlay System Info + card de tweaks activos (fix 30, rediseño prompt 62) ─────
    // El overlay reusa el patron del overlay de consola. Siempre cerrable.
    private void OpenSystemInfoOverlay()
    {
        systemInfoOverlay.Visibility = Visibility.Visible;
        _ = LoadComponentsInfoAsync(); // WMI lazy/cacheado; refresca el estado de HAGS
    }

    private void CloseSystemInfoOverlay()
    {
        systemInfoOverlay.Visibility = Visibility.Collapsed;
    }

    // Card "TWEAKS ACTIVOS" del Home (prompt 62, reemplaza a la vieja "Ultima optimizacion" --
    // esa dependia 100% de BackupSessionInfo/SessionMetadata, el mecanismo del tab Optimizar
    // clasico que el proyecto viene jubilando, ver diagnostico prompt 61). Cuenta cuantos de
    // TweakRegistry.All tienen LeerEstadoAsync() == On ahora mismo, EN VIVO -- a proposito NO
    // reusa AuditResult/RunAuditAsync (la malla de salud): son 17 checks con criterios mas laxos
    // que los 27 toggles reales (ej. CheckSvcXbox tolera 2 de 3, el TweakDefinition exige los 3),
    // mostrar ese numero como "tweaks activos" seria inconsistente con lo que el usuario ve en
    // Tweaks/Network.
    private async Task UpdateActiveTweaksCardAsync()
    {
        if (_activeTweaksCount is int cached)
        {
            RenderActiveTweaksCard(cached, App.Tweaks.All.Count);
            return;
        }
        // Primera vez que hace falta el numero (tipico: el usuario entra a Home antes de haber
        // visitado nunca Tweaks o Network) -- barre los 27 en paralelo (cada LeerEstadoAsync ya es
        // su propio Task.Run, Task.WhenAll no bloquea el hilo UI) y cachea el resultado en memoria
        // para no repetir el barrido en cada visita a Home. Guard contra doble barrido si el
        // usuario rebota a Home varias veces mientras el primero todavia esta en vuelo.
        if (_activeTweaksLoading) return;
        _activeTweaksLoading = true;

        panelHomeTweaksData.Visibility    = Visibility.Collapsed;
        panelHomeTweaksLoading.Visibility = Visibility.Visible;
        try
        {
            // Reintenta si algun Aplicar/Revertir marco el barrido como "sucio" mientras corria
            // (prompt 63) -- tope chico solo como resguardo contra un caso patologico (alguien
            // togglea sin parar durante varios barridos seguidos); en el uso real no deberia hacer
            // falta mas de un reintento, si acaso.
            int on;
            int attempts = 0;
            do
            {
                _activeTweaksDirtyDuringSweep = false;
                var statuses = await Task.WhenAll(App.Tweaks.All.Select(t => t.LeerEstadoAsync()));
                on = statuses.Count(s => s.State == TweakState.On);
            } while (_activeTweaksDirtyDuringSweep && ++attempts < 5);

            _activeTweaksCount = on;
            RenderActiveTweaksCard(on, App.Tweaks.All.Count);
        }
        catch { panelHomeTweaksLoading.Visibility = Visibility.Visible; }
        finally { _activeTweaksLoading = false; }
    }

    private void RenderActiveTweaksCard(int on, int total)
    {
        lblHomeTweaksOn.Text    = $"{on}";
        lblHomeTweaksTotal.Text = $" / {total}";
        panelHomeTweaksLoading.Visibility = Visibility.Collapsed;
        panelHomeTweaksData.Visibility    = Visibility.Visible;
    }

    // Ajusta el cache +1/-1 cuando Aplicar/Revertir cambia el estado REAL de un tweak (comparado
    // contra el ultimo estado conocido de ese Id, no contra lo que el usuario intento hacer -- un
    // Revertir no-op o un Aplicar que fallo no deben mover el contador). Si el cache todavia no se
    // calculo ni una vez (_activeTweaksCount null), no hay nada que ajustar todavia -- pero si un
    // barrido esta en vuelo en ese momento, igual se marca sucio (ver _activeTweaksDirtyDuringSweep)
    // para que ese barrido se descarte y se repita en vez de cachear un numero que ya sabe que no
    // incluyo este cambio.
    private void AdjustActiveTweaksCache(string id, TweakState newState)
    {
        if (_activeTweaksLoading) _activeTweaksDirtyDuringSweep = true;
        if (_activeTweaksCount is not int count) return;
        bool wasOn = _lastKnownTweakState.TryGetValue(id, out var previous) && previous == TweakState.On;
        bool isOn  = newState == TweakState.On;
        if (wasOn != isOn) _activeTweaksCount = count + (isOn ? 1 : -1);
    }

    // Prompt 75: "Limpieza profunda de cache" dejo de ser una card propia en Herramientas.
    // Ahora es el checkbox "Cache profunda" de la seccion Limpieza -- lo dispara
    // OptimizationService.CleanupTweaks -> MaintenanceService.DeepCleanAsync, con el aviso de
    // impacto alto (reinicio del Explorador) en ConfirmOptimizationDialog. El handler
    // DeepCleanAsync() de MainWindow se elimino (sin otro caller).

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

        try
        {
            // Prompt 66: el wizard ya no elige ni aplica ningun preset (ese paso se saco --
            // aplicaba los checkboxes del tab Optimizar clasico, retirado en este mismo corte).
            var dlg = new OnboardingDialog(cpu, gpu, ram, disk, laptop, score) { Owner = this };
            dlg.ShowDialog();

            if (dlg.Completed)
            {
                App.Settings.Current.FirstRunCompleted = true;   // Set-FirstRunComplete
                App.Settings.Save();
                App.Logger.Log("Onboarding completado", "ok");
            }
        }
        catch { }
    }

    private async Task RecalcScoreAsync()
    {
        btnRecalcScore.IsEnabled  = false;
        lblHomeScoreLabel.Text    = "Recalculando...";
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

    // Fix 30: alimenta la MALLA DE SALUD del Home (ex panel de barras de Info del sistema).
    // Nombre conservado para no tocar los callers (RunAndDisplayScoreAsync / RecalcScoreAsync /
    // OnMainTabsSelectionChanged).
    private void UpdateScorePanel(AuditResult r)
    {
        lblHomeScore.Text       = $"{r.Score}";
        lblHomeScore.Foreground = ScoreBrush(r.Score);
        lblHomeScoreLabel.Text  = r.Score >= 75 ? "Sistema bien optimizado"
                                : r.Score >= 45 ? "Optimizacion parcial - hay margen de mejora"
                                : "Sistema sin optimizar";

        // Insights derivados del estado REAL. El insight afirmativo (completa) o el de revisar
        // (incompleta) segun la fraccion. Privacidad: con el fix 32 (CheckTasks independiente del
        // idioma) 4/4 pasa a afirmativo; el texto prudente ("Revisa...") solo queda si por algun
        // motivo la categoria quedara incompleta.
        SetHealthCard(r, "Rendimiento", lblHomeRendStatus, lblHomeRendFrac, lblHomeRendInsight,
                      BrushGreen, "Todos los tweaks de rendimiento aplicados",
                      "Hay tweaks de rendimiento sin aplicar");
        SetHealthCard(r, "Privacidad", lblHomePrivStatus, lblHomePrivFrac, lblHomePrivInsight,
                      BrushYellow, "Telemetria y tareas de diagnostico deshabilitadas",
                      "Revisa esta categoria para reforzar tu privacidad");
        SetHealthCard(r, "Red", lblHomeRedStatus, lblHomeRedFrac, lblHomeRedInsight,
                      BrushFromHex("#00C8FF"), "Conectividad optimizada",
                      "Hay optimizaciones de red pendientes");
        SetHealthCard(r, "Servicios", lblHomeServStatus, lblHomeServFrac, lblHomeServInsight,
                      BrushFromHex("#A855F7"), "Servicios innecesarios deshabilitados",
                      "Hay servicios innecesarios activos");
    }

    // Una card de la malla: fraccion real (ok/total) + estado OPTIMO/REVISAR + insight.
    private void SetHealthCard(AuditResult r, string category, TextBlock status, TextBlock frac,
                               TextBlock insight, SolidColorBrush completeColor,
                               string okInsight, string reviewInsight)
    {
        var items = r.Items.Where(i => i.Category == category).ToList();
        int ok    = items.Count(i => i.Ok);
        int total = items.Count;
        bool complete = total > 0 && ok == total;

        frac.Text         = $"{ok}/{total}";
        status.Text       = complete ? "OPTIMO" : "REVISAR";
        status.Foreground = complete ? completeColor : BrushYellow;
        insight.Text      = complete ? okInsight : reviewInsight;
    }

    private void OnMainTabsSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.Source != mainTabs) return;

        // Tab Herramientas (0, era 1 -- prompt 66 retiro el tab Optimizar clasico, indice 0
        // original): carga lazy de procesos pesados la primera vez + arranca el auto-refresh (ON
        // por defecto). El scan corre async, no traba la UI.
        if (mainTabs.SelectedIndex == 0 && !_procLoaded)
        {
            _procLoaded = true;
            _ = InitProcessesAsync();
        }

        // Tab Home (1, era 2, fix 30): refresca la malla de salud + la card de tweaks activos
        // (prompt 62). (Los componentes ya NO se cargan aca: viven en el overlay System Info, que
        // los pide al abrirse.)
        if (mainTabs.SelectedIndex == 1)
        {
            if (_lastAuditResult is { } r)
                Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => UpdateScorePanel(r)));
            _ = UpdateActiveTweaksCardAsync();
        }

        // Tab Arranque (2, era 3): carga lazy de la lista de startup la primera vez
        if (mainTabs.SelectedIndex == 2 && !_startupLoaded)
        {
            _startupLoaded = true;
            _ = RefreshStartupAsync();
        }

        // Tab Bloatware (3, era 4): escanea lazy la primera vez (el scan enumera AppX y
        // tarda; dispararlo aca y no en el arranque evita penalizar el startup).
        // El boton "Actualizar lista" sigue refrescando manualmente despues.
        if (mainTabs.SelectedIndex == 3 && !_bloatLoaded)
        {
            _bloatLoaded = true;
            _ = ScanBloatwareAsync();
        }

        // Tab Historial (4, era 5): carga lazy la primera vez
        if (mainTabs.SelectedIndex == 4 && !_historyLoaded)
        {
            _historyLoaded = true;
            _ = RefreshHistoryAsync();
        }

        // Tab Ajustes (5, era 6): calcula el tamano de la carpeta de backups la primera vez
        // (async, fuera del hilo UI; BUG 3)
        if (mainTabs.SelectedIndex == 5 && !_settingsLoaded)
            _ = LoadBackupInfoAsync();

        // Tab Tweaks (7, era 8 -- prompt 66 retiro el tab Optimizar clasico): carga lazy de las
        // cards (App.Tweaks.All filtrado a Categoria!="Red", 24 de las 27 del registro --
        // Nagle/TCP/DisableIPv6 viven en Network) + estado real la primera vez
        if (mainTabs.SelectedIndex == 7 && !_tweaksLoaded)
        {
            _tweaksLoaded = true;
            _ = LoadTweaksTabAsync();
        }

        // Tab Network (8, era 9, Fase C Paso 1): carga lazy de las cards de categoria Red
        // (Nagle/TCP mudados desde Tweaks + DisableIPv6 nuevo) + estado real la primera vez.
        if (mainTabs.SelectedIndex == 8 && !_networkLoaded)
        {
            _networkLoaded = true;
            _ = LoadNetworkTabAsync();
        }

        // Tab Limpieza (9, era 10, Fase C Paso 3): carga lazy -- solo necesita saber si hay SSD
        // para deshabilitar el checkbox de Prefetch (WMI, evitar la consulta en cada apertura de tab).
        if (mainTabs.SelectedIndex == 9 && !_limpiezaLoaded)
        {
            _limpiezaLoaded = true;
            _ = LoadLimpiezaTabAsync();
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
            lblHomeScore.Text = $"{from + (int)Math.Round((to - from) * eased)}"; // score del Home (fix 30)
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

    // ── Mantenimiento automatico (4.3; seccion Limpieza desde el prompt 75) ──────────────────
    // El XAML de esta seccion se movio de Herramientas a Limpieza en el prompt 75. Estos metodos
    // no cambiaron: operan sobre los mismos controles x:Name (tglMaintenance, cboMaintFreq/Hour,
    // chkMaint*, lblLastMaint/NextMaint/MaintStatus, btnRunMaintNow), solo que ahora viven en otra
    // parte del arbol visual. UpdateMaintUIAsync se sigue llamando al arrancar la app (constructor),
    // no atado a visitar ningun tab.

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

            // Col 4 — Estado. Prompt 69: una sesion de Bloatware (solo bloatware_removed.json)
            // se rotula "Bloatware" en vez del generico "Sin metadata" -- asi la fila se lee
            // como registro coherente y el hueco de la columna Accion (sin boton) tiene sentido.
            var (stateBg, stateFg, stateLbl) = s.IsBloatwareOnly
                ? (Color.FromRgb(0x1A, 0x1A, 0x1A), Color.FromRgb(0x88, 0x88, 0x88), "Bloatware")
                : s.HasMeta
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

            // Col 5 — Accion. "Revertir" salvo en sesiones de Bloatware: un revert de Bloatware
            // no se puede cumplir (no se reinstalan apps), asi que la fila queda como registro
            // informativo sin accion. Placeholder inerte "—" para que la columna no quede vacia.
            UIElement col5;
            if (s.IsBloatwareOnly)
            {
                col5 = new TextBlock
                {
                    Text                = "—",
                    FontSize            = 12,
                    Foreground          = BrushGray,
                    VerticalAlignment   = VerticalAlignment.Center,
                    HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                };
            }
            else
            {
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
                col5 = revertBtn;
            }
            Grid.SetColumn(col5, 5);

            grid.Children.Add(tsTxt);
            grid.Children.Add(presetBdr);
            grid.Children.Add(actTxt);
            grid.Children.Add(mbTxt);
            grid.Children.Add(stateBdr);
            grid.Children.Add(col5);

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

        // Prompt 69: "Revertir ultima sesion" apunta a la mas reciente. Si esa es una sesion
        // de Bloatware (solo bloatware_removed.json) no se puede revertir -- no se reinstalan
        // apps. Avisar honestamente en vez de mandarla a InvokeRevertSessionAsync, donde el
        // dialogo de confirmacion prometeria restaurar "registro, servicios y red" y el guard
        // de RestoreSession terminaria en "Restauracion con errores".
        if (sessions[0].IsBloatwareOnly)
        {
            System.Windows.MessageBox.Show(
                "La ultima sesion es un registro de desinstalacion de Bloatware.\n\n" +
                "Las apps desinstaladas no se pueden reinstalar automaticamente desde WinBoost, " +
                "asi que esa sesion no se puede revertir.",
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

    // ── Licencias (5.1, modulos 12B/12C) ─────────────────────────────────────
    // El trial gratuito de 14 dias se elimino en el prompt 82. IsPro solo es true con
    // una licencia Pro/Tech real; sin licencia -> Free. Los features protegidos por
    // LockProFeature no cambiaron (Desinstalar bloatware, Mantenimiento automatico,
    // Revertir sesion) -- que MAS gatear para Free queda pendiente (ver PENDIENTES.md).

    // Init en background: HWID + estado de licencia fuera del hilo UI.
    private async Task InitLicenseAsync()
    {
        await Task.Run(() => App.License.RefreshFromStored());
        lblHardwareID.Text = App.License.GetHardwareId();
        UpdateLicenseBadge();
    }

    // Mirror de Lock-ProFeature: bloquea (true) si no hay licencia Pro/Tech.
    private bool LockProFeature(string featureName = "")
    {
        if (App.License.IsPro) return false;

        string baseName = string.IsNullOrEmpty(featureName) ? "Esta funcion" : featureName;
        System.Windows.MessageBox.Show(
            $"{baseName} es exclusiva de las licencias Pro y Tecnico.\n\n" +
            "Activa tu licencia en la pestaña Licencia para usarla.",
            "WinBoost - Funcion Pro",
            MessageBoxButton.OK, MessageBoxImage.Information);
        return true;
    }

    // Badge de licencia junto al wordmark del sidebar + texto de estado en la pestaña
    // Licencia. Tres estados: Tecnico / Pro / Free (el trial se elimino en el prompt 82).
    private void UpdateLicenseBadge()
    {
        var lic = App.License;
        badgeLicenseFree.Visibility = Visibility.Collapsed;
        badgeLicensePro.Visibility  = Visibility.Collapsed;
        badgeLicenseTech.Visibility = Visibility.Collapsed;

        if (lic.IsTech)
        {
            badgeLicenseTech.Visibility = Visibility.Visible;
            lblLicenseStatus.Text       = "WinBoost TECNICO activado - multi-PC";
            lblLicenseStatus.Foreground = BrushGreen;
        }
        else if (lic.IsPro)
        {
            badgeLicensePro.Visibility = Visibility.Visible;
            lblLicenseStatus.Text       = "WinBoost PRO activado";
            lblLicenseStatus.Foreground = BrushYellow;
        }
        else
        {
            badgeLicenseFree.Visibility = Visibility.Visible;
            lblLicenseStatus.Text       = "Version gratuita activa";
            lblLicenseStatus.Foreground = BrushLicFree;
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
        // Prompt 66: se saco el SetActiveNav(0) que habia aca ("mostrar footer con la
        // progressBar") -- footerBar (del tab Optimizar clasico, ya retirado) no tenia ninguna
        // progressBar real desde el fix 28.3 (App.Progress apunta solo a progressBarConsole, en
        // el overlay de Consola); confirmado que este llamado ya no cumplia ninguna funcion antes
        // de sacarlo.
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

    // Prompt 56: la pestana Tuning Avanzado (Scheduler CPU / HAGS / Politica termica, 3
    // ui:ToggleSwitch de 16B) se retiro completa. Los 3 controles + su logica Update*Ui/Set*
    // migraron a la seccion Tweaks (TweakRegistry.cs: tweaks "Win32PrioritySep", "HAGS",
    // "PoliticaTermica"), reusando BuildTweakCard/UpdateTweakCardUi genericos en vez de UI a
    // mano por control.

    // ── Tweaks (piloto Fase A, 38_fase_a_registro_tweaks_piloto.txt) ─────────────────────────
    // Mismo patron que Tuning Avanzado (ToggleSwitch IsChecked bool?, Checked/Unchecked, flag
    // _tweaksSyncing) pero data-driven desde App.Tweaks.All en vez de 3 switches fijos en XAML:
    // las cards se generan en codigo para no tener que duplicar bloques XAML por tweak cuando la
    // Fase B escale esto a ~25.

    // Fase C, Paso 1: excluye Categoria=="Red" -- esos tweaks (Nagle, TCP, + DisableIPv6 nuevo) se
    // mudaron al panel Network (LoadNetworkTabAsync), misma definicion, solo cambia donde se
    // renderiza la card. _tweakCardRefs.Clear() se saco a proposito: el dict ahora es compartido
    // entre dos paneles con carga lazy independiente (Tweaks y Network) -- si el usuario abre
    // Network primero y Tweaks despues, un Clear() aca borraria las referencias de las cards de
    // Network ya construidas, dejando sus toggles sin efecto (UpdateTweakCardUi no encontraria su
    // entrada). No hace falta: cada Id es unico en todo el registro, y _xLoaded ya evita que este
    // metodo corra mas de una vez, asi que nunca hay nada viejo que limpiar.
    private async Task LoadTweaksTabAsync()
    {
        pnlTweaks.Children.Clear();
        var tweaks = App.Tweaks.All.Where(t => t.Categoria != "Red").ToList();
        foreach (var def in tweaks)
            pnlTweaks.Children.Add(BuildTweakCard(def));

        foreach (var def in tweaks)
            UpdateTweakCardUi(def.Id, await def.LeerEstadoAsync());
    }

    // Fase C, Paso 1 (47_fase_c_paso1_seccion_network.txt): panel hermano de LoadTweaksTabAsync,
    // filtrado a Categoria=="Red" -- Nagle/TCP (mudados, misma AplicarAsync/RevertirAsync/
    // LeerEstadoAsync de siempre) + DisableIPv6 (nuevo). Mismo BuildTweakCard/UpdateTweakCardUi
    // que Tweaks, sin duplicar nada.
    private async Task LoadNetworkTabAsync()
    {
        pnlNetwork.Children.Clear();
        var tweaks = App.Tweaks.All.Where(t => t.Categoria == "Red").ToList();
        foreach (var def in tweaks)
            pnlNetwork.Children.Add(BuildTweakCard(def));

        // DNSFlush (Fase C, Paso 2): quick action, no TweakDefinition -- se agrega al mismo panel
        // que las cards de toggle, despues de ellas.
        var dnsFlush = App.QuickActions.Find("DNSFlush");
        if (dnsFlush is not null) pnlNetwork.Children.Add(BuildQuickActionCard(dnsFlush));

        foreach (var def in tweaks)
            UpdateTweakCardUi(def.Id, await def.LeerEstadoAsync());

        await RefreshDnsCardAsync();
    }

    // Fase C, Paso 2 (48_fase_c_paso2_dns_dnsflush.txt): estado de la card de DNS, siempre leido en
    // vivo (nunca cacheado) -- mismo principio que UpdateTweakCardUi/LeerEstadoAsync.
    private async Task RefreshDnsCardAsync()
    {
        var status = await DnsPresetService.ReadStatusAsync();
        lblNetDnsStatus.Text = status.State switch
        {
            DnsState.Automatico     => "Estado actual: Automatico (DHCP).",
            DnsState.Proveedor      => $"Estado actual: {status.ProviderName}.",
            DnsState.Personalizado  => "Estado actual: Configuracion personalizada (no coincide con ningun proveedor conocido).",
            DnsState.SinAdaptadores => "No se detectaron adaptadores de red activos.",
            _                       => "",
        };
        lblNetDnsStatus.Foreground = (Brush)FindResource("BrushFgMuted");
        btnNetDnsRestore.IsEnabled = DnsPresetService.HasOriginalCaptured();
    }

    // Fase C, Paso 2 (48_fase_c_paso2_dns_dnsflush.txt): card reutilizable para
    // QuickActionDefinition -- mismo look que BuildTweakCard (Border/titulo/descripcion/status)
    // pero con un boton "Ejecutar" en vez del ToggleSwitch, ya que una accion rapida no tiene
    // On/Off. Pensada para reusarse tal cual cuando TRIM/Desfrag y el punto de restauracion migren
    // a este mismo patron.
    private Border BuildQuickActionCard(QuickActionDefinition def)
    {
        var status = new TextBlock { FontSize = 11, Margin = new Thickness(0, 8, 0, 0), TextWrapping = TextWrapping.Wrap, Foreground = (Brush)FindResource("BrushFgMuted") };

        var button = new Button { Content = "Ejecutar", Style = (Style)FindResource("BtnSec"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 0, 0, 0) };
        button.Click += async (_, _) =>
        {
            button.IsEnabled = false;
            try
            {
                status.Text       = await def.EjecutarAsync();
                status.Foreground = BrushGreen;
            }
            catch (Exception ex)
            {
                status.Text       = $"Error: {ex.Message}";
                status.Foreground = BrushRed;
            }
            finally { button.IsEnabled = true; }
        };

        var title = new TextBlock
        {
            Text       = def.Nombre.ToUpperInvariant(),
            FontSize   = 10,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)FindResource("BrushAccent"),
            Margin     = new Thickness(0, 0, 0, 12),
        };

        var left = new StackPanel();
        left.Children.Add(new TextBlock
        {
            Text         = def.Descripcion,
            FontSize     = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground   = (Brush)FindResource("BrushFg2"),
        });

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(left, 0);
        Grid.SetColumn(button, 1);
        grid.Children.Add(left);
        grid.Children.Add(button);

        var body = new StackPanel();
        body.Children.Add(title);
        body.Children.Add(grid);
        body.Children.Add(status);

        return new Border
        {
            Background      = (Brush)FindResource("BrushCard"),
            BorderBrush     = (Brush)FindResource("BrushAccent"),
            BorderThickness = new Thickness(0, 0, 0, 2),
            CornerRadius    = new CornerRadius(8),
            Padding         = new Thickness(18, 14, 18, 16),
            Margin          = new Thickness(0, 0, 0, 14),
            Child           = body,
        };
    }

    // Fase C, Paso 3 (49_fase_c_paso3_seccion_limpieza.txt): unico dato que necesita esta seccion
    // al abrir el tab -- si hay SSD, para Prefetch. Mismo SystemInfoService.HasSsd() liviano de la
    // Tanda 4 (no el SystemSnapshot completo del tab Optimizar clasico, que dispara 5 consultas WMI
    // de mas por un solo booleano).
    private async Task LoadLimpiezaTabAsync()
    {
        bool hasSsd = await Task.Run(SystemInfoService.HasSsd);
        if (!hasSsd)
        {
            // Mismo tratamiento visual que NoAplicable en la Tanda 4 (SvcSysMain/SvcWSearch):
            // control deshabilitado + motivo en el mismo color "info" (BrushBlue). Un CheckBox no
            // tiene una linea de status propia como las cards de toggle -- el motivo va directo en
            // el label en vez de un TextBlock aparte.
            chkCleanPrefetch.IsChecked  = false;
            chkCleanPrefetch.IsEnabled  = false;
            chkCleanPrefetch.Content    = "Prefetch (requiere SSD)";
            chkCleanPrefetch.Foreground = BrushBlue;
        }
    }

    // Fase C, Paso 3: dialogo de confirmacion (ConfirmOptimizationDialog, el mismo del tab
    // Optimizar clasico -- agrupa por categoria y ya muestra el banner de impacto alto; con 8 items
    // "Limpieza" arma un solo grupo y preserva la advertencia de EventLogs sin cambiar nada del
    // dialogo) + OptimizationService.CleanupTweaks (subida a internal, Paso 4) sobre una instancia
    // NUEVA -- new OptimizationService(), no App.Optimizer -- mismo criterio que
    // TweakRegistry.ApplyPageFileAsync (Fase B): evita compartir _applied/_skipped/Log con la
    // instancia singleton que usa el tab Optimizar clasico.
    private async Task RunLimpiezaAsync()
    {
        var items = new (string Id, CheckBox Chk, string Label, string Detail, string Impact)[]
        {
            ("TempUser",  chkCleanTempUser,  "Temp usuario",         "%TEMP% - archivos temporales del perfil de usuario",         "low"),
            ("TempSys",   chkCleanTempSys,   "Temp sistema",         @"C:\Windows\Temp - temporales del sistema operativo",        "low"),
            ("Prefetch",  chkCleanPrefetch,  "Prefetch (SSD)",       @"C:\Windows\Prefetch - solo recomendado en SSD",             "low"),
            ("WinUpdate", chkCleanWinUpdate, "Cache Windows Update", @"SoftwareDistribution\Download - paquetes ya instalados",    "low"),
            ("Browsers",  chkCleanBrowsers,  "Cache navegadores",    "Chrome, Edge, Firefox, Brave, Opera - no borra contrasenas", "low"),
            ("Recycle",   chkCleanRecycle,   "Papelera",             "Vacia la papelera permanentemente",                          "low"),
            ("EventLogs", chkCleanEventLogs, "Logs de eventos",
                "Borra logs Aplicacion/Sistema/etc. Log de Seguridad NO se toca. Elimina registros forenses.", "high"),
            // Prompt 75: "Cache profunda" (ex-card de Herramientas). Subsume al viejo checkbox
            // "Thumbnails" -- el paso 1 de DeepClean cubre la misma carpeta (%LocalAppData%\
            // Microsoft\Windows\Explorer) mejor, con el Explorador detenido. Impacto "high" por el
            // reinicio forzado del Explorador. La clave "Thumb" de CleanupTweaks se conserva para
            // el -Silent de CLI (los presets la usan); solo se saco el checkbox de la UI.
            ("DeepClean", chkCleanDeep,      "Cache profunda",
                "Reinicia el Explorador (parpadeo 2-3 s, cierra ventanas). Limpia cache de iconos/miniaturas, WER, logs CBS/DISM y shaders D3D.", "high"),
        };

        var sel  = items.ToDictionary(i => i.Id, i => i.Chk.IsChecked == true);
        var plan = items.Where(i => i.Chk.IsChecked == true)
                         .Select(i => new PlanAction("Limpieza", i.Label, i.Detail, i.Impact))
                         .ToList();

        if (plan.Count == 0)
        {
            lblLimpiezaResult.Text       = "No hay items seleccionados.";
            lblLimpiezaResult.Foreground = (Brush)FindResource("BrushFgMuted");
            return;
        }

        var dialog = new ConfirmOptimizationDialog(plan) { Owner = this };
        if (dialog.ShowDialog() != true) return;

        btnRunLimpieza.IsEnabled    = false;
        lblLimpiezaResult.Text       = "Limpiando...";
        lblLimpiezaResult.Foreground = (Brush)FindResource("BrushFgMuted");
        try
        {
            bool   hasSsd   = await Task.Run(SystemInfoService.HasSsd);
            string sysDrive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:") + @"\";
            double freedMb  = await Task.Run(() => new OptimizationService().CleanupTweaks(sel, hasSsd, sysDrive));

            lblLimpiezaResult.Text       = $"Limpieza completada: {freedMb:F1} MB liberados. Detalle por item en la Consola.";
            lblLimpiezaResult.Foreground = BrushGreen;
        }
        catch (Exception ex)
        {
            lblLimpiezaResult.Text       = $"Error: {ex.Message}";
            lblLimpiezaResult.Foreground = BrushRed;
        }
        finally { btnRunLimpieza.IsEnabled = true; }
    }

    // Fase C, Paso 4 (50_fase_c_paso4_5_trim_herramientas_restore_home.txt): mismo mecanismo que
    // OnRunOptimizationAsync/Desinstalar bloatware para una operacion larga y cancelable --
    // App.Worker.RunAsync (lock IsRunning + CancellationTokenSource) + OpenConsoleOverlay (progreso
    // y log en vivo + "Detener", ya cableado a App.Worker.Cancel()). No se inventa un mecanismo de
    // progreso/cancelacion propio: TrimTweaksAsync ya tiene el suyo (CancellationToken + loop de
    // progreso cada 1s) -- forzarlo en un patron mas simple (tipo QuickActionDefinition) lo habria
    // perdido.
    private async Task RunTrimAsync()
    {
        if (App.Worker.IsRunning)
        {
            lblTrimStatus.Text       = "Ya hay una operacion en curso (revisa la Consola).";
            lblTrimStatus.Foreground = BrushRed;
            return;
        }

        btnRunTrim.IsEnabled     = false;
        lblTrimStatus.Text       = "Iniciando...";
        lblTrimStatus.Foreground = (Brush)FindResource("BrushFgMuted");

        bool hasSsd = (_systemInfo ?? await App.SystemInfo.GetSystemInfoAsync()).HasSsd;

        OpenConsoleOverlay(running: true);
        bool ok = await App.Worker.RunAsync(
            ct => new OptimizationService().TrimTweaksAsync(hasSsd, ct),
            startMsg: "Iniciando TRIM/Desfrag...",
            doneMsg:  "TRIM/Desfrag completado");
        ConsoleOperationCompleted();

        btnRunTrim.IsEnabled     = true;
        lblTrimStatus.Text       = ok
            ? "TRIM/Desfrag completado. Detalle en la Consola."
            : "Cancelado o con errores -- revisa la Consola para el detalle.";
        lblTrimStatus.Foreground = ok ? BrushGreen : BrushYellow;
    }

    private Border BuildTweakCard(TweakDefinition def)
    {
        var toggle = new Wpf.Ui.Controls.ToggleSwitch
        {
            Margin            = new Thickness(16, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            OnContent         = "Activo",
            OffContent        = "Inactivo",
        };
        var status = new TextBlock { FontSize = 11, Margin = new Thickness(0, 8, 0, 0), TextWrapping = TextWrapping.Wrap };

        // Panel "Restablecer a default de Windows" (prompt 71): solo para los 20 tweaks "Seguro"
        // (def.RestablecerDefaultAsync != null). Arranca oculto; UpdateTweakCardUi lo muestra
        // cuando el tweak esta On y no hay Original capturado (el escenario que bloquea "Revertir").
        StackPanel? resetPanel = null;
        if (def.RestablecerDefaultAsync is not null)
        {
            var resetHint = new TextBlock
            {
                Text         = "WinBoost no guardo un valor original para este tweak, asi que \"Revertir\" no " +
                               "puede volver a lo que tenias. Podes dejarlo en el valor de fabrica de Windows " +
                               "(no necesariamente lo que tenias antes en este equipo):",
                FontSize     = 11,
                TextWrapping = TextWrapping.Wrap,
                Foreground   = BrushYellow,
            };
            var resetBtn = new Button
            {
                Content             = "Restablecer a default de Windows",
                Style               = (Style)FindResource("BtnSec"),
                FontSize            = 11,
                Margin              = new Thickness(0, 8, 0, 0),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
            };
            resetBtn.Click += async (_, _) => await ResetTweakToDefaultAsync(def);
            resetPanel = new StackPanel { Margin = new Thickness(0, 12, 0, 0), Visibility = Visibility.Collapsed };
            resetPanel.Children.Add(resetHint);
            resetPanel.Children.Add(resetBtn);
        }

        _tweakCardRefs[def.Id] = (toggle, status, resetPanel);

        toggle.Checked   += async (_, _) => { if (!_tweaksSyncing) await ApplyTweakAsync(def); };
        toggle.Unchecked += async (_, _) => { if (!_tweaksSyncing) await RevertTweakAsync(def); };

        var title = new TextBlock
        {
            Text       = def.Nombre.ToUpperInvariant(),
            FontSize   = 10,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)FindResource("BrushAccent"),
            Margin     = new Thickness(0, 0, 0, 12),
        };

        var left = new StackPanel();
        left.Children.Add(new TextBlock
        {
            Text          = def.Descripcion,
            FontSize      = 12,
            TextWrapping  = TextWrapping.Wrap,
            Foreground    = (Brush)FindResource("BrushFg2"),
        });
        if (def.RequiereReinicio)
            left.Children.Add(new TextBlock
            {
                Text         = "Requiere reiniciar el equipo para tener efecto completo.",
                FontSize     = 10,
                FontWeight   = FontWeights.SemiBold,
                Foreground   = BrushYellow,
                TextWrapping = TextWrapping.Wrap,
                Margin       = new Thickness(0, 4, 0, 0),
            });

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(left, 0);
        Grid.SetColumn(toggle, 1);
        grid.Children.Add(left);
        grid.Children.Add(toggle);

        var body = new StackPanel();
        body.Children.Add(title);
        body.Children.Add(grid);
        body.Children.Add(status);
        if (resetPanel is not null) body.Children.Add(resetPanel);

        return new Border
        {
            Background      = (Brush)FindResource("BrushCard"),
            BorderBrush     = (Brush)FindResource("BrushAccent"),
            BorderThickness = new Thickness(0, 0, 0, 2),
            CornerRadius    = new CornerRadius(8),
            Padding         = new Thickness(18, 14, 18, 16),
            Margin          = new Thickness(0, 0, 0, 14),
            Child           = body,
        };
    }

    // Fuente de verdad SIEMPRE es LeerEstadoAsync contra el sistema real, nunca el store -- por
    // eso esto se llama tanto en la carga inicial como despues de cada Aplicar/Revertir (incluso
    // si tiro excepcion), para que el switch nunca muestre algo que no se pudo confirmar de verdad.
    private void UpdateTweakCardUi(string id, TweakStatus status)
    {
        // Bookkeeping para la card "Tweaks activos" del Home (prompt 62): todo render de una card
        // pasa por aca (carga inicial de Tweaks/Network, y cada Aplicar/Revertir), asi que este es
        // el unico lugar que necesita escribir el ultimo estado conocido -- gratis, sin barrido
        // extra. Se guarda incluso si la card todavia no existe (id valido pero _tweakCardRefs sin
        // entrada) para que el primer Aplicar/Revertir de una card recien creada ya tenga una base
        // real, no default(TweakState).
        _lastKnownTweakState[id] = status.State;

        if (!_tweakCardRefs.TryGetValue(id, out var refs)) return;

        _tweaksSyncing = true;
        try { refs.Switch.IsChecked = status.State == TweakState.On; }
        finally { _tweaksSyncing = false; }

        refs.Switch.IsEnabled = status.State != TweakState.NoAplicable;
        // status.Motivo en On (prompt 51, tweak "Power"): la mayoria de los tweaks no lo setea
        // (queda null, TweakStatus.On es el static field compartido) y cae en el "Aplicado."
        // generico de siempre -- Power es el primer caso que necesita decir la verdad de que se
        // aplico realmente segun el tipo de maquina (Ultimate Performance vs. Alto Rendimiento),
        // en vez de un texto identico en desktop y laptop.
        refs.Status.Text = status.State switch
        {
            TweakState.On          => status.Motivo ?? "Aplicado.",
            TweakState.Off         => "No aplicado.",
            TweakState.NoAplicable => $"No disponible: {status.Motivo}",
            _                      => "",
        };
        // NoAplicable (primer caso real: SvcSysMain/SvcWSearch sin SSD, Fase B Tanda 4) usaba el
        // mismo BrushLicFree que Off -- el toggle deshabilitado (arriba) ya lo distingue de un
        // vistazo, pero el texto de estado se veia identico a "No aplicado.", como si el usuario
        // pudiera simplemente prenderlo. BrushBlue = #00C8FF, el color "info" de la guia de estilo
        // (CLAUDE.md: ok/warn/err/info), reusado tal cual -- no se creo un brush nuevo.
        refs.Status.Foreground = status.State switch
        {
            TweakState.On          => BrushGreen,
            TweakState.NoAplicable => BrushBlue,
            _                      => BrushLicFree,
        };

        // "Restablecer a default de Windows" (prompt 71): visible SOLO si (1) el tweak lo soporta
        // -- refs.ResetPanel != null encapsula "es uno de los 20 Seguro", se setea en
        // BuildTweakCard --, (2) esta On, y (3) TweakStateStore no tiene un Original capturado
        // (mismo HasEntry que hoy determina si "Revertir" es no-op). Con Original real, "Revertir"
        // ya resuelve el caso: no se muestra este boton para no duplicar acciones.
        if (refs.ResetPanel is not null)
            refs.ResetPanel.Visibility =
                status.State == TweakState.On && !App.TweakState.HasEntry(id)
                    ? Visibility.Visible
                    : Visibility.Collapsed;
    }

    private async Task ApplyTweakAsync(TweakDefinition def)
    {
        if (!_tweakCardRefs.TryGetValue(def.Id, out var refs)) return;
        try
        {
            await def.AplicarAsync();
            var status = await def.LeerEstadoAsync();
            AdjustActiveTweaksCache(def.Id, status.State); // antes de UpdateTweakCardUi: necesita el ultimo estado conocido
            UpdateTweakCardUi(def.Id, status);
            // Mismo Motivo honesto que UpdateTweakCardUi (prompt 51) -- sin el, este texto pisaba
            // el de arriba con un "Aplicado." generico apenas 2 lineas despues de haberlo seteado
            // bien.
            string baseText = status.Motivo ?? "Aplicado.";
            refs.Status.Text = def.RequiereReinicio
                ? $"{baseText} Reinicia el equipo para que tenga efecto completo."
                : baseText;
            refs.Status.Foreground = def.RequiereReinicio ? BrushYellow : BrushGreen;
            App.Logger.Log($"{def.Nombre}: aplicado", "ok");
        }
        catch (Exception ex)
        {
            var real = await def.LeerEstadoAsync(); // revierte el switch al estado real
            AdjustActiveTweaksCache(def.Id, real.State);
            UpdateTweakCardUi(def.Id, real);
            refs.Status.Text       = $"Error al aplicar: {ex.Message}";
            refs.Status.Foreground = BrushRed;
        }
    }

    private async Task RevertTweakAsync(TweakDefinition def)
    {
        if (!_tweakCardRefs.TryGetValue(def.Id, out var refs)) return;
        try
        {
            await def.RevertirAsync();
            var status = await def.LeerEstadoAsync();
            AdjustActiveTweaksCache(def.Id, status.State); // antes de UpdateTweakCardUi: necesita el ultimo estado conocido
            UpdateTweakCardUi(def.Id, status);

            // RevertirAsync es no-op si WinBoost nunca aplico este tweak desde esta seccion (ej.
            // ya estaba On por el tab Optimizar clasico) -- el estado real sigue On y el switch
            // vuelve a marcarse solo (via UpdateTweakCardUi de arriba); el texto tiene que decir
            // eso, no afirmar un revert que no paso.
            if (status.State == TweakState.Off)
            {
                refs.Status.Text       = "Revertido a su valor original.";
                refs.Status.Foreground = BrushLicFree;
                App.Logger.Log($"{def.Nombre}: revertido", "ok");
            }
            else
            {
                refs.Status.Text = "No se revirtio: WinBoost no tiene un valor original guardado " +
                                    "para este tweak (puede haber sido aplicado desde la pestaña Optimizar).";
                refs.Status.Foreground = BrushYellow;
            }
        }
        catch (Exception ex)
        {
            var real = await def.LeerEstadoAsync(); // revierte el switch al estado real
            AdjustActiveTweaksCache(def.Id, real.State);
            UpdateTweakCardUi(def.Id, real);
            refs.Status.Text       = $"Error al revertir: {ex.Message}";
            refs.Status.Foreground = BrushRed;
        }
    }

    // "Restablecer a default de Windows" (prompt 71): accion NUEVA, separada de "Revertir". Solo
    // llega aca desde el boton de la card, que la UI muestra unicamente cuando def.Restablecer
    // DefaultAsync != null (uno de los 20 "Seguro") + el tweak esta On + no hay Original capturado.
    // NO escribe nada en TweakStateStore -- el ciclo normal de captura-en-el-primer-toggle sigue
    // igual desde este punto.
    private async Task ResetTweakToDefaultAsync(TweakDefinition def)
    {
        if (def.RestablecerDefaultAsync is null) return; // defensa: no deberia pasar
        if (!_tweakCardRefs.TryGetValue(def.Id, out var refs)) return;

        var confirm = System.Windows.MessageBox.Show(
            $"Se va a escribir el valor de fabrica de Windows para \"{def.Nombre}\".\n\n" +
            "Esto NO restaura la configuracion que tenias antes en este equipo (WinBoost no la " +
            "guardo) -- es el valor predeterminado de Windows, que puede o no coincidir con lo " +
            "que tenias.\n\nContinuar?",
            "WinBoost - Restablecer a default de Windows",
            MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (confirm != MessageBoxResult.Yes) return;

        if (refs.ResetPanel is not null) refs.ResetPanel.IsEnabled = false;
        try
        {
            await def.RestablecerDefaultAsync();
            var status = await def.LeerEstadoAsync();
            AdjustActiveTweaksCache(def.Id, status.State); // antes de UpdateTweakCardUi
            UpdateTweakCardUi(def.Id, status);             // si quedo Off, oculta el panel de reset

            if (status.State != TweakState.On) // Off, o NoAplicable -- en ambos casos ya no esta activo
            {
                refs.Status.Text = def.RequiereReinicio
                    ? "Restablecido al valor de fabrica de Windows. Reinicia el equipo para que tenga efecto completo."
                    : "Restablecido al valor de fabrica de Windows.";
                refs.Status.Foreground = def.RequiereReinicio ? BrushYellow : BrushLicFree;
                App.Logger.Log($"{def.Nombre}: restablecido a default de Windows", "ok");
            }
            else
            {
                // Se escribio el default pero el tweak sigue figurando activo (ej. una clave HKLM
                // protegida que no se pudo tocar) -- decirlo, no afirmar un exito que no paso.
                refs.Status.Text = "Se escribio el valor de fabrica de Windows, pero el tweak sigue figurando como activo. " +
                                    "Revisa la consola.";
                refs.Status.Foreground = BrushYellow;
                App.Logger.Log($"{def.Nombre}: restablecer a default no dejo el tweak en Off", "err");
            }
        }
        catch (Exception ex)
        {
            var real = await def.LeerEstadoAsync();
            AdjustActiveTweaksCache(def.Id, real.State);
            UpdateTweakCardUi(def.Id, real);
            refs.Status.Text       = $"Error al restablecer: {ex.Message}";
            refs.Status.Foreground = BrushRed;
        }
        finally
        {
            if (refs.ResetPanel is not null) refs.ResetPanel.IsEnabled = true;
        }
    }

    // Info de componentes (overlay System Info, Home).
    // Mirror de New-InfoRow del PS1 (label 160px + valor). La fila de HAGS aca es
    // SOLO informativa; el toggle de activar/desactivar HAGS vive en la seccion Tweaks
    // (prompt 56 -- antes vivia en la pestana Tuning Avanzado, ya retirada).
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

    // ── Limpieza del Driver Store (seccion Limpieza desde el prompt 75; antes en Herramientas) ──
    // El XAML (btnScanDrvStore/btnDriverBackup/btnDriverDelete/lblDriverStatus/drvListScroll/
    // icDrvStore) se movio de Herramientas a Limpieza en el prompt 75. Estos handlers y BuildDriverRow
    // no cambiaron -- TuningService sigue siendo el servicio que hace el trabajo real.

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

        // Deshabilitar UI y abrir el overlay de consola en modo operacion (fix 27)
        btnScanBloat.IsEnabled    = false;
        btnRemoveBloat.IsEnabled  = false;
        btnBloatSelAll.IsEnabled  = false;
        btnBloatSelNone.IsEnabled = false;
        OpenConsoleOverlay(running: true); // era SetActiveNav(5); "Detener" cancela via App.Worker

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

        ConsoleOperationCompleted(); // fix 27: oculta "Detener", habilita "Cerrar", chip Completado

        // Rehabilitar UI
        btnScanBloat.IsEnabled    = true;
        btnBloatSelAll.IsEnabled  = true;
        btnBloatSelNone.IsEnabled = true;

        // Re-escanear automaticamente para reflejar cambios
        SetActiveNav(3); // Bloatware (era 4, prompt 66)
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
