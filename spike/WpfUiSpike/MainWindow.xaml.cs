using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;
using WpfUiSpike.Views;

namespace WpfUiSpike;

/// <summary>
/// Interaction logic for MainWindow.xaml
/// </summary>
public partial class MainWindow : FluentWindow
{
    /// <summary>
    /// Host del ContentDialog, único por ventana (ver comentario en MainWindow.xaml). Las
    /// páginas que necesitan mostrar un diálogo usan este host en vez de declarar el suyo.
    /// </summary>
    public ContentDialogHost DialogHost => RootDialogHost;

    public MainWindow()
    {
        InitializeComponent();

        SystemThemeWatcher.Watch(this);

        // NavigationView arma su Frame interno via ControlTemplate; ese template recien
        // se aplica cuando el control se carga, no en el constructor de la ventana (si se
        // navega antes, UpdateContent revienta con NullReferenceException).
        Loaded += (_, _) => RootNavigation.Navigate(typeof(DashboardPage));
    }
}
