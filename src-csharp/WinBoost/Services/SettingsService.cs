using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace WinBoost.Services;

internal sealed class SettingsService
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "settings.json");

    internal AppSettings Current { get; private set; } = new();

    internal void Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return;
            var loaded = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath));
            if (loaded is null) return;

            if (!string.IsNullOrEmpty(loaded.Theme))       Current.Theme             = loaded.Theme;
            if (!string.IsNullOrEmpty(loaded.Language))    Current.Language          = loaded.Language;
            if (!string.IsNullOrEmpty(loaded.CloseAction)) Current.CloseAction       = loaded.CloseAction;
            Current.ShowSplash          = loaded.ShowSplash;
            Current.ProcRefreshSec      = loaded.ProcRefreshSec > 0 ? loaded.ProcRefreshSec : 3;
            Current.ProcAutoRefresh     = loaded.ProcAutoRefresh;
            Current.RunAtStartup        = loaded.RunAtStartup;
            if (!string.IsNullOrEmpty(loaded.BackupRoot))  Current.BackupRoot        = loaded.BackupRoot;
            Current.BackupRetainDays    = loaded.BackupRetainDays > 0 ? loaded.BackupRetainDays : 30;
            Current.TrialStartDate      = loaded.TrialStartDate  ?? "";
            Current.TrialExpired        = loaded.TrialExpired;
            Current.TechnicianName      = loaded.TechnicianName  ?? "";
            Current.FirstRunCompleted   = loaded.FirstRunCompleted;
        }
        catch { }
    }

    internal void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath,
                JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    // WinBoost es dark-only (decision de producto): no hay ramas light/auto. Ver
    // docs/CHANGELOG.md para el detalle. A futuro podrian sumarse VARIANTES dark con
    // distinto acento (nunca un tema claro), pero eso no esta cableado aca todavia.
    internal void ApplyTheme(Window window)
    {
        try
        {
            var palette = new Dictionary<string, string>
            {
                ["BrushAppBg"]   = "#0D0D0D", ["BrushSidebar"] = "#111111",
                ["BrushCard"]    = "#161616",  ["BrushDeep"]   = "#0A0A0A",
                ["BrushElev"]    = "#1A1A1A",  ["BrushCtrl"]   = "#1E1E1E",
                ["BrushBorder"]  = "#2A2A2A",
                ["BrushFg1"]     = "#EEEEEE",  ["BrushFg2"]    = "#CCCCCC",
                ["BrushFgMuted"] = "#888888",  ["BrushFgDim"]  = "#555555",
            };

            foreach (var (key, hex) in palette)
            {
                var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
                brush.Freeze();
                window.Resources[key] = brush;
            }

            // Reconcilia el tema de WPF-UI (fundacion) con el swap propio de WinBoost: los
            // controles con estilo implicito de WPF-UI (ComboBox/CheckBox/etc. en ventanas sin
            // override local, ScrollBar de los dialogos secundarios) quedan fijos en oscuro
            // tambien. updateAccent:false para no perder el acento de marca fijado en
            // App.xaml.cs.
            Wpf.Ui.Appearance.ApplicationThemeManager.Apply(
                Wpf.Ui.Appearance.ApplicationTheme.Dark,
                Wpf.Ui.Controls.WindowBackdropType.None,
                updateAccent: false);
        }
        catch { }
    }

    internal void Apply(Window window)
    {
        ApplyTheme(window);
        ApplyStartup();
    }

    private void ApplyStartup()
    {
        const string keyPath   = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string valueName = "WinBoost";
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(keyPath, writable: true);
            if (key is null) return;
            if (Current.RunAtStartup)
            {
                var exe = Environment.ProcessPath ?? "";
                if (!string.IsNullOrEmpty(exe))
                    key.SetValue(valueName, $"\"{exe}\"");
            }
            else
            {
                key.DeleteValue(valueName, throwOnMissingValue: false);
            }
        }
        catch { }
    }
}
