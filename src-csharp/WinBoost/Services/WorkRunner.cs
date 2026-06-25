namespace WinBoost.Services;

/// <summary>
/// Reemplaza el patron Start-Job + DispatcherTimer + Flush-UI del PS1.
///
/// Uso tipico (desde el hilo UI):
///   await App.Worker.RunAsync(async ct => {
///       App.Progress.Set(10, "Limpiando...");
///       await Task.Run(() => HeavyWork(), ct);
///       ct.ThrowIfCancellationRequested();
///       App.Progress.Set(50, "Tweaks...");
///       await Task.Run(() => MoreWork(), ct);
///   });
///
/// - La lambda arranca en el hilo UI (progress/log sin Dispatcher extra).
/// - Task.Run dentro de la lambda despacha el trabajo pesado fuera del hilo UI.
/// - Despues de cada await la ejecucion vuelve al hilo UI automaticamente.
/// </summary>
internal sealed class WorkRunner
{
    private CancellationTokenSource? _cts;

    internal bool IsRunning { get; private set; }

    /// <summary>
    /// Ejecuta <paramref name="work"/> y gestiona ciclo de vida del token de cancelacion.
    /// Retorna true = completado con exito, false = cancelado o excepcion.
    /// </summary>
    internal async Task<bool> RunAsync(
        Func<CancellationToken, Task> work,
        string? startMsg = null,
        string? doneMsg  = null)
    {
        if (IsRunning) return false;

        _cts = new CancellationTokenSource();
        IsRunning = true;

        if (startMsg is not null)
            App.Logger?.Log(startMsg, "head");

        bool success;
        try
        {
            await work(_cts.Token);
            success = true;
            if (doneMsg is not null)
                App.Logger?.Log(doneMsg, "ok");
        }
        catch (OperationCanceledException)
        {
            App.Logger?.Log("Operacion cancelada", "skip");
            App.Progress?.Set(0, "Cancelado");
            success = false;
        }
        catch (Exception ex)
        {
            App.Logger?.Log($"Error: {ex.Message}", "err");
            success = false;
        }
        finally
        {
            _cts.Dispose();
            _cts = null;
            IsRunning = false;
        }

        return success;
    }

    /// <summary>Cancela la operacion en curso (no-op si no hay ninguna).</summary>
    internal void Cancel() => _cts?.Cancel();
}
