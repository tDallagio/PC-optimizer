using System.Windows;
using System.Windows.Controls;

namespace WinBoost.Services;

internal sealed class ProgressService
{
    // Fix 28.3: la barra de progreso salio de Optimizar; el progreso vive SOLO en el overlay de
    // consola. ProgressService apunta directo a esos controles (progressBarConsole/labels). Se
    // revirtio el "mirror" del fix 26 (ya no hay dos barras que sincronizar).
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
