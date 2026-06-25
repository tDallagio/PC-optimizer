using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace WinBoost.Services;

internal sealed class AppLogger
{
    private readonly RichTextBox  _rtb;
    private readonly ScrollViewer _scroll;
    private readonly Button       _errBadge;
    private readonly TextBlock    _errCount;
    private readonly List<string> _errors = [];

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

    internal void Log(string message, string type = "info")
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
                int n = _errors.Count;
                _errBadge.Visibility = Visibility.Visible;
                _errCount.Text = n == 1 ? "1 error" : $"{n} errores";
            }

            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
            var run   = new Run(line) { Foreground = brush };
            var para  = new Paragraph(run) { Margin = new Thickness(0) };
            _rtb.Document.Blocks.Add(para);
            _scroll.ScrollToEnd();
        });
    }
}
