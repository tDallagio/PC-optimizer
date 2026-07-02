using System.Diagnostics;
using System.Management;
using Microsoft.Win32;

namespace WinBoost.Services;

// Equivalente a los modulos 9A/9B/9C del PS1 (Game Focus Mode).
public sealed class GameFocusService
{
    // Lista de juegos conocidos (nombre de proceso sin .exe, minusculas).
    // Mirror exacto de $script:knownGames del PS1.
    private static readonly string[] KnownGames =
    [
        "csgo", "cs2", "valorant", "fortnite", "minecraft", "javaw",
        "steam", "epicgameslauncher", "leagueclient", "leagueclientux",
        "dota2", "overwatch", "overwatch2", "gta5", "gtav",
        "rocketleague", "apexlegends", "apex", "battlefield1", "bf4",
        "rainbow6", "r6", "pubg", "tslgame", "warzone",
        "modernwarfare", "eldenring", "cyberpunk2077", "witcher3",
        "destiny2", "hogwartslegacy", "baldursgate3", "bg3",
        "starfield", "fallout4", "skyrimse", "sekiro", "thunderstore",
    ];

    private const string ToastRegPath =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications";

    // Estado de focus mode (null = inactivo). Mirror de $script:gameFocusState.
    private FocusState? _state;

    public bool IsActive => _state is { Active: true };

    private sealed class FocusState
    {
        public bool                  Active;
        public required Process      Process;
        public ProcessPriorityClass? PreviousPriority;
        public int                   PreviousToast;
        public long                  PreviousAffinity = -1;
    }

    // ── Deteccion (modulo 9A) ─────────────────────────────────────────────────

    // Mirror de Test-FullscreenProcess: detecta si la ventana en primer plano
    // ocupa exactamente el area del monitor. Devuelve el Process o null.
    public static Process? GetFullscreenProcess()
    {
        try
        {
            IntPtr hwnd = NativeMethods.GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return null;

            // Excluir escritorio y shell
            if (hwnd == NativeMethods.GetDesktopWindow() ||
                hwnd == NativeMethods.GetShellWindow()) return null;

            if (!NativeMethods.GetWindowRect(hwnd, out var winRect)) return null;

            IntPtr hMon = NativeMethods.MonitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
            if (hMon == IntPtr.Zero) return null;

            var monInfo = new NativeMethods.MONITORINFO
            {
                cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.MONITORINFO>(),
            };
            if (!NativeMethods.GetMonitorInfo(hMon, ref monInfo)) return null;

            var mon = monInfo.rcMonitor;
            bool isFullscreen = winRect.Left   == mon.Left  &&
                                winRect.Top    == mon.Top   &&
                                winRect.Right  == mon.Right &&
                                winRect.Bottom == mon.Bottom;
            if (!isFullscreen) return null;

            NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0) return null;

            return Process.GetProcessById((int)pid);
        }
        catch { return null; }
    }

    // Mirror de Test-KnownGame: nombre del proceso contiene un juego conocido.
    public static bool IsKnownGame(Process? proc)
    {
        if (proc == null) return false;
        string name;
        try { name = proc.ProcessName.ToLowerInvariant(); }
        catch { return false; }
        return KnownGames.Any(g => name.Contains(g));
    }

    // ── Afinidad (modulo 9B, F2.20) ──────────────────────────────────────────

    // Mascara de nucleos fisicos (primeros N bits). -1 si no hay SMT/HT util.
    public static long GetPhysicalCoreMask()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT NumberOfCores, NumberOfLogicalProcessors FROM Win32_Processor");
            foreach (var mo in searcher.Get())
            {
                int physical = Convert.ToInt32(mo["NumberOfCores"]);
                int logical  = Convert.ToInt32(mo["NumberOfLogicalProcessors"]);
                if (logical <= physical || physical < 1) return -1;
                return (1L << physical) - 1;
            }
        }
        catch { }
        return -1;
    }

    // ── Apply / Restore (modulo 9B) ──────────────────────────────────────────

    // Mirror de Apply-GameFocusMode: eleva prioridad, suprime toasts, aplica
    // afinidad de CPU si el ajuste esta activo. Guarda el estado previo.
    public void Apply(Process proc)
    {
        if (proc == null) return;

        ProcessPriorityClass? prevPriority = null;
        try { prevPriority = proc.PriorityClass; } catch { }

        int prevToast = 1;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(ToastRegPath);
            if (key?.GetValue("ToastEnabled") is int v) prevToast = v;
        }
        catch { }

        _state = new FocusState
        {
            Active           = true,
            Process          = proc,
            PreviousPriority = prevPriority,
            PreviousToast    = prevToast,
            PreviousAffinity = -1,
        };

        // Elevar prioridad
        try { proc.PriorityClass = ProcessPriorityClass.High; } catch { }

        // Suprimir notificaciones toast
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(ToastRegPath, writable: true);
            key?.SetValue("ToastEnabled", 0, RegistryValueKind.DWord);
        }
        catch { }

        // Afinidad de CPU a nucleos fisicos (si el ajuste esta activado)
        if (App.Settings.Current.GameAffinityEnabled)
        {
            long mask = GetPhysicalCoreMask();
            if (mask > 0)
            {
                try
                {
                    _state.PreviousAffinity = proc.ProcessorAffinity.ToInt64();
                    proc.ProcessorAffinity  = (IntPtr)mask;
                    App.Logger?.Log(
                        $"Gaming Mode ON - {proc.ProcessName} (PID {proc.Id}) prioridad High, " +
                        $"notificaciones OFF, afinidad CPU fisica (mascara 0x{mask:X})", "ok");
                }
                catch
                {
                    App.Logger?.Log(
                        $"Gaming Mode ON - {proc.ProcessName} (PID {proc.Id}) prioridad High, " +
                        "notificaciones OFF (afinidad CPU no disponible)", "ok");
                }
            }
            else
            {
                App.Logger?.Log(
                    $"Gaming Mode ON - {proc.ProcessName} (PID {proc.Id}) prioridad High, " +
                    "notificaciones OFF (sin SMT/HT, afinidad sin cambio)", "ok");
            }
        }
        else
        {
            App.Logger?.Log(
                $"Gaming Mode ON - {proc.ProcessName} (PID {proc.Id}) prioridad High, " +
                "notificaciones OFF", "ok");
        }
    }

    // Mirror de Restore-GameFocusMode: restaura prioridad, toasts y afinidad.
    public void Restore()
    {
        if (_state is not { Active: true } state) return;

        // Restaurar prioridad (si sigue corriendo)
        try
        {
            if (!state.Process.HasExited && state.PreviousPriority is { } prio)
                state.Process.PriorityClass = prio;
        }
        catch { }

        // Restaurar notificaciones toast
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(ToastRegPath, writable: true);
            key?.SetValue("ToastEnabled", state.PreviousToast, RegistryValueKind.DWord);
        }
        catch { }

        // Restaurar afinidad si fue modificada
        if (state.PreviousAffinity >= 0)
        {
            try
            {
                if (!state.Process.HasExited)
                    state.Process.ProcessorAffinity = (IntPtr)state.PreviousAffinity;
            }
            catch { }
        }

        state.Active = false;
        App.Logger?.Log("Gaming Mode OFF - prioridad, notificaciones y afinidad CPU restauradas", "info");
    }

    // Devuelve true si el proceso en foco ya termino (para que el timer limpie
    // el badge sin restaurar). Mirror del chequeo HasExited del modulo 9C.
    public bool ActiveProcessExited()
    {
        if (_state is not { Active: true } state) return false;
        try { return state.Process.HasExited; }
        catch { return true; }
    }

    public void MarkInactive()
    {
        if (_state != null) _state.Active = false;
    }
}
