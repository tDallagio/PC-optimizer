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
    public string TrialStartDate      { get; set; } = "";
    public bool   TrialExpired        { get; set; } = false;
    public string TechnicianName      { get; set; } = "";
    public bool   FirstRunCompleted   { get; set; } = false;

    internal static readonly string DefaultBackupRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "backups");
}
