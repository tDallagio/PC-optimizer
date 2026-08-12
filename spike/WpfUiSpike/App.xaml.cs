using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace WpfUiSpike;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DiagLog.Write($"=== WpfUiSpike arranca === log en {DiagLog.LogPath}");

        // Captura global de excepciones: se agrego para diagnosticar el crash de navegacion
        // de 11_diag_crash_navegacion_spike.txt (ya resuelto, ver 12_fix_crash_navegacion_spike.txt).
        // Se deja a proposito mientras el spike siga en evaluacion, por si aparece otra cosa;
        // no es parte del control/producto real que se esta evaluando. Ver spike/WpfUiSpike/README.md.
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnAppDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;

        // Marca WinBoost sobre el theming de WPF-UI: tema oscuro + accent #00C8FF.
        // updateAccent:false porque el accent se setea a mano abajo (no queremos que
        // ApplicationThemeManager lo pise con el accent del sistema).
        ApplicationThemeManager.Apply(ApplicationTheme.Dark, WindowBackdropType.Mica, updateAccent: false);
        ApplicationAccentColorManager.Apply(
            (Color)ColorConverter.ConvertFromString("#00C8FF"),
            ApplicationTheme.Dark);
    }

    private static void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        DiagLog.WriteException("DispatcherUnhandledException (hilo UI)", e.Exception);

        // No se suprime: queremos ver el crash real, solo lo logueamos antes de que reviente.
        e.Handled = false;
    }

    private static void OnAppDomainUnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            DiagLog.WriteException($"AppDomain.UnhandledException (IsTerminating={e.IsTerminating})", ex);
        }
        else
        {
            DiagLog.Write($"AppDomain.UnhandledException (IsTerminating={e.IsTerminating}) - objeto no es Exception: {e.ExceptionObject}");
        }
    }

    private static void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        DiagLog.WriteException("TaskScheduler.UnobservedTaskException (excepcion async no observada)", e.Exception);
        e.SetObserved();
    }
}

/// <summary>
/// Logging minimo a archivo de excepciones no manejadas, para el spike. No es parte del
/// control/producto que se esta evaluando; se mantiene mientras el spike siga en evaluacion.
/// </summary>
internal static class DiagLog
{
    public static readonly string LogPath = Path.Combine(Path.GetTempPath(), "WpfUiSpike_crash.log");

    private static readonly object Gate = new();

    public static void Write(string message)
    {
        lock (Gate)
        {
            try
            {
                File.AppendAllText(LogPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}{Environment.NewLine}");
            }
            catch
            {
                // El logging de diagnostico nunca debe tapar/reemplazar el crash real.
            }
        }
    }

    public static void WriteException(string context, Exception ex)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] *** {context} ***");

        var current = ex;
        var level = 0;
        while (current is not null)
        {
            sb.AppendLine($"--- Nivel {level} ---");
            sb.AppendLine($"Tipo: {current.GetType().FullName}");
            sb.AppendLine($"Message: {current.Message}");
            sb.AppendLine($"HResult: 0x{current.HResult:X8} ({current.HResult})");
            sb.AppendLine("StackTrace:");
            sb.AppendLine(current.ToString());
            current = current.InnerException;
            level++;
        }

        lock (Gate)
        {
            try
            {
                File.AppendAllText(LogPath, sb.ToString());
            }
            catch
            {
                // idem arriba
            }
        }
    }
}
