using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using WinBoost.Services;

namespace WinBoost;

public partial class MainWindow : Window
{
    private readonly DispatcherTimer _monitorTimer = new() { Interval = TimeSpan.FromSeconds(1) };

    private long _prevIdle, _prevKernel, _prevUser;
    private bool _firstCpuRead = true;
    private NativeMethods.MEMORYSTATUSEX _memStatus;
    private PerformanceCounter? _diskCounter;

    private static readonly SolidColorBrush BrushGreen  = FreezeBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
    private static readonly SolidColorBrush BrushYellow = FreezeBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
    private static readonly SolidColorBrush BrushRed    = FreezeBrush(Color.FromRgb(0xEF, 0x44, 0x44));
    private static readonly SolidColorBrush BrushBlue   = FreezeBrush(Color.FromRgb(0x00, 0xC8, 0xFF));

    // nav buttons indexed 0-8 (navTuning = index 9, no existe en XAML)
    private Button[] _navButtons = [];

    public MainWindow()
    {
        InitializeComponent();
        _memStatus.dwLength = NativeMethods.MemoryStatusExSize;
        Loaded += OnLoaded;
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
            navConsola,      // 1
            navArranque,     // 2
            navHerramientas, // 3
            navInfo,         // 4
            navHistorial,    // 5
            navBloatware,    // 6
            navAjustes,      // 7
            navLicencia,     // 8
        ];

        navOptimizar.Click    += (_, _) => SetActiveNav(0);
        navConsola.Click      += (_, _) => SetActiveNav(1);
        navArranque.Click     += (_, _) => SetActiveNav(2);
        navHerramientas.Click += (_, _) => SetActiveNav(3);
        navInfo.Click         += (_, _) => SetActiveNav(4);
        navHistorial.Click    += (_, _) => SetActiveNav(5);
        navBloatware.Click    += (_, _) => SetActiveNav(6);
        navAjustes.Click      += (_, _) => SetActiveNav(7);
        navLicencia.Click     += (_, _) => SetActiveNav(8);
        // navTuning (index 9) no existe como x:Name en el XAML actual

        App.Settings.Load();
        App.Settings.Apply(this);

        App.Logger   = new AppLogger(rtbLog, logScroll, btnErrBadge, lblErrCount);
        App.Progress = new ProgressService(progressBar, lblProgress, lblPct);

        try { _diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total"); }
        catch { }

        _monitorTimer.Tick += OnMonitorTick;
        _monitorTimer.Start();

        SetActiveNav(0);
        App.Logger.Log("WinBoost iniciado", "head");
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

        lblCPUTemp.Text = "N/D";
        lblGPUTemp.Text = "N/D";
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

        return new Metrics(cpu, usedGb, totalGb, diskPct);
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
        _diskCounter?.Dispose();
        base.OnClosed(e);
    }

    private record struct Metrics(float CpuPct, double RamUsedGb, double RamTotalGb, double DiskPct);
}
