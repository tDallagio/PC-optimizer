using System.Windows;
using System.Windows.Controls;
using Wpf.Ui.Controls;

namespace WpfUiSpike.Views;

/// <summary>
/// Interaction logic for DashboardPage.xaml
/// </summary>
public partial class DashboardPage : Page
{
    public DashboardPage()
    {
        InitializeComponent();
    }

    private async void OnOpenDialogClick(object sender, RoutedEventArgs e)
    {
        // El ContentDialogHost vive en MainWindow (uno por ventana), no en la pagina: ver
        // 12_fix_crash_navegacion_spike.txt.
        var dialogHost = (Window.GetWindow(this) as MainWindow)?.DialogHost;
        if (dialogHost is null)
        {
            return;
        }

        var dialog = new ContentDialog(dialogHost)
        {
            Title = "Diálogo de prueba",
            Content = "Esto es un Wpf.Ui.Controls.ContentDialog, evaluado como reemplazo de los " +
                      "MessageBox nativos (item 8 del rediseño).",
            PrimaryButtonText = "Aceptar",
            CloseButtonText = "Cerrar",
        };

        await dialog.ShowAsync();
    }
}
