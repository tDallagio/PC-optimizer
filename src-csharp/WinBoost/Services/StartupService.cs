using Microsoft.Win32;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────

// Item de arranque detectado (mirror del PSCustomObject de Load-StartupItems)
public sealed class StartupItem
{
    public required string Name     { get; init; }
    public required string Path     { get; init; }
    public required string Source   { get; init; }  // HKCU | HKLM | Startup | Startup All
    public          bool   Enabled  { get; set; }
    public required string ApprPath { get; init; }  // ruta de la clave StartupApproved
    public          string FileName { get; init; } = "";  // nombre de archivo (solo carpetas)
}

// ─────────────────────────────────────────────────────────────────────────────

// Equivalente al modulo "GESTOR DE ARRANQUE" del PS1.
public sealed class StartupService
{
    // Claves de aprobacion de arranque (Task Manager / Settings escriben aqui)
    private const string ApprHkcu   = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string ApprHklm   = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string ApprFolder = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder";

    private const string RunHkcu = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string RunHklm = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";

    // Mirror de Load-StartupItems del PS1. Corre en Task.Run.
    public Task<IReadOnlyList<StartupItem>> GetStartupItemsAsync() =>
        Task.Run(() =>
        {
            var items = new List<StartupItem>();

            // HKCU\Run
            LoadRunKey(items, Registry.CurrentUser, RunHkcu, "HKCU", Registry.CurrentUser, ApprHkcu);
            // HKLM\Run
            LoadRunKey(items, Registry.LocalMachine, RunHklm, "HKLM", Registry.CurrentUser, ApprHklm);

            // Carpeta Startup del usuario
            LoadStartupFolder(items,
                Environment.GetFolderPath(Environment.SpecialFolder.Startup),
                "Startup", checkApproval: true);

            // Carpeta Startup comun (todos los usuarios)
            LoadStartupFolder(items,
                Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup),
                "Startup All", checkApproval: false);

            return (IReadOnlyList<StartupItem>)items;
        });

    private static void LoadRunKey(
        List<StartupItem> items,
        RegistryKey runRoot, string runSub, string source,
        RegistryKey apprRoot, string apprSub)
    {
        try
        {
            using var run = runRoot.OpenSubKey(runSub);
            if (run is null) return;

            foreach (string name in run.GetValueNames())
            {
                if (string.IsNullOrEmpty(name)) continue;
                items.Add(new StartupItem
                {
                    Name     = name,
                    Path     = run.GetValue(name)?.ToString() ?? "",
                    Source   = source,
                    Enabled  = GetApprState(apprRoot, apprSub, name),
                    ApprPath = apprSub,
                    FileName = "",
                });
            }
        }
        catch { }
    }

    private static void LoadStartupFolder(
        List<StartupItem> items, string folder, string source, bool checkApproval)
    {
        if (string.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return;
        try
        {
            foreach (var file in Directory.EnumerateFiles(folder))
            {
                if (string.Equals(System.IO.Path.GetExtension(file), ".ini",
                        StringComparison.OrdinalIgnoreCase))
                    continue;

                string fname = System.IO.Path.GetFileName(file);
                items.Add(new StartupItem
                {
                    Name     = System.IO.Path.GetFileNameWithoutExtension(fname),
                    Path     = file,
                    Source   = source,
                    Enabled  = !checkApproval || GetApprState(Registry.CurrentUser, ApprFolder, fname),
                    ApprPath = ApprFolder,
                    FileName = fname,
                });
            }
        }
        catch { }
    }

    // Mirror de Get-ApprState del PS1.
    // El primer byte del valor binario: 0x03 / 0x08 = deshabilitado; resto = habilitado.
    // Ausencia del valor = habilitado (default).
    private static bool GetApprState(RegistryKey root, string apprSub, string name)
    {
        try
        {
            using var key = root.OpenSubKey(apprSub);
            if (key?.GetValue(name) is byte[] v && v.Length >= 1)
                return v[0] != 0x03 && v[0] != 0x08;
        }
        catch { }
        return true;
    }

    // Mirror de Toggle-StartupItem del PS1.
    // Escribe el valor binario de aprobacion: habilitado=0x02, deshabilitado=0x03.
    // Devuelve el nuevo estado (Enabled) tras togglear.
    public Task<bool> ToggleAsync(StartupItem item) =>
        Task.Run(() =>
        {
            bool newState = !item.Enabled;
            byte[] val    = newState
                ? [0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                : [0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

            // ApprPath siempre vive bajo HKCU en este modelo
            using var key = Registry.CurrentUser.CreateSubKey(item.ApprPath, writable: true)
                ?? throw new InvalidOperationException($"No se pudo abrir {item.ApprPath}");

            string keyName = item.FileName != "" ? item.FileName : item.Name;
            key.SetValue(keyName, val, RegistryValueKind.Binary);

            item.Enabled = newState;
            return newState;
        });
}
