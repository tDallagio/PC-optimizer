using System.Diagnostics;
using System.Text.Json;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────

// Entrada de la base de datos de bloatware (mirror de $script:bloatwareDb)
public record BloatwareDbEntry(
    string  Name,
    string? PackageId,
    string? WingetId,
    string  Category,
    string  Method,      // "appx" | "winget" | "appx+winget"
    string  Risk,        // "safe" | "caution"
    int     EstimateMB);

// App detectada e instalada en el sistema
public record DetectedApp(
    string  Name,
    string  Category,
    string  Method,
    string  Risk,
    int     EstimateMB,
    string? PackageFN,   // PackageFamilyName real (null si solo winget)
    string? WingetId);

public record BloatwareSummary(
    int Count,
    int TotalMB,
    int SafeCount,
    int CautionCount);

public record RemoveResult(
    string Name,
    bool   Ok,
    string Method,
    string Message);

// ─────────────────────────────────────────────────────────────────────────────

public sealed class BloatwareService
{
    // ── Base de datos — mirror de $script:bloatwareDb del PS1 ────────────────
    private static readonly BloatwareDbEntry[] _db =
    [
        // JUEGOS PREINSTALADOS
        new("Candy Crush Saga",          "king.com.CandyCrushSaga",               null,                               "Juegos",       "appx",        "safe",    120),
        new("Candy Crush Friends",       "king.com.CandyCrushFriendsSaga",        null,                               "Juegos",       "appx",        "safe",    110),
        new("Candy Crush Soda Saga",     "king.com.CandyCrushSodaSaga",           null,                               "Juegos",       "appx",        "safe",    100),
        new("Farm Heroes Saga",          "king.com.FarmHeroesSaga",               null,                               "Juegos",       "appx",        "safe",    90),
        new("Bubble Witch 3 Saga",       "king.com.BubbleWitch3Saga",             null,                               "Juegos",       "appx",        "safe",    85),
        new("Microsoft Solitaire",       "Microsoft.MicrosoftSolitaireCollection",null,                               "Juegos",       "appx",        "safe",    95),
        new("Xbox Game Bar",             "Microsoft.XboxGamingOverlay",           null,                               "Juegos",       "appx",        "caution", 50),
        new("Xbox App",                  "Microsoft.GamingApp",                   null,                               "Juegos",       "appx",        "caution", 150),
        new("Xbox Identity Provider",    "Microsoft.XboxIdentityProvider",        null,                               "Juegos",       "appx",        "caution", 20),
        new("Xbox TCUI",                 "Microsoft.Xbox.TCUI",                   null,                               "Juegos",       "appx",        "caution", 15),
        new("Xbox Speech To Text",       "Microsoft.XboxSpeechToTextOverlay",     null,                               "Juegos",       "appx",        "safe",    10),

        // COMUNICACION / REDES SOCIALES
        new("Skype",                     "Microsoft.SkypeApp",                    "Microsoft.Skype",                  "Comunicacion", "appx+winget", "safe",    180),
        new("Microsoft Teams (personal)","MicrosoftTeams",                        "Microsoft.Teams",                  "Comunicacion", "appx+winget", "caution", 350),
        new("WhatsApp",                  "5319275A.WhatsAppDesktop",              null,                               "Comunicacion", "appx",        "safe",    200),
        new("Facebook",                  "Facebook.Facebook",                     null,                               "Comunicacion", "appx",        "safe",    90),
        new("Instagram",                 "Facebook.Instagram",                    null,                               "Comunicacion", "appx",        "safe",    80),
        new("Twitter / X",               "Twitter.Twitter",                       null,                               "Comunicacion", "appx",        "safe",    70),
        new("TikTok",                    "BytedancePte.Ltd.TikTok",               null,                               "Comunicacion", "appx",        "safe",    150),
        new("Spotify (preinstalado)",    "SpotifyAB.SpotifyMusic",                null,                               "Comunicacion", "appx",        "safe",    130),

        // TELEMETRIA / DIAGNOSTICO
        new("Bing Search (barra tareas)","Microsoft.BingSearch",                  null,                               "Telemetria",   "appx",        "safe",    15),
        new("Bing News",                 "Microsoft.BingNews",                    null,                               "Telemetria",   "appx",        "safe",    40),
        new("Bing Weather",              "Microsoft.BingWeather",                 null,                               "Telemetria",   "appx",        "safe",    35),
        new("Bing Finance",              "Microsoft.BingFinance",                 null,                               "Telemetria",   "appx",        "safe",    30),
        new("Bing Sports",               "Microsoft.BingSports",                  null,                               "Telemetria",   "appx",        "safe",    30),
        new("Microsoft Advertising SDK", "Microsoft.Advertising.Xaml",            null,                               "Telemetria",   "appx",        "safe",    20),
        new("Feedback Hub",              "Microsoft.WindowsFeedbackHub",          null,                               "Telemetria",   "appx",        "safe",    25),
        new("Get Help",                  "Microsoft.GetHelp",                     null,                               "Telemetria",   "appx",        "safe",    20),
        new("Microsoft Tips",            "Microsoft.Getstarted",                  null,                               "Telemetria",   "appx",        "safe",    15),
        new("Mixed Reality Portal",      "Microsoft.MixedReality.Portal",         null,                               "Telemetria",   "appx",        "safe",    200),
        new("3D Viewer",                 "Microsoft.Microsoft3DViewer",           null,                               "Telemetria",   "appx",        "safe",    45),
        new("Paint 3D",                  "Microsoft.MSPaint",                     null,                               "Telemetria",   "appx",        "safe",    55),
        new("Microsoft To Do",           "Microsoft.Todos",                       null,                               "Telemetria",   "appx",        "safe",    60),
        new("Clipchamp",                 "Clipchamp.Clipchamp",                   null,                               "Telemetria",   "appx",        "safe",    80),
        new("Power Automate",            "Microsoft.PowerAutomateDesktop",        null,                               "Telemetria",   "appx",        "safe",    300),

        // OEM / FABRICANTE
        new("HP Support Assistant",      null,                                    "HP.HPSupportAssistant",            "OEM",          "winget",      "safe",    400),
        new("HP Sure Connect",           null,                                    "HP.HPSureConnect",                 "OEM",          "winget",      "safe",    60),
        new("Dell SupportAssist",        null,                                    "Dell.DellSupportAssistforPCs",     "OEM",          "winget",      "safe",    500),
        new("Dell Digital Delivery",     null,                                    "Dell.DellDigitalDelivery",         "OEM",          "winget",      "safe",    80),
        new("Lenovo Vantage",            null,                                    "Lenovo.LenovoVantage",             "OEM",          "winget",      "safe",    250),
        new("Lenovo Smart Noise Cancel", "E046963F.LenovoCompanion",              null,                               "OEM",          "appx",        "safe",    120),
        new("ASUS Armoury Crate",        null,                                    "ASUS.ArmouryCrate",                "OEM",          "winget",      "safe",    350),
        new("Acer Care Center",          null,                                    "Acer.AcerCareCenter",              "OEM",          "winget",      "safe",    200),
        new("McAfee (trial)",            null,                                    "McAfee.McAfeeSecurity",            "OEM",          "winget",      "safe",    600),
        new("Norton (trial)",            null,                                    "NortonLifeLock.NortonSecurity",    "OEM",          "winget",      "safe",    550),

        // UTILIDADES INNECESARIAS
        new("Microsoft Sway",            "Microsoft.Office.Sway",                 null,                               "Utilidades",   "appx",        "safe",    30),
        new("OneNote (preinstalado)",    "Microsoft.Office.OneNote",              null,                               "Utilidades",   "appx",        "safe",    120),
        new("People",                    "Microsoft.People",                      null,                               "Utilidades",   "appx",        "safe",    25),
        new("Maps",                      "Microsoft.WindowsMaps",                 null,                               "Utilidades",   "appx",        "safe",    80),
        new("Groove Music",              "Microsoft.ZuneMusic",                   null,                               "Utilidades",   "appx",        "safe",    75),
        new("Movies & TV",               "Microsoft.ZuneVideo",                   null,                               "Utilidades",   "appx",        "safe",    65),
        new("Money",                     "Microsoft.BingFinance",                 null,                               "Utilidades",   "appx",        "safe",    30),
        new("Microsoft Print to PDF",    "Microsoft.Print.to.PDF",                null,                               "Utilidades",   "appx",        "caution", 5),
        new("Your Phone / Phone Link",   "Microsoft.YourPhone",                   null,                               "Utilidades",   "appx",        "safe",    90),
        new("Microsoft Family Safety",   "MicrosoftCorporationII.MicrosoftFamily",null,                               "Utilidades",   "appx",        "safe",    40),
        new("Quick Assist",              "MicrosoftCorporationII.QuickAssist",    null,                               "Utilidades",   "appx",        "caution", 15),
    ];

    // ── Deteccion ─────────────────────────────────────────────────────────────

    // Mirror de Get-BloatwareList del PS1 (modulo 4A).
    // Cruza la DB con los paquetes instalados y devuelve solo los presentes.
    public async Task<IReadOnlyList<DetectedApp>> GetBloatwareListAsync()
    {
        return await Task.Run(() =>
        {
            var appxMap   = GetInstalledAppxMap();
            bool wingetOk = IsWingetAvailable();
            var wingetMap = wingetOk ? GetWingetInstalledMap() : [];

            var result = new List<DetectedApp>();

            foreach (var entry in _db)
            {
                bool    found     = false;
                string? packageFN = null;

                // Busqueda AppX
                if (entry.PackageId != null &&
                    (entry.Method == "appx" || entry.Method == "appx+winget"))
                {
                    string needle = entry.PackageId.ToLowerInvariant();
                    foreach (var key in appxMap.Keys)
                    {
                        if (key.Contains(needle) || needle.Contains(key))
                        {
                            found     = true;
                            packageFN = appxMap[key];
                            break;
                        }
                    }
                }

                // Busqueda Winget (solo si no se encontro via AppX)
                if (!found && entry.WingetId != null && wingetOk &&
                    (entry.Method == "winget" || entry.Method == "appx+winget"))
                {
                    string needle = entry.WingetId.ToLowerInvariant();
                    foreach (var key in wingetMap.Keys)
                    {
                        if (key.Contains(needle) || needle.Contains(key))
                        {
                            found = true;
                            break;
                        }
                    }
                }

                if (found)
                    result.Add(new DetectedApp(
                        entry.Name, entry.Category, entry.Method,
                        entry.Risk, entry.EstimateMB, packageFN, entry.WingetId));
            }

            return (IReadOnlyList<DetectedApp>)result
                .OrderBy(a => a.Category)
                .ThenBy(a => a.Name)
                .ToList();
        });
    }

    public BloatwareSummary GetSummary(IReadOnlyList<DetectedApp> list) =>
        new(list.Count,
            list.Sum(a => a.EstimateMB),
            list.Count(a => a.Risk == "safe"),
            list.Count(a => a.Risk == "caution"));

    public bool IsWingetAvailable() => IsWingetAvailableCore();

    // ── Eliminacion ───────────────────────────────────────────────────────────

    // Mirror de Remove-BloatItem del PS1 (modulo 4C).
    public async Task<RemoveResult> RemoveAppAsync(DetectedApp app, CancellationToken ct = default)
    {
        return await Task.Run(() =>
        {
            string msg = "";

            // Intentar via AppX primero
            if (app.PackageFN != null &&
                (app.Method == "appx" || app.Method == "appx+winget"))
            {
                try
                {
                    // Extraer el fragmento del nombre (antes del primer '_')
                    string fragment = app.PackageFN.Split('_')[0];
                    string psCmd =
                        $"Get-AppxPackage -Name '*{fragment}*' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction Stop; " +
                        $"Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | " +
                        $"Where-Object {{$_.PackageName -like '*{fragment}*'}} | " +
                        $"Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue";

                    int exit = RunPowerShell(psCmd, 60_000);
                    if (exit == 0)
                        return new RemoveResult(app.Name, true, "appx", "Eliminado via AppX");

                    msg = $"AppX ExitCode={exit}";
                }
                catch (Exception ex)
                {
                    msg = $"AppX error: {ex.Message}";
                }
            }

            // Intentar via winget
            if (app.WingetId != null &&
                (app.Method == "winget" || app.Method == "appx+winget"))
            {
                if (!IsWingetAvailableCore())
                    return new RemoveResult(app.Name, false, app.Method, "winget no disponible");

                try
                {
                    using var p = new Process
                    {
                        StartInfo = new ProcessStartInfo("winget",
                            $"uninstall --id \"{app.WingetId}\" --silent --accept-source-agreements --disable-interactivity")
                        {
                            UseShellExecute        = false,
                            CreateNoWindow         = true,
                            RedirectStandardOutput = true,
                            RedirectStandardError  = true,
                        }
                    };
                    p.Start();
                    bool done = p.WaitForExit(60_000);
                    int  exit = done ? p.ExitCode : -1;

                    if (exit == 0)
                        return new RemoveResult(app.Name, true, "winget", "Eliminado via winget");

                    string wingetMsg = done ? $"winget ExitCode={exit}" : "winget timeout";
                    if (!string.IsNullOrEmpty(msg)) msg += "; ";
                    msg += wingetMsg;
                }
                catch (Exception ex)
                {
                    if (!string.IsNullOrEmpty(msg)) msg += "; ";
                    msg += $"winget error: {ex.Message}";
                }
            }

            return new RemoveResult(app.Name, false, app.Method,
                string.IsNullOrEmpty(msg) ? "Metodo no reconocido" : msg);
        }, ct);
    }

    // Guarda lista de apps que se van a eliminar como referencia en el backup.
    // Mirror de Save-BloatBackup del PS1.
    public void SaveBloatBackup(string sessionPath, IEnumerable<DetectedApp> apps)
    {
        try
        {
            var snapshot = apps.Select(a => new
            {
                a.Name, a.Category, a.Method, a.PackageFN, a.WingetId,
                RemovedAt = DateTime.Now.ToString("HH:mm:ss"),
            });
            string json    = JsonSerializer.Serialize(snapshot,
                new JsonSerializerOptions { WriteIndented = true });
            string outFile = Path.Combine(sessionPath, "bloatware_removed.json");
            File.WriteAllText(outFile, json);
        }
        catch { }
    }

    // ── Helpers privados ──────────────────────────────────────────────────────

    // Mirror de Get-InstalledAppxMap del PS1.
    // Devuelve mapa: PackageFamilyName.ToLower() -> PackageFamilyName (original)
    private static Dictionary<string, string> GetInstalledAppxMap()
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            // Obtener todos los paquetes (usuario actual + todos los usuarios)
            // @(...) es el operador de sub-expresion array: agrupa los dos cmdlets en
            // una sola coleccion. Con parentesis simples (...) PowerShell lo trata como
            // una unica expresion y el ';' interno es un error de sintaxis ("falta ')'"),
            // por lo que el mapa quedaba vacio y el bloatware se reportaba como "sistema limpio".
            string output = RunPowerShellCapture(
                "@(Get-AppxPackage; Get-AppxPackage -AllUsers) | " +
                "Select-Object -ExpandProperty PackageFamilyName -Unique",
                20_000);

            foreach (string line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                string name = line.Trim();
                if (string.IsNullOrEmpty(name)) continue;
                string key = name.ToLowerInvariant();
                if (!map.ContainsKey(key))
                    map[key] = name;
            }
        }
        catch { }
        return map;
    }

    // Mirror de Test-WingetAvailable del PS1.
    private static bool IsWingetAvailableCore()
    {
        try
        {
            using var p = new Process
            {
                StartInfo = new ProcessStartInfo("winget", "--version")
                {
                    UseShellExecute        = false,
                    CreateNoWindow         = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                }
            };
            p.Start();
            bool done = p.WaitForExit(5_000);
            return done && p.ExitCode == 0;
        }
        catch { return false; }
    }

    // Mirror de Get-WingetInstalledMap del PS1.
    // Devuelve mapa de IDs instalados: id.ToLower() -> raw line
    private static Dictionary<string, string> GetWingetInstalledMap()
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            string output = RunProcessCapture("winget",
                "list --accept-source-agreements", 10_000);

            foreach (string line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                // Buscar columna de ID: secuencia de 2+ espacios antes de un ID valido
                // (patron equivalente al regex del PS1: '\s{2,}([A-Za-z0-9][\w\.\-]+)\s{2,}')
                int idx = 0;
                while (idx < line.Length)
                {
                    // Buscar doble espacio
                    int sp = line.IndexOf("  ", idx, StringComparison.Ordinal);
                    if (sp < 0) break;
                    int start = sp + 2;
                    while (start < line.Length && line[start] == ' ') start++;
                    if (start >= line.Length) break;

                    // Leer token hasta el siguiente doble espacio o fin
                    int end = line.IndexOf("  ", start, StringComparison.Ordinal);
                    string token = end < 0
                        ? line[start..].Trim()
                        : line[start..end].Trim();

                    if (token.Length > 3 && char.IsLetterOrDigit(token[0]) &&
                        token.Any(c => c == '.'))
                    {
                        string key = token.ToLowerInvariant();
                        if (!map.ContainsKey(key))
                            map[key] = line.Trim();
                    }
                    idx = end < 0 ? line.Length : end + 2;
                }
            }
        }
        catch { }
        return map;
    }

    // Ejecuta PowerShell con -NoProfile -NonInteractive y devuelve exit code.
    private static int RunPowerShell(string command, int timeoutMs)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo("powershell",
                $"-NoProfile -NonInteractive -Command \"{command.Replace("\"", "\\\"")}\"")
            {
                UseShellExecute        = false,
                CreateNoWindow         = true,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
            }
        };
        p.Start();
        p.WaitForExit(timeoutMs);
        return p.ExitCode;
    }

    // Ejecuta PowerShell y captura stdout.
    private static string RunPowerShellCapture(string command, int timeoutMs)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo("powershell",
                $"-NoProfile -NonInteractive -Command \"{command.Replace("\"", "\\\"")}\"")
            {
                UseShellExecute        = false,
                CreateNoWindow         = true,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
            }
        };
        p.Start();
        string output = p.StandardOutput.ReadToEnd();
        p.WaitForExit(timeoutMs);
        return output;
    }

    // Ejecuta un proceso externo y captura stdout.
    private static string RunProcessCapture(string exe, string args, int timeoutMs)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo(exe, args)
            {
                UseShellExecute        = false,
                CreateNoWindow         = true,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
            }
        };
        p.Start();
        string output = p.StandardOutput.ReadToEnd();
        p.WaitForExit(timeoutMs);
        return output;
    }
}
