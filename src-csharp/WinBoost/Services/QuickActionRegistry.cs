using System.Diagnostics;
using System.Linq;
using System.Management;

namespace WinBoost.Services;

// Fase C, Paso 2 (48_fase_c_paso2_dns_dnsflush.txt): modelo para acciones de un solo click SIN
// estado -- DNSFlush (primer caso real) no encaja en TweakDefinition: no hay nada que
// LeerEstadoAsync pueda leer (la accion no queda "aplicada" de forma persistente, no existe un
// concepto de On/Off/NoAplicable), y por lo tanto tampoco pasa por TweakStateStore. Completamente
// separado de TweakDefinition/TweakRegistry a proposito -- forzarlo en ese molde habria sido
// artificial.
//
// Diseñado para reusarse mas alla de DNSFlush (decision de Tomy, no un caso hipotetico): TRIM/
// Desfrag (va a Herramientas) y el punto de restauracion (va a Home) son el mismo patron -- nombre
// + descripcion + boton "Ejecutar" + resultado, nada que revertir ni que consultar despues. Mismo
// mecanismo All/Find que TweakRegistry, para que sea igual de facil de descubrir y de extender.
public sealed record QuickActionDefinition(
    string Id,
    string Nombre,
    string Descripcion,
    Func<Task<string>> EjecutarAsync);

public sealed class QuickActionRegistry
{
    public IReadOnlyList<QuickActionDefinition> All { get; }

    public QuickActionRegistry()
    {
        All =
        [
            new QuickActionDefinition(
                Id:            "DNSFlush",
                Nombre:        "Limpiar cache DNS",
                Descripcion:   "Vacia la cache de resoluciones DNS de Windows. Util despues de cambiar de proveedor DNS o si una pagina resuelve a una IP vieja.",
                EjecutarAsync: FlushDnsAsync),

            // Fase C, Paso 5 (50_fase_c_paso4_5_trim_herramientas_restore_home.txt): segundo caso
            // real del patron. Card en Home (no generada por BuildQuickActionCard -- ver
            // MainWindow.xaml, boton btnHomeRestorePoint + ShowToast).
            new QuickActionDefinition(
                Id:            "RestorePoint",
                Nombre:        "Crear punto de restauracion",
                Descripcion:   "Crea un punto de restauracion de Windows. El sistema operativo no deja crear mas de uno cada 24 horas.",
                EjecutarAsync: CreateRestorePointAsync),
        ];
    }

    public QuickActionDefinition? Find(string id) => All.FirstOrDefault(a => a.Id == id);

    // Sin RunProcess compartido que trague la excepcion (a proposito, a diferencia del RunProcess
    // privado de TweakRegistry/OptimizationService): una accion rapida existe justamente para que
    // el click reporte exito o error real -- si Process.Start fallara (ipconfig.exe ausente, caso
    // practicamente imposible en un Windows real pero no imposible), eso tiene que llegar como
    // excepcion real a quien llamo EjecutarAsync, no perderse en un catch silencioso que devuelva
    // igual un mensaje de "listo". No se inspecciona stdout (evita repetir el parseo de texto
    // localizado que ya se identifico como fragil en otros lugares del proyecto, ver
    // docs/PENDIENTES.md) -- "ipconfig /flushdns" no necesita permisos especiales y no falla en la
    // practica; exito = el proceso arranco y termino sin tirar excepcion.
    private static Task<string> FlushDnsAsync() => Task.Run(() =>
    {
        using var proc = Process.Start(new ProcessStartInfo("ipconfig", "/flushdns")
        {
            UseShellExecute = false,
            CreateNoWindow  = true,
        });
        proc?.WaitForExit(30_000);
        return "Cache DNS limpiada.";
    });

    // Fase C, Paso 5: Windows por politica default NO permite crear mas de UN punto de
    // restauracion cada 24 horas (SystemRestorePointCreationFrequency) -- OptimizationService.
    // CreateRestorePoint (reusada tal cual, sin tocar) llama a Checkpoint-Computer y loguea
    // "creado" si la llamada no tira excepcion, pero eso NO confirma que Windows haya creado un
    // punto nuevo de verdad: dentro de la ventana de 24hs, la llamada completa "con exito" sin
    // crear nada. Mismo tipo de trampa que MouseAccel ("sin error" no es "funciono de verdad") --
    // se verifica con evidencia real, comparando la lista de puntos de restauracion antes y
    // despues (Get-ComputerRestorePoint), no confiando en que la llamada no haya tirado excepcion.
    private static Task<string> CreateRestorePointAsync() => Task.Run(() =>
    {
        var before = GetRestorePointsSnapshot();

        string sysDrive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:") + @"\";
        new OptimizationService().CreateRestorePoint(sysDrive);

        var after = GetRestorePointsSnapshot();

        if (before is null || after is null)
            return "No se pudo confirmar si se creo un punto nuevo (no se pudo leer la lista de puntos de restauracion -- puede que la Proteccion del sistema este desactivada en este disco). Revisa manualmente con Get-ComputerRestorePoint.";

        if (after.Value.Count > before.Value.Count)
            return $"Punto de restauracion creado ({DateTime.Now:dd/MM/yyyy HH:mm}).";

        // Conteo identico antes y despues = no se creo nada nuevo de verdad, mas alla de que la
        // llamada no haya tirado excepcion. Si el ultimo punto ya capturado esta dentro de las
        // ultimas 24hs, es evidencia directa de que fue el limite de Windows (no una suposicion) --
        // si no, no se puede afirmar esa causa especifica.
        if (before.Value.Latest is { } last && DateTime.Now - last < TimeSpan.FromHours(24))
            return $"Windows no permite otro punto de restauracion todavia (limite de 1 cada 24 horas) -- el ultimo fue creado el {last:dd/MM/yyyy HH:mm}.";

        return "No se creo ningun punto de restauracion nuevo. No parece ser el limite de 24 horas -- revisa la Consola para el detalle (puede que la Proteccion del sistema este desactivada en este disco).";
    });

    // Snapshot real (conteo + fecha del mas reciente) de los puntos de restauracion existentes, via
    // el mismo mecanismo que ya usa el resto del proyecto para leer estado sin tocarlo (subproceso
    // powershell.exe, RedirectStandardOutput -- no un runspace embebido). CreationTime en formato
    // DMTF (el que devuelve WMI, fijo, NO localizado) parseado con ManagementDateTimeConverter, no
    // como texto libre -- mismo criterio anti-parseo-fragil que el resto del proyecto (ver
    // docs/PENDIENTES.md). null = no se pudo leer la lista (ej. sin permisos, o Get-ComputerRestorePoint
    // tiro excepcion) -- se distingue explicitamente de "0 puntos existentes" via try/catch +
    // 'ERROR' centinela en el propio script, no infiriendolo de un conteo en cero.
    private static (int Count, DateTime? Latest)? GetRestorePointsSnapshot()
    {
        try
        {
            using var proc = new Process
            {
                StartInfo = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -NonInteractive -Command " +
                    "\"try{$p=@(Get-ComputerRestorePoint -ErrorAction Stop);$p.Count;" +
                    "if($p.Count -gt 0){($p|Sort-Object CreationTime -Descending|Select-Object -First 1).CreationTime}else{'NONE'}" +
                    "}catch{'ERROR'}\"")
                {
                    UseShellExecute       = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow         = true,
                }
            };
            proc.Start();
            string[] lines = proc.StandardOutput.ReadToEnd()
                .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            proc.WaitForExit(15_000);

            if (lines.Length == 0 || !int.TryParse(lines[0], out int count)) return null;

            DateTime? latest = null;
            if (lines.Length > 1 && lines[1] != "NONE")
                try { latest = ManagementDateTimeConverter.ToDateTime(lines[1]); } catch { }

            return (count, latest);
        }
        catch { return null; }
    }
}
