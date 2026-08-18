using System.Windows;
using System.Windows.Controls;

namespace WinBoost.Services;

internal sealed class ProgressService
{
    private readonly ProgressBar _bar;
    private readonly TextBlock   _lblMsg;
    private readonly TextBlock   _lblPct;

    // Mirror opcional a la Consola (fix 26): las operaciones que navegan a la Consola
    // (Bloatware, mantenimiento) muestran su progreso ahi. El mismo Set() actualiza AMBAS
    // barras; como cada una solo es visible en su pestaña, el usuario ve la de la pestaña en
    // la que esta. Sin logica duplicada ni seguimiento de contexto: es un fan-out simple.
    private readonly ProgressBar? _barConsole;
    private readonly TextBlock?   _lblMsgConsole;
    private readonly TextBlock?   _lblPctConsole;

    internal ProgressService(ProgressBar bar, TextBlock lblMsg, TextBlock lblPct,
                             ProgressBar? barConsole = null, TextBlock? lblMsgConsole = null,
                             TextBlock? lblPctConsole = null)
    {
        _bar    = bar;
        _lblMsg = lblMsg;
        _lblPct = lblPct;
        _barConsole    = barConsole;
        _lblMsgConsole = lblMsgConsole;
        _lblPctConsole = lblPctConsole;
    }

    internal void Set(int pct, string message)
    {
        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            int v = Math.Clamp(pct, 0, 100);
            _bar.Value   = v;
            _lblMsg.Text = message;
            _lblPct.Text = $"{pct}%";

            if (_barConsole    is { } bc) bc.Value  = v;
            if (_lblMsgConsole is { } mc) mc.Text   = message;
            if (_lblPctConsole is { } pc) pc.Text   = $"{pct}%";
        });
    }
}
