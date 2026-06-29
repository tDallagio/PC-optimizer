using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace WinBoost.Services;

// Metadata de una version disponible (mirror de $script:updateMeta del PS1).
internal sealed record UpdateMeta(
    string Version, string Changelog, string ReleaseUrl, string DownloadUrl, string Sha256);

// ============================================================
// MODULO 14 - AUTO-UPDATER (Check / Download / Apply)
// Mirror de Check-ForUpdates / Start-UpdateDownload / Apply-Update
// del PS1. La UI del changelog vive en ChangelogDialog (5.2).
// ============================================================
internal sealed class UpdateService
{
    private const string CheckUrl =
        "https://raw.githubusercontent.com/tDallagio/PC-optimizer/main/version.json";

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("WinBoost-Updater");
        return c;
    }

    // Ultima version detectada por CheckAsync (null si no hay update).
    internal UpdateMeta? Latest { get; private set; }

    // DTO del version.json (campos en minuscula, match case-insensitive).
    private sealed class VersionDto
    {
        public string? Version     { get; set; }
        public string? ReleaseUrl  { get; set; }
        public string? DownloadUrl { get; set; }
        public string? Sha256      { get; set; }
        public string? Changelog   { get; set; }
    }

    // ── Check ─────────────────────────────────────────────────────────────────
    // Mirror de Check-ForUpdates: descarga version.json, compara con la version
    // local. Devuelve la meta si la remota es mayor, o null (sin conexion incluido).
    internal async Task<UpdateMeta?> CheckAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            string json = await Http.GetStringAsync(CheckUrl, cts.Token);

            var dto = JsonSerializer.Deserialize<VersionDto>(json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (dto?.Version is null) return null;

            if (!TryParseVersion(dto.Version, out var remote)) return null;
            if (!TryParseVersion(App.Version, out var local))  return null;
            if (remote <= local) { Latest = null; return null; }

            Latest = new UpdateMeta(
                Version:     dto.Version.Trim(),
                Changelog:   string.IsNullOrWhiteSpace(dto.Changelog)
                                ? "Sin detalles disponibles." : dto.Changelog.Trim(),
                ReleaseUrl:  dto.ReleaseUrl?.Trim()  ?? "",
                DownloadUrl: dto.DownloadUrl?.Trim() ?? "",
                Sha256:      (dto.Sha256 ?? "").Trim().ToUpperInvariant());
            return Latest;
        }
        catch
        {
            // Sin conexion o URL invalida: ignorar silenciosamente (igual que el PS1)
            return null;
        }
    }

    // Mirror del cast [version]($v -replace "[^0-9.]","") del PS1.
    private static bool TryParseVersion(string raw, out Version version)
    {
        version = new Version(0, 0);
        string cleaned = new string(raw.Where(ch => char.IsDigit(ch) || ch == '.').ToArray()).Trim('.');
        if (cleaned.Length == 0) return false;
        if (!cleaned.Contains('.')) cleaned += ".0";
        return Version.TryParse(cleaned, out version!);
    }

    // ── Download ──────────────────────────────────────────────────────────────
    // Mirror de Start-UpdateDownload: descarga el instalador a %TEMP%, reportando
    // progreso. Devuelve la ruta del archivo o null. No bloquea el hilo UI.
    internal async Task<string?> DownloadAsync(UpdateMeta meta, IProgress<int>? progress,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(meta.DownloadUrl)) return null;

        string tmpDir = Path.Combine(Path.GetTempPath(), "OptimizarPC_update");
        Directory.CreateDirectory(tmpDir);

        string fileName = Path.GetFileName(new Uri(meta.DownloadUrl).LocalPath);
        if (string.IsNullOrWhiteSpace(fileName)) fileName = "WinBoost_update.exe";
        string dest = Path.Combine(tmpDir, fileName);

        using var resp = await Http.GetAsync(meta.DownloadUrl,
            HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();

        long? total = resp.Content.Headers.ContentLength;
        await using var src = await resp.Content.ReadAsStreamAsync(ct);
        await using var dst = new FileStream(dest, FileMode.Create, FileAccess.Write, FileShare.None);

        var buffer = new byte[81920];
        long read  = 0;
        int  n;
        while ((n = await src.ReadAsync(buffer, ct)) > 0)
        {
            await dst.WriteAsync(buffer.AsMemory(0, n), ct);
            read += n;
            if (total is > 0)
                progress?.Report((int)(read * 100 / total.Value));
        }
        progress?.Report(100);
        return dest;
    }

    // ── Verificacion de integridad ────────────────────────────────────────────
    // Mirror de la comprobacion Get-FileHash SHA256 del PS1.
    internal static bool VerifySha256(string file, string expectedHash)
    {
        if (string.IsNullOrWhiteSpace(expectedHash)) return false;
        if (!File.Exists(file)) return false;
        try
        {
            using var sha = SHA256.Create();
            using var fs  = File.OpenRead(file);
            string actual = Convert.ToHexString(sha.ComputeHash(fs));
            return string.Equals(actual.Trim(), expectedHash.Trim(),
                StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    // True si corremos como .exe compilado (no bajo el host dotnet / debugger).
    internal static bool IsRunningAsExe()
    {
        string exe = Environment.ProcessPath ?? "";
        return exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            && !exe.Contains("dotnet", StringComparison.OrdinalIgnoreCase);
    }

    // ── Apply ─────────────────────────────────────────────────────────────────
    // Mirror de Apply-Update: lanza un helper PowerShell que espera el cierre del
    // proceso, corre el instalador en silencio y relanza la app. El instalador
    // hereda la elevacion del proceso actual (ya corre como admin). El caller
    // debe cerrar la ventana al recibir true. Devuelve false en modo desarrollo.
    internal bool ApplyUpdate(string installerFile)
    {
        string currentExe = Environment.ProcessPath ?? "";
        if (!IsRunningAsExe() || string.IsNullOrEmpty(currentExe)) return false;

        int procId     = Environment.ProcessId;
        string swapDir = Path.Combine(Path.GetTempPath(), "OptimizarPC_update");
        Directory.CreateDirectory(swapDir);
        string swapPs1 = Path.Combine(swapDir, "do_update.ps1");

        string srcEsc      = installerFile.Replace("'", "''");
        string relaunchEsc = currentExe.Replace("'", "''");

        var sb = new StringBuilder();
        sb.AppendLine($"$installer = '{srcEsc}'");
        sb.AppendLine($"$relaunch  = '{relaunchEsc}'");
        sb.AppendLine($"$procId_   = {procId}");
        sb.AppendLine("for ($i = 0; $i -lt 30; $i++) {");
        sb.AppendLine("    if (-not (Get-Process -Id $procId_ -ErrorAction SilentlyContinue)) { break }");
        sb.AppendLine("    Start-Sleep -Seconds 1");
        sb.AppendLine("}");
        sb.AppendLine("Start-Sleep -Seconds 1");
        sb.AppendLine("$ec = -1");
        sb.AppendLine("try {");
        sb.AppendLine("    $proc = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOCANCEL' -Wait -PassThru -ErrorAction Stop");
        sb.AppendLine("    $ec = $proc.ExitCode");
        sb.AppendLine("} catch {");
        sb.AppendLine("    Add-Type -AssemblyName System.Windows.Forms");
        sb.AppendLine("    [System.Windows.Forms.MessageBox]::Show('Error al ejecutar el instalador: ' + $_.Exception.Message, 'WinBoost Update', 'OK', 'Error') | Out-Null");
        sb.AppendLine("    exit 1");
        sb.AppendLine("}");
        sb.AppendLine("if ($ec -ne 0) {");
        sb.AppendLine("    Add-Type -AssemblyName System.Windows.Forms");
        sb.AppendLine("    [System.Windows.Forms.MessageBox]::Show('El instalador termino con codigo ' + $ec + '. Actualiza manualmente desde GitHub.', 'WinBoost Update', 'OK', 'Warning') | Out-Null");
        sb.AppendLine("    exit 1");
        sb.AppendLine("}");
        sb.AppendLine("Start-Sleep -Seconds 1");
        sb.AppendLine("if (Test-Path $relaunch) { Start-Process $relaunch }");

        File.WriteAllText(swapPs1, sb.ToString(), new UTF8Encoding(false));

        Process.Start(new ProcessStartInfo
        {
            FileName        = "powershell",
            Arguments       = $"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{swapPs1}\"",
            UseShellExecute = false,
            CreateNoWindow  = true,
        });
        return true;
    }
}
