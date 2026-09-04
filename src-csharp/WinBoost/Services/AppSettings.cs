namespace WinBoost.Services;

internal sealed class AppSettings
{
    public string Theme               { get; set; } = "dark";
    public string Language            { get; set; } = "es";
    public string CloseAction         { get; set; } = "exit";
    public bool   ShowSplash          { get; set; } = true;
    public int    ProcRefreshSec      { get; set; } = 3;
    public bool   ProcAutoRefresh     { get; set; } = true;
    public bool   RunAtStartup        { get; set; } = false;
    public string BackupRoot          { get; set; } = DefaultBackupRoot;
    public int    BackupRetainDays    { get; set; } = 30;
    public string TechnicianName      { get; set; } = "";
    public bool   FirstRunCompleted   { get; set; } = false;
    // TrialStartDate / TrialExpired se removieron en el prompt 82 (trial de 14 dias eliminado).
    // Sin logica de migracion: no hay usuarios con settings.json existente, y System.Text.Json
    // ignora campos desconocidos al deserializar, asi que un settings.json viejo con esos
    // campos no rompe SettingsService.Load().

    internal static readonly string DefaultBackupRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "backups");
}
