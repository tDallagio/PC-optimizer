using System.Diagnostics;
using System.Linq;
using System.Management;

namespace WinBoost.Services;

public enum DnsState { Automatico, Proveedor, Personalizado, SinAdaptadores }

public sealed record DnsStatus(DnsState State, string? ProviderName);

// Fase C, Paso 2 (48_fase_c_paso2_dns_dnsflush.txt): DNS no es un TweakDefinition -- es un
// selector de 4 proveedores fijos + un boton "Restaurar original" separado, no un toggle On/Off.
// El estado real tiene mas de 2 formas (automatico, uno de los 4 proveedores conocidos, o
// configuracion personalizada) -- forzar eso en TweakStatus.On/Off/NoAplicable mentiria sobre lo
// que realmente hay. Vive en su propio servicio chico, no en TweakRegistry.
//
// Reusa OptimizationService.DnsProviders (los mismos 4 -- agregar mas proveedores es un item de
// backlog aparte en PENDIENTES.md, fuera de alcance aca) y el MISMO filtro de adaptadores que ya
// usa OptimizationService.NetworkTweaks para el Apply real: "IPEnabled = True AND MACAddress IS
// NOT NULL" contra Win32_NetworkAdapterConfiguration.
//
// Tecnica de lectura/escritura: se basa en BackupService.SaveNetBackup()/RestoreNetworkFromSession
// (ya sabe leer/restaurar DNSServerSearchOrder por adaptador, incluyendo "vacio = automatico" ->
// null a SetDNSServerSearchOrder) pero SIN llamarlos directo -- ese guardado es session-scoped
// (ligado a una corrida del tab Optimizar clasico), mismo motivo de siempre para no reusarlo tal
// cual (ver SvcDiag, Tanda 2: el original tiene que vivir en TweakStateStore, disponible siempre).
// Ademas se simplifica el mecanismo: SaveNetBackup lee DNS via
// System.Net.NetworkInformation.NetworkInterface (una API) y RestoreNetworkFromSession despues
// busca el adaptador correspondiente por InterfaceIndex contra Win32_NetworkAdapterConfiguration
// (otra API) -- una correlacion cruzada entre dos fuentes distintas. Esta clase lee y escribe
// DNSServerSearchOrder e InterfaceIndex del MISMO objeto WMI de punta a punta, sin cruzar APIs. El
// binding de IPv6 que tambien toca SaveNetBackup/RestoreNetworkFromSession no aplica aca -- este
// tweak no lo toca.
internal static class DnsPresetService
{
    private const string StateId = "DNS";
    private const string AdapterQuery =
        "SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True AND MACAddress IS NOT NULL";

    internal static bool HasOriginalCaptured() => App.TweakState.HasEntry(StateId);

    internal static Task ApplyAsync(DnsProvider provider) => Task.Run(() =>
    {
        CaptureOriginalIfNeeded();

        using var searcher = new ManagementObjectSearcher(AdapterQuery);
        foreach (ManagementObject mo in searcher.Get())
        {
            try
            {
                var inParams = mo.GetMethodParameters("SetDNSServerSearchOrder");
                inParams["DNSServerSearchOrder"] = new string[] { provider.Primary, provider.Secondary };
                mo.InvokeMethod("SetDNSServerSearchOrder", inParams, new InvokeMethodOptions());
            }
            catch { }
            finally { mo.Dispose(); }
        }
        FlushDns();
    });

    // Restaura cada adaptador a SU PROPIO original -- no asume que todos estaban en el mismo
    // estado (uno pudo tener DNS manual antes de que WinBoost tocara nada, otro pudo estar en
    // automatico). Sin entrada en el store = WinBoost nunca aplico DNS desde este panel -- no-op
    // (mismo criterio que el resto del registro de tweaks).
    //
    // Adaptador SIN entrada en el original capturado (ej. una VPN que se conecto despues de
    // aplicar) se SALTEA, no se fuerza a automatico -- WinBoost nunca lo toco ni al aplicar ni
    // ahora, tocarlo igual seria cambiar algo que nunca estuvo bajo su control. Mismo criterio que
    // RevertNagleAsync (Tanda 1): revertir solo lo que esta en el original capturado, iterando lo
    // que hay HOY para no recrear/tocar de mas.
    internal static Task RestoreAsync() => Task.Run(() =>
    {
        if (!App.TweakState.HasEntry(StateId)) return;
        var original = App.TweakState.ReadOriginal<Dictionary<string, string[]?>>(StateId);
        if (original is null) return;

        using var searcher = new ManagementObjectSearcher(AdapterQuery);
        foreach (ManagementObject mo in searcher.Get())
        {
            try
            {
                string key = Convert.ToString(mo["InterfaceIndex"]) ?? "";
                if (!original.TryGetValue(key, out var dns)) continue;

                if (dns is { Length: > 0 })
                {
                    mo.InvokeMethod("SetDNSServerSearchOrder", new object[] { dns });
                }
                else
                {
                    // Original capturado vacio/null = estaba en automatico (DHCP). WMI requiere
                    // null, no un array vacio -- mismo criterio que RestoreNetworkFromSession.
#pragma warning disable CS8625
                    mo.InvokeMethod("SetDNSServerSearchOrder", new object[] { null });
#pragma warning restore CS8625
                }
            }
            catch { }
            finally { mo.Dispose(); }
        }
        FlushDns();
    });

    // Se lee en vivo SIEMPRE (nunca desde el store) -- el store solo guarda el ORIGINAL para poder
    // revertir, no es la fuente de verdad del estado actual (mismo principio que
    // UpdateTweakCardUi/LeerEstadoAsync en el resto del registro).
    internal static Task<DnsStatus> ReadStatusAsync() => Task.Run(() =>
    {
        var perAdapter = new List<string[]?>();
        using (var searcher = new ManagementObjectSearcher(AdapterQuery))
            foreach (ManagementObject mo in searcher.Get())
            {
                perAdapter.Add(mo["DNSServerSearchOrder"] as string[]);
                mo.Dispose();
            }

        // 0 adaptadores elegibles ahora mismo: sin este guard, .All() sobre una lista vacia da
        // true (vacuous truth) y reportaria "Automatico" sin que haya nada que afirmar -- mismo
        // bug ya identificado y evitado para Nagle (Tanda 1).
        if (perAdapter.Count == 0) return new DnsStatus(DnsState.SinAdaptadores, null);

        if (perAdapter.All(d => d is null or { Length: 0 }))
            return new DnsStatus(DnsState.Automatico, null);

        foreach (var prov in OptimizationService.DnsProviders)
            if (perAdapter.All(d => MatchesProvider(d, prov)))
                return new DnsStatus(DnsState.Proveedor, prov.Name);

        return new DnsStatus(DnsState.Personalizado, null);
    });

    private static bool MatchesProvider(string[]? dns, DnsProvider p) =>
        dns is { Length: 2 } && dns[0] == p.Primary && dns[1] == p.Secondary;

    private static void CaptureOriginalIfNeeded()
    {
        if (App.TweakState.HasEntry(StateId)) return;

        var original = new Dictionary<string, string[]?>();
        using var searcher = new ManagementObjectSearcher(AdapterQuery);
        foreach (ManagementObject mo in searcher.Get())
        {
            string key = Convert.ToString(mo["InterfaceIndex"]) ?? "";
            original[key] = mo["DNSServerSearchOrder"] as string[];
            mo.Dispose();
        }
        App.TweakState.SaveOriginal(StateId, original);
    }

    // Mismo criterio que RestoreNetworkFromSession ("Flush DNS siempre al restaurar red"): sin
    // esto, resoluciones ya cacheadas contra el servidor VIEJO seguirian devolviendo esas mismas
    // respuestas hasta que expiren solas, y el cambio se sentiria como que "no hizo nada" aunque
    // el adaptador ya este apuntando al servidor nuevo. Best-effort, no bloquea el resultado de
    // Aplicar/Restaurar si falla.
    private static void FlushDns()
    {
        try
        {
            using var proc = Process.Start(new ProcessStartInfo("ipconfig", "/flushdns")
            {
                UseShellExecute = false,
                CreateNoWindow  = true,
            });
            proc?.WaitForExit(10_000);
        }
        catch { }
    }
}
