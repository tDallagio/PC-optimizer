using System.Windows;
using System.Windows.Controls;

namespace WinBoost.Services;

internal sealed class ProgressService
{
    private readonly ProgressBar _bar;
    private readonly TextBlock   _lblMsg;
    private readonly TextBlock   _lblPct;

    internal ProgressService(ProgressBar bar, TextBlock lblMsg, TextBlock lblPct)
    {
        _bar    = bar;
        _lblMsg = lblMsg;
        _lblPct = lblPct;
    }

    internal void Set(int pct, string message)
    {
        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            _bar.Value   = Math.Clamp(pct, 0, 100);
            _lblMsg.Text = message;
            _lblPct.Text = $"{pct}%";
        });
    }
}
