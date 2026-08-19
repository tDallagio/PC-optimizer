using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace WinBoost.Services;

public interface IAppLogger
{
    void Log(string message, string type = "info");
    void ClearErrorBadge();
}

internal sealed class AppLogger : IAppLogger
{
    private readonly RichTextBox  _rtb;
    private readonly ScrollViewer _scroll;
    private readonly Button       _errBadge;
    private readonly TextBlock    _errCount;
    private readonly List<string> _errors = [];
    // Fix 28.4: errores ya "reconocidos" (el usuario clickeo el badge). NO se borran de _errors ni
    // del log: solo desplazan el conteo VISIBLE. El badge muestra los errores nuevos desde el reset.
    private int _ackedErrors = 0;

    private static readonly Dictionary<string, string> Colors = new()
    {
        ["ok"]   = "#22C55E",
        ["err"]  = "#EF4444",
        ["skip"] = "#666666",
        ["head"] = "#00C8FF",
        ["info"] = "#F59E0B",
    };

    private static readonly Dictionary<string, string> Labels = new()
    {
        ["ok"]   = "  OK   ",
        ["err"]  = "  !!   ",
        ["skip"] = "  --   ",
        ["head"] = " ====  ",
        ["info"] = "  >>   ",
    };

    internal AppLogger(RichTextBox rtb, ScrollViewer scroll, Button errBadge, TextBlock errCount)
    {
        _rtb      = rtb;
        _scroll   = scroll;
        _errBadge = errBadge;
        _errCount = errCount;
    }

    public void Log(string message, string type = "info")
    {
        string ts    = DateTime.Now.ToString("HH:mm:ss");
        string label = Labels.GetValueOrDefault(type, "  >>   ");
        string color = Colors.GetValueOrDefault(type, "#888888");
        string line  = $"{ts}{label}{message}";

        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            if (type == "err")
            {
                _errors.Add($"{ts}  {message}");
                int n = _errors.Count - _ackedErrors; // solo los no reconocidos
                if (n > 0)
                {
                    _errBadge.Visibility = Visibility.Visible;
                    _errCount.Text = n == 1 ? "1 error" : $"{n} errores";
                }
            }

            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
            var run   = new Run(line) { Foreground = brush };
            var para  = new Paragraph(run) { Margin = new Thickness(0) };
            _rtb.Document.Blocks.Add(para);
            _scroll.ScrollToEnd();
        });
    }

    // Fix 28.4: limpia SOLO el cartel visible de errores (lo oculta y pone el conteo en 0). NO
    // borra _errors ni el contenido del log: el usuario sigue leyendo los errores en la consola.
    // Si luego se loguean errores nuevos, el badge reaparece contando desde este reset.
    public void ClearErrorBadge()
    {
        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            _ackedErrors = _errors.Count;
            _errBadge.Visibility = Visibility.Collapsed;
            _errCount.Text = "";
        });
    }
}
