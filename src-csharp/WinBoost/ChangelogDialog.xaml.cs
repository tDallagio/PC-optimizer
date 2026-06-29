using System.Windows;

namespace WinBoost;

// Resultado de la interaccion del usuario con el dialogo de actualizacion.
public enum ChangelogResult { Later, GitHub, Download }

// ============================================================
// Show-ChangelogDialog (parte del modulo 14 - auto-updater)
// Ventana con el changelog de la version disponible y 3 acciones.
// UI desacoplada del motor de updater (FASE 5.3): el caller arma
// el dialogo con la metadata, lo muestra y decide que hacer segun
// Result (Later / GitHub / Download).
// ============================================================
public partial class ChangelogDialog : Window
{
    public ChangelogResult Result { get; private set; } = ChangelogResult.Later;

    public ChangelogDialog(string newVersion, string currentVersion, string changelog,
        bool downloadAvailable)
    {
        InitializeComponent();

        lblUpdateVersion.Text    = $"WinBoost v{newVersion} disponible";
        lblUpdateCurrentVer.Text = $"Version actual: v{currentVersion}";
        tbChangelog.Text         = changelog;

        if (!downloadAvailable)
        {
            btnUpdateDownload.IsEnabled = false;
            btnUpdateDownload.Content   = "Descarga no disponible";
        }
    }

    private void OnLater(object sender, RoutedEventArgs e)
    {
        Result = ChangelogResult.Later;
        Close();
    }

    private void OnGitHub(object sender, RoutedEventArgs e)
    {
        Result = ChangelogResult.GitHub;
        Close();
    }

    private void OnDownload(object sender, RoutedEventArgs e)
    {
        Result = ChangelogResult.Download;
        Close();
    }
}
