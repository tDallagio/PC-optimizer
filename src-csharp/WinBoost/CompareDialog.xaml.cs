using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using WinBoost.Services;

namespace WinBoost;

// Equivalente a Show-CompareDialog del PS1 (modulo 11B).
// Result: "restart" | "later" | "log"
public partial class CompareDialog : Window
{
    public string Result { get; private set; } = "later";

    private static readonly Color ColBetter  = Color.FromRgb(0x22, 0xC5, 0x5E);
    private static readonly Color ColNeutral = Color.FromRgb(0x55, 0x55, 0x55);
    private static readonly Color ColWorse   = Color.FromRgb(0xEF, 0x44, 0x44);
    private static readonly Color ColValue   = Color.FromRgb(0xCC, 0xCC, 0xCC);
    private static readonly Color ColLabel   = Color.FromRgb(0x77, 0x77, 0x77);
    private static readonly Color ColBg      = Color.FromRgb(0x16, 0x16, 0x16);
    private static readonly Color ColBgAlt   = Color.FromRgb(0x11, 0x11, 0x11);

    public CompareDialog(IReadOnlyList<CompareRow> compare, double freedMb)
    {
        InitializeComponent();
        BuildRows(compare, freedMb);
    }

    private void BuildRows(IReadOnlyList<CompareRow> compare, double freedMb)
    {
        spRows.Children.Add(BuildHeader());

        int rowIdx = 0;
        foreach (var r in compare)
        {
            string bef = r.Before.ToString();
            string aft = r.After.ToString();
            if (r.Label.Contains("MB"))      { bef = $"{r.Before} MB"; aft = $"{r.After} MB"; }
            else if (r.Label.Contains("(%)")) { bef = $"{r.Before}%";  aft = $"{r.After}%"; }

            spRows.Children.Add(MakeRow(r.Label, bef, aft, r.Delta, r.Status, rowIdx % 2 == 1));
            rowIdx++;
        }

        // Fila extra: MB liberados (de freedMb, no del snapshot)
        int freed = (int)Math.Round(freedMb);
        string freedStatus = freed > 0 ? "better" : "neutral";
        spRows.Children.Add(MakeRow("MB liberados", "0 MB", $"{freed} MB", freed, freedStatus, rowIdx % 2 == 1));
    }

    // Header de columnas: "" | Metrica | Antes | Despues | Delta
    private static Border BuildHeader()
    {
        var bdr = new Border
        {
            Padding = new Thickness(12, 4, 12, 6),
            Margin  = new Thickness(0, 0, 0, 2),
        };
        var grid = MakeColumns();

        string[] labels = ["", "Metrica", "Antes", "Despues", "Delta"];
        for (int ci = 0; ci < labels.Length; ci++)
        {
            var ht = new TextBlock
            {
                Text                = labels[ci],
                FontSize            = 10,
                FontWeight          = FontWeights.SemiBold,
                Foreground          = new SolidColorBrush(Color.FromRgb(0x55, 0x55, 0x55)),
                VerticalAlignment   = VerticalAlignment.Center,
                HorizontalAlignment = ci >= 2
                    ? System.Windows.HorizontalAlignment.Center
                    : System.Windows.HorizontalAlignment.Left,
            };
            Grid.SetColumn(ht, ci);
            grid.Children.Add(ht);
        }
        bdr.Child = grid;
        return bdr;
    }

    // Mirror del scriptblock $mkRow del PS1.
    private static Border MakeRow(string label, string valBefore, string valAfter,
        int delta, string status, bool alt)
    {
        Color sColor = status switch
        {
            "better" => ColBetter,
            "worse"  => ColWorse,
            _        => ColNeutral,
        };
        string sign      = delta > 0 ? "+" : "";
        string deltaText = delta == 0 ? "Sin cambio" : $"{sign}{delta}";

        var bdr = new Border
        {
            Background   = new SolidColorBrush(alt ? ColBgAlt : ColBg),
            CornerRadius = new CornerRadius(5),
            Padding      = new Thickness(12, 7, 12, 7),
            Margin       = new Thickness(0, 2, 0, 0),
        };
        var grid = MakeColumns();

        // Dot indicador de estado
        var dot = new Ellipse
        {
            Width               = 8,
            Height              = 8,
            VerticalAlignment   = VerticalAlignment.Center,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            Fill                = new SolidColorBrush(sColor),
        };
        Grid.SetColumn(dot, 0);

        var tLabel = new TextBlock
        {
            Text              = label,
            FontSize          = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground        = new SolidColorBrush(ColValue),
        };
        Grid.SetColumn(tLabel, 1);

        var tBef = new TextBlock
        {
            Text                = valBefore,
            FontSize            = 12,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment   = VerticalAlignment.Center,
            Foreground          = new SolidColorBrush(ColLabel),
        };
        Grid.SetColumn(tBef, 2);

        var tAft = new TextBlock
        {
            Text                = valAfter,
            FontSize            = 12,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment   = VerticalAlignment.Center,
            Foreground          = new SolidColorBrush(ColValue),
        };
        Grid.SetColumn(tAft, 3);

        var tDelta = new TextBlock
        {
            Text                = deltaText,
            FontSize            = 11,
            FontWeight          = FontWeights.SemiBold,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment   = VerticalAlignment.Center,
            Foreground          = new SolidColorBrush(sColor),
        };
        Grid.SetColumn(tDelta, 4);

        grid.Children.Add(dot);
        grid.Children.Add(tLabel);
        grid.Children.Add(tBef);
        grid.Children.Add(tAft);
        grid.Children.Add(tDelta);
        bdr.Child = grid;
        return bdr;
    }

    // Columnas: 16 | * | 90 | 90 | 80
    private static Grid MakeColumns()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
        return grid;
    }

    private void OnRestart(object sender, RoutedEventArgs e) { Result = "restart"; Close(); }
    private void OnLater(object sender, RoutedEventArgs e)   { Result = "later";   Close(); }
    private void OnViewLog(object sender, RoutedEventArgs e) { Result = "log";     Close(); }
}
