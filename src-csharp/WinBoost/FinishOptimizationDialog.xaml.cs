using System.Windows;
using WinBoost.Services;

namespace WinBoost;

public partial class FinishOptimizationDialog : Window
{
    public bool GoToHistory  { get; private set; }
    public bool ShowCompare  { get; private set; }

    public FinishOptimizationDialog(OptResult result, int scoreBefore, int scoreAfter,
        bool needsReboot, bool canCompare = false)
    {
        InitializeComponent();
        Populate(result, scoreBefore, scoreAfter, needsReboot);
        if (canCompare) btnCompare.Visibility = Visibility.Visible;
    }

    private void Populate(OptResult result, int scoreBefore, int scoreAfter, bool needsReboot)
    {
        lblAppliedCount.Text = $"{result.Applied}";
        lblSkippedCount.Text = $"{result.Skipped}";
        lblFreedMb.Text      = result.FreedMb >= 1
            ? $"{Math.Round(result.FreedMb, 0):F0}"
            : $"{Math.Round(result.FreedMb, 1)}";

        // Score panel (solo si tenemos scores validos)
        if (scoreBefore > 0 || scoreAfter > 0)
        {
            lblScoreBefore.Text = $"{scoreBefore}";
            lblScoreAfter.Text  = $"{scoreAfter}";
            panelScore.Visibility = Visibility.Visible;

            int delta = scoreAfter - scoreBefore;
            if (delta != 0)
            {
                lblDelta.Text          = delta > 0 ? $"+{delta}" : $"{delta}";
                lblDelta.Foreground    = delta > 0
                    ? System.Windows.Media.Brushes.LightGreen
                    : System.Windows.Media.Brushes.OrangeRed;
                badgeDelta.Visibility  = Visibility.Visible;
            }
        }

        if (needsReboot)
            panelReboot.Visibility = Visibility.Visible;
    }

    private void OnGoHistory(object sender, RoutedEventArgs e)
    {
        GoToHistory = true;
        Close();
    }

    private void OnCompare(object sender, RoutedEventArgs e)
    {
        ShowCompare = true;
        Close();
    }

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    private void OnTitleDrag(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (e.LeftButton == System.Windows.Input.MouseButtonState.Pressed)
            DragMove();
    }
}
