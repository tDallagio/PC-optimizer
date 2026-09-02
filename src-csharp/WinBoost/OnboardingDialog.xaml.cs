using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace WinBoost;

// ============================================================
// MODULO 15B - VENTANA DE BIENVENIDA (ONBOARDING)
// Mirror de Show-OnboardingDialog del PS1. Wizard de 3 pasos
// mostrado solo en la primera ejecucion. Bloquea el cierre (X)
// hasta completar el ultimo paso.
// Prompt 66 (retiro del tab Optimizar clasico): se saco el paso
// de seleccion de perfil -- aplicaba los checkboxes de esa
// pantalla, que dejaron de existir. Pausado a proposito: no se
// construyo ningun reemplazo (aplicar un preset real contra
// TweakRegistry, u otra forma de "vender" el paso) -- eso queda
// para un prompt aparte una vez que se decida de fondo. El wizard
// ya no elige ni aplica ningun preset, solo muestra hardware +
// score y cierra.
// ============================================================
public partial class OnboardingDialog : Window
{
    private static readonly SolidColorBrush BrushOn  = Freeze("#00C8FF");
    private static readonly SolidColorBrush BrushOff = Freeze("#2A2A2A");

    private static readonly string[] Titles =
    {
        "Bienvenido a WinBoost",
        "Tu salud del sistema",
        "Todo listo",
    };
    private static readonly string[] Subs =
    {
        "Revisamos tu hardware en unos pasos rapidos.",
        "Analizamos el estado actual de tu PC.",
        "WinBoost configurado y listo para usar.",
    };

    private int  _step;
    private bool _canClose;

    private Border[] _panels = null!;
    private Border[] _dots   = null!;

    // true si el usuario completo el wizard (llego al ultimo paso y cerro con "Empezar").
    public bool Completed { get; private set; }

    public OnboardingDialog(string cpuName, string gpuName, int ramGb, string diskType,
        bool isLaptop, int score)
    {
        InitializeComponent();

        // step2/dot2 (seleccion de preset) se eliminaron del XAML -- step3/dot3 (paso "listo")
        // quedan con su x:Name original, sin renombrar, para minimizar el diff.
        _panels = new[] { step0, step1, step3 };
        _dots   = new[] { dot0, dot1, dot3 };

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

        UpdateStep();
    }

    // Mirror de obdUpdateStep: visibilidad de pasos, dots, titulos y botones.
    private void UpdateStep()
    {
        for (int i = 0; i < _panels.Length; i++)
        {
            _panels[i].Visibility = i == _step ? Visibility.Visible : Visibility.Collapsed;
            _dots[i].Background   = i <= _step ? BrushOn : BrushOff;
        }
        lblObdStepTitle.Text = Titles[_step];
        lblObdStepSub.Text   = Subs[_step];
        btnObdBack.IsEnabled = _step > 0;
        btnObdNext.Content   = _step == _panels.Length - 1 ? "Empezar" : "Siguiente";
    }

    private void OnBack(object sender, RoutedEventArgs e)
    {
        if (_step > 0) { _step--; UpdateStep(); }
    }

    private void OnNext(object sender, RoutedEventArgs e)
    {
        if (_step < _panels.Length - 1)
        {
            _step++;
            UpdateStep();
        }
        else
        {
            Completed = true;
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
