using System.Windows;
using WinBoost.Services;

namespace WinBoost;

public partial class App : Application
{
    internal static SettingsService Settings { get; } = new();
    internal static AppLogger       Logger   { get; set; } = null!;
    internal static ProgressService Progress { get; set; } = null!;
    internal static WorkRunner      Worker   { get; } = new();
}
