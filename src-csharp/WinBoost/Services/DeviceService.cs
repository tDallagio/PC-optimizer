using System.Management;

namespace WinBoost.Services;

public sealed record ProblemDevice(
    string FriendlyName,
    string Status,          // "Error" | "Unknown" | "Degraded" | ...
    uint   ErrorCode);      // ConfigManagerErrorCode

public sealed class DeviceService
{
    // Mirror de Get-ProblemDevices del PS1 (módulo F1.7 / F1.8).
    // Usa Win32_PnPEntity: ConfigManagerErrorCode <> 0 equivale a Get-PnpDevice | Status -ne "OK".
    public Task<IReadOnlyList<ProblemDevice>> GetProblemDevicesAsync() =>
        Task.Run(GetProblemDevices);

    private static IReadOnlyList<ProblemDevice> GetProblemDevices()
    {
        var result = new List<ProblemDevice>();
        try
        {
            using var s = new ManagementObjectSearcher(
                "SELECT Name, Status, ConfigManagerErrorCode " +
                "FROM Win32_PnPEntity " +
                "WHERE ConfigManagerErrorCode <> 0");

            foreach (ManagementObject o in s.Get())
            {
                string name    = o["Name"]?.ToString()   ?? "(sin nombre)";
                string status  = o["Status"]?.ToString() ?? "Desconocido";
                uint   code    = o["ConfigManagerErrorCode"] is uint u ? u : 0u;
                result.Add(new ProblemDevice(name, status, code));
            }
        }
        catch { }

        return result.OrderBy(d => d.FriendlyName).ToList();
    }
}
