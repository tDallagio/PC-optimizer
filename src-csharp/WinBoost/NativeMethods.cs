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

    // ── user32 ────────────────────────────────────────────────────────────────

    // Fix 43: escribir MouseSpeed/MouseThreshold1/MouseThreshold2 directo al registro (lo que
    // hacia el tweak MouseAccel) PERSISTE el valor pero no lo aplica en la sesion en curso --
    // Windows cachea estos 3 parametros a nivel de sesion y solo los relee via
    // SystemParametersInfo(SPI_SETMOUSE) o en el proximo logon. Confirmado en la maquina real: el
    // registro quedaba escrito en 0/0/0, pero el checkbox "Mejorar precision del puntero" de Panel
    // de Control nunca cambiaba, ni cerrando y reabriendo el dialogo. SPI_SETMOUSE es la MISMA API
    // que usa Panel de Control cuando el usuario toca el checkbox a mano -- toma un array de 3
    // ints [Threshold1, Threshold2, Speed] (ese orden, no el orden de los nombres de registro) y
    // SPIF_SENDCHANGE difunde WM_SETTINGCHANGE para que la sesion en curso lo tome ya mismo.
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

    internal static void SetMouseAcceleration(int threshold1, int threshold2, int speed)
    {
        const uint SPI_SETMOUSE       = 0x0004;
        const uint SPIF_UPDATEINIFILE = 0x01;
        const uint SPIF_SENDCHANGE    = 0x02;
        int[] mouseParams = [threshold1, threshold2, speed];
        SystemParametersInfo(SPI_SETMOUSE, 0, mouseParams, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
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
