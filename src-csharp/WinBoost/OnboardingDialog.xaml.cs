using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace WinBoost;

// ============================================================
// MODULO 15B - VENTANA DE BIENVENIDA (ONBOARDING)
// Mirror de Show-OnboardingDialog del PS1. Wizard de 4 pasos
// mostrado solo en la primera ejecucion. Bloquea el cierre (X)
// hasta completar el paso 4. Devuelve el preset elegido en
// ChosenPreset ("Gaming"/"Prod"/"Safe") para que el caller lo
// aplique y marque el primer uso como completado.
// ============================================================
public partial class OnboardingDialog : Window
{
    private static readonly SolidColorBrush BrushOn  = Freeze("#00C8FF");
    private static readonly SolidColorBrush BrushOff = Freeze("#2A2A2A");

    private static readonly string[] Titles =
    {
        "Bienvenido a WinBoost",
        "Tu salud del sistema",
        "Perfil de optimizacion",
        "Todo listo",
    };
    private static readonly string[] Subs =
    {
        "Revisamos tu hardware en 4 pasos rapidos.",
        "Analizamos el estado actual de tu PC.",
        "Elegimos la configuracion ideal para tu equipo.",
        "WinBoost configurado y listo para usar.",
    };

    private int    _step;
    private string _preset;      // "gaming" / "prod" / "safe"
    private bool   _canClose;

    private Border[] _panels = null!;
    private Border[] _dots   = null!;

    // "Gaming" / "Prod" / "Safe" — null si el usuario aun no completo el wizard.
    public string? ChosenPreset { get; private set; }

    public OnboardingDialog(string cpuName, string gpuName, int ramGb, string diskType,
        bool isLaptop, int score, string recommendedPreset)
    {
        InitializeComponent();

        _panels = new[] { step0, step1, step2, step3 };
        _dots   = new[] { dot0, dot1, dot2, dot3 };
        _preset = recommendedPreset;

        // Paso 0 - hardware
        lblObdCPU.Text  = cpuName;
        lblObdGPU.Text  = gpuName;
        lblObdRAM.Text  = $"{ramGb} GB";
        lblObdDisk.Text = diskType;
        lblObdType.Text = isLaptop ? "Laptop" : "PC Escritorio";

        // Paso 1 - score (mismos umbrales/colores que el PS1)
        string scoreColor = score >= 80 ? "#22C55E" : score >= 60 ? "#F59E0B" : "#EF4444";
        string scoreLabel = score >= 80 ? "Sistema en buen estado"
                          : score >= 60 ? "Hay margen de mejora"
                          : "Optimizacion recomendada";
        lblObdScore.Text       = $"{score}";
        lblObdScoreLabel.Text  = scoreLabel;
        lblObdScore.Foreground = Freeze(scoreColor);

        // Paso 2 - badge del preset recomendado
        Border recBadge = recommendedPreset switch
        {
            "gaming" => badgeRecGaming,
            "prod"   => badgeRecProd,
            _        => badgeRecSafe,
        };
        recBadge.Visibility = Visibility.Visible;

        UpdateStep();
        UpdateCards();
    }

    // Mirror de obdUpdateStep: visibilidad de pasos, dots, titulos y botones.
    private void UpdateStep()
    {
        for (int i = 0; i < 4; i++)
        {
            _panels[i].Visibility = i == _step ? Visibility.Visible : Visibility.Collapsed;
            _dots[i].Background   = i <= _step ? BrushOn : BrushOff;
        }
        lblObdStepTitle.Text = Titles[_step];
        lblObdStepSub.Text   = Subs[_step];
        btnObdBack.IsEnabled = _step > 0;
        btnObdNext.Content   = _step == 3 ? "Empezar" : "Siguiente";
    }

    // Mirror de obdUpdateCards: highlight de tarjetas + resumen del paso 3.
    private void UpdateCards()
    {
        cardGaming.BorderBrush = _preset == "gaming" ? BrushOn : BrushOff;
        cardProd.BorderBrush   = _preset == "prod"   ? BrushOn : BrushOff;
        cardSafe.BorderBrush   = _preset == "safe"   ? BrushOn : BrushOff;
        lblObdPresetChosen.Text = _preset switch
        {
            "gaming" => "Gaming",
            "prod"   => "Productividad",
            _        => "Conservador",
        };
    }

    private void OnPickGaming(object sender, MouseButtonEventArgs e) { _preset = "gaming"; UpdateCards(); }
    private void OnPickProd(object sender, MouseButtonEventArgs e)   { _preset = "prod";   UpdateCards(); }
    private void OnPickSafe(object sender, MouseButtonEventArgs e)   { _preset = "safe";   UpdateCards(); }

    private void OnBack(object sender, RoutedEventArgs e)
    {
        if (_step > 0) { _step--; UpdateStep(); }
    }

    private void OnNext(object sender, RoutedEventArgs e)
    {
        if (_step < 3)
        {
            _step++;
            UpdateStep();
        }
        else
        {
            ChosenPreset = _preset switch
            {
                "gaming" => "Gaming",
                "prod"   => "Prod",
                _        => "Safe",
            };
            _canClose = true;
            Close();
        }
    }

    // Bloquear cierre con X hasta completar el wizard (mirror de Add_Closing).
    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_canClose) e.Cancel = true;
        base.OnClosing(e);
    }

    private static SolidColorBrush Freeze(string hex)
    {
        var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        b.Freeze();
        return b;
    }
}
