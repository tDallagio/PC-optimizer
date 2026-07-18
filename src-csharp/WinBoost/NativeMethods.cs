using System.Runtime.InteropServices;

namespace WinBoost;

internal static class NativeMethods
{
    // ── kernel32 ─────────────────────────────────────────────────────────────

    [DllImport("kernel32.dll")]
    internal static extern bool GetSystemTimes(
        out FILETIME lpIdleTime, out FILETIME lpKernelTime, out FILETIME lpUserTime);

    [DllImport("kernel32.dll")]
    internal static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    // ── psapi ─────────────────────────────────────────────────────────────────

    [DllImport("psapi.dll", SetLastError = true)]
    internal static extern bool EmptyWorkingSet(IntPtr hProcess);

    // ── ntdll ─────────────────────────────────────────────────────────────────

    [DllImport("ntdll.dll")]
    private static extern uint NtSetSystemInformation(int cls, IntPtr info, int len);

    // ── advapi32 ──────────────────────────────────────────────────────────────

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool LookupPrivilegeValue(string? system, string name, out LUID luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(
        IntPtr token, bool disableAll,
        ref TOKEN_PRIVILEGES newState, uint bufLen, IntPtr prev, IntPtr retLen);

    // ── shell32 ───────────────────────────────────────────────────────────────

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(IntPtr hwnd, string? pszRootPath, uint dwFlags);

    internal static void EmptyRecycleBin()
    {
        const uint SHERB_NOCONFIRMATION = 0x00000001;
        const uint SHERB_NOPROGRESSUI   = 0x00000002;
        const uint SHERB_NOSOUND        = 0x00000004;
        SHEmptyRecycleBin(IntPtr.Zero, null, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
    }

    // ── structs ───────────────────────────────────────────────────────────────

    [StructLayout(LayoutKind.Sequential)]
    internal struct FILETIME
    {
        public uint dwLowDateTime;
        public uint dwHighDateTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MEMORYSTATUSEX
    {
        public uint  dwLength, dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys;
        public ulong ullTotalPageFile, ullAvailPageFile;
        public ulong ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint Low; public int High; }

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES
    {
        public uint Count;
        public LUID Luid;
        public uint Attributes;
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    internal static readonly uint MemoryStatusExSize =
        (uint)Marshal.SizeOf<MEMORYSTATUSEX>();

    internal static long FileTimeToLong(FILETIME ft) =>
        ((long)ft.dwHighDateTime << 32) | ft.dwLowDateTime;

    internal static bool EnablePrivilege(string name)
    {
        IntPtr token = IntPtr.Zero;
        try
        {
            if (!OpenProcessToken(GetCurrentProcess(), 0x28u, out token)) return false;
            if (!LookupPrivilegeValue(null, name, out LUID luid)) return false;
            var tp = new TOKEN_PRIVILEGES { Count = 1u, Luid = luid, Attributes = 2u };
            AdjustTokenPrivileges(token, false, ref tp, 0u, IntPtr.Zero, IntPtr.Zero);
            return true;
        }
        finally
        {
            if (token != IntPtr.Zero) CloseHandle(token);
        }
    }

    internal static uint PurgeStandbyList()
    {
        IntPtr p = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(p, 4);
        uint r = NtSetSystemInformation(0x50, p, 4);
        Marshal.FreeHGlobal(p);
        return r;
    }
}
