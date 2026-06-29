using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using WinBoost.Services;

namespace WinBoost;

public partial class ConfirmOptimizationDialog : Window
{
    private static readonly SolidColorBrush _brushCategory = new(Color.FromRgb(0x00, 0xC8, 0xFF));
    private static readonly SolidColorBrush _brushLabel    = new(Color.FromRgb(0xCC, 0xCC, 0xCC));
    private static readonly SolidColorBrush _brushDetail   = new(Color.FromRgb(0x66, 0x66, 0x66));
    private static readonly SolidColorBrush _brushHighImp  = new(Color.FromRgb(0xF5, 0x9E, 0x0B));
    private static readonly SolidColorBrush _brushMidImp   = new(Color.FromRgb(0x88, 0x88, 0x88));

    static ConfirmOptimizationDialog()
    {
        _brushCategory.Freeze();
        _brushLabel.Freeze();
        _brushDetail.Freeze();
        _brushHighImp.Freeze();
        _brushMidImp.Freeze();
    }

    public ConfirmOptimizationDialog(IReadOnlyList<PlanAction> plan)
    {
        InitializeComponent();
        PopulatePlan(plan);
    }

    private void PopulatePlan(IReadOnlyList<PlanAction> plan)
    {
        // ── Contador ─────────────────────────────────────────────────────────
        int n = plan.Count;
        lblActionCount.Text = n == 0
            ? "No hay acciones seleccionadas."
            : $"Se aplicaran {n} {(n == 1 ? "accion" : "acciones")} en tu sistema.";

        // ── Acciones de impacto alto ──────────────────────────────────────────
        var high = plan.Where(a => a.Impact == "high").ToList();
        if (high.Any())
        {
            lblHighImpact.Text = string.Join(" · ", high.Select(a => a.Label));
            panelHighImpact.Visibility = Visibility.Visible;
        }

        // ── Punto de restauracion ─────────────────────────────────────────────
        if (plan.Any(a => a.Label == "Punto de restauracion"))
            panelRestorePoint.Visibility = Visibility.Visible;

        // ── Grupos por categoria ──────────────────────────────────────────────
        // Orden fijo: Seguridad > Limpieza > Rendimiento > Privacidad > Red > Servicios
        var order = new[] { "Seguridad", "Limpieza", "Rendimiento", "Privacidad", "Red", "Servicios" };
        var groups = plan
            .GroupBy(a => a.Category)
            .OrderBy(g =>
            {
                int i = Array.IndexOf(order, g.Key);
                return i < 0 ? 99 : i;
            });

        foreach (var group in groups)
        {
            // Separador visual entre grupos
            if (spActions.Children.Count > 0)
                spActions.Children.Add(new Border { Height = 8 });

            // Header de categoria
            var header = new TextBlock
            {
                Text       = group.Key.ToUpperInvariant(),
                FontSize   = 10,
                FontWeight = FontWeights.SemiBold,
                Foreground = _brushCategory,
                Margin     = new Thickness(0, 0, 0, 4),
            };
            spActions.Children.Add(header);

            foreach (var action in group)
            {
                bool isHigh = action.Impact == "high";
                bool isMid  = action.Impact == "medium";

                // Fila de accion: icono dot + label + detail
                var row = new Grid { Margin = new Thickness(0, 1, 0, 1) };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                // Col 0: dot
                var dot = new TextBlock
                {
                    Text              = "·",
                    Foreground        = isHigh ? _brushHighImp : _brushMidImp,
                    FontSize          = 13,
                    VerticalAlignment = VerticalAlignment.Top,
                    Margin            = new Thickness(0, 0, 0, 0),
                };
                Grid.SetColumn(dot, 0);

                // Col 1: label
                var lblAction = new TextBlock
                {
                    Text              = action.Label,
                    FontSize          = 11,
                    Foreground        = isHigh ? _brushHighImp : _brushLabel,
                    FontWeight        = isHigh ? FontWeights.SemiBold : FontWeights.Normal,
                    VerticalAlignment = VerticalAlignment.Top,
                    TextTrimming      = TextTrimming.CharacterEllipsis,
                };
                Grid.SetColumn(lblAction, 1);

                // Col 2: detail
                var lblDetail = new TextBlock
                {
                    Text         = action.Detail,
                    FontSize     = 10,
                    Foreground   = _brushDetail,
                    TextWrapping = TextWrapping.Wrap,
                    Margin       = new Thickness(8, 1, 0, 0),
                };
                Grid.SetColumn(lblDetail, 2);

                row.Children.Add(dot);
                row.Children.Add(lblAction);
                row.Children.Add(lblDetail);
                spActions.Children.Add(row);
            }
        }
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    private void OnConfirm(object sender, RoutedEventArgs e) => DialogResult = true;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;

    private void OnTitleDrag(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (e.LeftButton == System.Windows.Input.MouseButtonState.Pressed)
            DragMove();
    }
}
