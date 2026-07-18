using System.Globalization;
using System.Management;
using System.Security.Cryptography;
using System.Text;

namespace WinBoost.Services;

internal enum LicenseTier { Free, Pro, Tech }

internal sealed record LicenseStatus(bool IsActivated, string HardwareId, LicenseTier Tier);

// ============================================================
// MODULO 12A/12B - MOTOR DE HARDWARE ID, LICENCIA Y TRIAL
// Mirror de Get-HardwareID / Test-LicenseKey / Get-LicenseStatus /
// Test-TrialStatus del PS1. La clave privada la tiene solo el emisor.
// ============================================================
internal sealed class LicenseService
{
    // Clave publica RSA-2048 (rotada; la vieja quedo comprometida). La privada la tiene solo Gen-License.ps1.
    private const string PublicKeyXml =
        "<RSAKeyValue><Modulus>ym5T92ZERbOkuMA0o/Acyqf2BcrCYfxH1uF0n6LPtM65a9jaJ/yBC8JEaXSgs3Ie" +
        "A4IHThBK8nJf2IdfTpHmljOrgiMmQc8BZhgAu7K+UTGKJeHORTf2Rt3lBcee8c2gV7ev7LuCWrXWzqfh24Khgv7" +
        "69fGWZh/iYxJFl+HDZYf+YH/ZknAN2L20ZagKrfhOfnfRjn0hr1ZmwzHJ1gXVO2AgewYXfT5W5HaBlGsqrUdIZv" +
        "fqzVqs3LIdJNBahU7/QKgOxhb/cWN35rdIPH9fj0dXt8iT/XbkNBeg1VcHMIyhW4SXL3vSMB4VVfDCSdUwMNYS0" +
        "lgjXbVMgiDC5jcpPQ==" +
        "</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>";

    private static readonly string LicensePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "license.key");

    private static readonly string TechLicensePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "tech_license.key");

    // Estado en memoria (reemplaza $script:IS_PRO / IS_TECH / IS_TRIAL / TRIAL_DAYS_LEFT)
    internal bool IsPro         { get; private set; }
    internal bool IsTech        { get; private set; }
    internal bool IsTrial       { get; private set; }
    internal int  TrialDaysLeft { get; private set; }

    private string? _cachedHwid;

    // ── Hardware ID ───────────────────────────────────────────────────────────
    // Mirror de Get-HardwareID: ProcessorId + BIOS SerialNumber, SHA256, 16 hex upper.
    internal string GetHardwareId()
    {
        if (_cachedHwid != null) return _cachedHwid;

        string procId = "", biosSerial = "";
        try { procId     = QueryFirst("Win32_Processor", "ProcessorId"); } catch { }
        try { biosSerial = QueryFirst("Win32_BIOS", "SerialNumber");     } catch { }

        string raw = (procId + biosSerial).Trim();
        if (raw.Length < 4)
        {
            try
            {
                string osSerial = QueryFirst("Win32_OperatingSystem", "SerialNumber");
                raw = Environment.MachineName + osSerial;
            }
            catch { }
        }

        using var sha = SHA256.Create();
        var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(raw));
        _cachedHwid = Convert.ToHexString(hash)[..16].ToUpperInvariant();
        return _cachedHwid;
    }

    private static string QueryFirst(string cls, string prop)
    {
        using var searcher = new ManagementObjectSearcher($"SELECT {prop} FROM {cls}");
        foreach (ManagementObject mo in searcher.Get())
            return mo[prop]?.ToString() ?? "";
        return "";
    }

    // ── Verificacion de firma RSA-2048/SHA256 ─────────────────────────────────
    private static bool TestSignature(string message, string signatureBase64)
    {
        try
        {
            using var rsa = new RSACryptoServiceProvider();
            rsa.FromXmlString(PublicKeyXml);
            using var sha = SHA256.Create();
            var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(message));
            var sig  = Convert.FromBase64String(signatureBase64);
            return rsa.VerifyHash(hash, "SHA256", sig);
        }
        catch { return false; }
    }

    // Mirror de Test-LicenseKey: firma sobre "WINBOOST-PRO-<HWID>" (hardware-bound).
    internal bool TestLicenseKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key)) return false;
        try { Convert.FromBase64String(key); } catch { return false; }
        try { return TestSignature($"WINBOOST-PRO-{GetHardwareId()}", key); }
        catch { return false; }
    }

    // Mirror de Test-TechLicenseKey: TECH-<Base64>, firma sobre "WINBOOST-TECH" (multi-PC).
    internal bool TestTechLicenseKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key)) return false;
        if (!key.StartsWith("TECH-", StringComparison.Ordinal)) return false;
        string sig = key[5..];
        try { Convert.FromBase64String(sig); } catch { return false; }
        try { return TestSignature("WINBOOST-TECH", sig); } catch { return false; }
    }

    // Mirror de Get-LicenseStatus: lee tech_license.key (multi-PC) y license.key (Pro).
    internal LicenseStatus GetStatus()
    {
        string hwid = "";
        try { hwid = GetHardwareId(); } catch { }

        if (File.Exists(TechLicensePath))
        {
            try
            {
                string stored = File.ReadAllText(TechLicensePath).Trim();
                if (TestTechLicenseKey($"TECH-{stored}"))
                    return new LicenseStatus(true, hwid, LicenseTier.Tech);
            }
            catch { }
        }

        if (File.Exists(LicensePath))
        {
            try
            {
                string stored = File.ReadAllText(LicensePath).Trim();
                if (TestLicenseKey(stored))
                    return new LicenseStatus(true, hwid, LicenseTier.Pro);
            }
            catch { }
        }

        return new LicenseStatus(false, hwid, LicenseTier.Free);
    }

    // Setea IS_PRO / IS_TECH desde la licencia guardada (reemplaza el init del modulo 12B).
    internal void RefreshFromStored()
    {
        var status    = GetStatus();
        IsPro         = status.IsActivated;
        IsTech        = status.Tier == LicenseTier.Tech;
        IsTrial       = false;
        TrialDaysLeft = 0;
    }

    // ── Trial (F0.2) ──────────────────────────────────────────────────────────
    // Mirror de Test-TrialStatus: evalua el trial de 14 dias y ajusta el estado.
    // Persiste TrialStartDate / TrialExpired via App.Settings si cambia.
    internal void EvaluateTrial()
    {
        var settings = App.Settings.Current;

        var status = GetStatus();
        if (status.IsActivated)
        {
            IsPro         = true;
            IsTech        = status.Tier == LicenseTier.Tech;
            IsTrial       = false;
            TrialDaysLeft = 0;
            return;
        }

        var today = DateTime.Now;

        if (string.IsNullOrEmpty(settings.TrialStartDate))
        {
            settings.TrialStartDate = today.ToString("yyyy-MM-dd");
            settings.TrialExpired   = false;
            App.Settings.Save();
            IsPro = true; IsTrial = true; TrialDaysLeft = 14;
            return;
        }

        try
        {
            var start = DateTime.ParseExact(
                settings.TrialStartDate, "yyyy-MM-dd", CultureInfo.InvariantCulture);
            int elapsed  = (int)(today - start).TotalDays;
            int daysLeft = 14 - elapsed;

            if (elapsed > 14)
            {
                IsPro = false; IsTrial = false; TrialDaysLeft = 0;
                if (!settings.TrialExpired)
                {
                    settings.TrialExpired = true;
                    App.Settings.Save();
                }
            }
            else
            {
                IsPro = true; IsTrial = true; TrialDaysLeft = Math.Max(1, daysLeft);
            }
        }
        catch
        {
            settings.TrialStartDate = today.ToString("yyyy-MM-dd");
            settings.TrialExpired   = false;
            App.Settings.Save();
            IsPro = true; IsTrial = true; TrialDaysLeft = 14;
        }
    }

    // ── Activacion (modulo 12C) ───────────────────────────────────────────────
    // Mirror del btnActivateLicense: valida, persiste la clave y actualiza el estado.
    internal bool ActivatePro(string key)
    {
        if (!TestLicenseKey(key)) return false;
        Directory.CreateDirectory(Path.GetDirectoryName(LicensePath)!);
        File.WriteAllText(LicensePath, key);
        IsPro = true; IsTech = false; IsTrial = false; TrialDaysLeft = 0;
        return true;
    }

    internal bool ActivateTech(string key)
    {
        if (!TestTechLicenseKey(key)) return false;
        Directory.CreateDirectory(Path.GetDirectoryName(TechLicensePath)!);
        File.WriteAllText(TechLicensePath, key[5..]);
        IsPro = true; IsTech = true; IsTrial = false; TrialDaysLeft = 0;
        return true;
    }
}
