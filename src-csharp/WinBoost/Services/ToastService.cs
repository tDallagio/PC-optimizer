using System.Windows.Threading;

namespace WinBoost.Services;

internal static class ToastService
{
    internal static void Show(string title, string message)
    {
        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            try
            {
                var ni = new System.Windows.Forms.NotifyIcon
                {
                    Icon    = System.Drawing.SystemIcons.Application,
                    Visible = true,
                };
                ni.ShowBalloonTip(5000, title, message, System.Windows.Forms.ToolTipIcon.None);

                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(6) };
                timer.Tick += (_, _) => { ni.Dispose(); timer.Stop(); };
                timer.Start();
            }
            catch { }
        });
    }
}
