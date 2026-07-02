namespace WinBoost.Services;

internal sealed class NullLogger : IAppLogger
{
    internal static readonly NullLogger Instance = new();
    public void Log(string message, string type = "info") { }
}

internal sealed class SilentFileLogger : IAppLogger
{
    private readonly string _logPath;

    private static readonly Dictionary<string, string> Labels = new()
    {
        ["ok"]   = "  OK   ",
        ["err"]  = "  !!   ",
        ["skip"] = "  --   ",
        ["head"] = " ====  ",
        ["info"] = "  >>   ",
    };

    internal SilentFileLogger(string logPath)
    {
        _logPath = logPath;
    }

    public void Log(string message, string type = "info")
    {
        string ts    = DateTime.Now.ToString("HH:mm:ss");
        string label = Labels.GetValueOrDefault(type, "  >>   ");
        string line  = $"{ts}{label}{message}";
        try { File.AppendAllText(_logPath, line + Environment.NewLine); }
        catch { }
    }
}
