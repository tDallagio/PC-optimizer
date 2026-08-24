using System.Text.Json;

namespace WinBoost.Services;

// Piloto Fase A (38_fase_a_registro_tweaks_piloto.txt): persistencia del valor ORIGINAL real
// por tweak individual, separada a proposito de BackupService/BackupModels (sesion completa de
// Optimizar). Un tweak con toggle inmediato necesita guardar/restaurar su propio estado anterior
// sin depender de que exista una "sesion" de backup creada al correr todo el plan.
//
// IMPORTANTE: este store es solo el respaldo del valor original para poder revertir. NUNCA es la
// fuente de verdad de si un tweak esta ON u OFF -- eso siempre lo decide TweakDefinition.LeerEstadoAsync
// contra el sistema real (si el usuario revirtio algo por fuera de WinBoost, o restauro una sesion
// vieja desde Historial, el toggle tiene que reflejar la realidad, no lo que dice este JSON).
public sealed class TweakStateEntry
{
    public string      Id                { get; set; } = "";
    public JsonElement Original          { get; set; }
    public string      AppliedAt         { get; set; } = "";
    // Informativo/diagnostico unicamente (ver nota de clase) -- no se usa para decidir estado.
    public bool        AppliedByWinBoost { get; set; }
}

public sealed class TweakStateStore
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".OptimizarPC", "tweak_state.json");

    // Fix 41 (41_fix_revert_mouseaccel_cortana_notif.txt): TweakStateStore es un singleton
    // (App.TweakState) pero cada tweak corre su Aplicar/Revertir en su PROPIO hilo de fondo
    // (Task.Run, ver TweakRegistry.cs) -- nada impide que dos tweaks distintos escriban al mismo
    // tiempo si el usuario toca dos toggles en una ventana corta. _entries era un Dictionary
    // comun (NO es thread-safe para escritores concurrentes) y Persist() hacia
    // File.WriteAllText() sobre el MISMO archivo desde esos hilos sin ninguna coordinacion: dos
    // llamadas casi simultaneas a SaveOriginal (una por cada tweak) podian pisarse -- la que
    // terminaba de escribir el archivo ultimo ganaba con SU snapshot de _entries, que podia no
    // incluir todavia la entrada que el otro hilo acababa de agregar en memoria, perdiendola en
    // el disco sin ninguna excepcion visible (EnsureLoaded/Persist ya tragaban errores en un
    // catch{} silencioso). Esto explica el sintoma real encontrado: MouseAccel/Cortana/Notif
    // aplicaban bien (la escritura de registro es independiente de este store) pero su entrada en
    // tweak_state.json nunca llegaba a persistir, asi que el revert siempre encontraba
    // HasEntry(id)==false. Fix: un lock unico que serializa TODO acceso a _entries y al archivo
    // (carga, lectura, escritura), asi dos tweaks aplicados/revertidos en paralelo ya no compiten
    // por el mismo diccionario ni el mismo archivo.
    private readonly object _gate = new();
    private Dictionary<string, TweakStateEntry> _entries = new(StringComparer.OrdinalIgnoreCase);
    private bool _loaded;

    // Llamar SIEMPRE desde dentro de lock (_gate).
    private void EnsureLoaded()
    {
        if (_loaded) return;
        _loaded = true;
        try
        {
            if (!File.Exists(FilePath)) return;
            var loaded = JsonSerializer.Deserialize<Dictionary<string, TweakStateEntry>>(File.ReadAllText(FilePath));
            if (loaded is not null) _entries = new(loaded, StringComparer.OrdinalIgnoreCase);
        }
        catch { }
    }

    // Llamar SIEMPRE desde dentro de lock (_gate).
    private void Persist()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath,
                JsonSerializer.Serialize(_entries, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    public bool HasEntry(string id)
    {
        lock (_gate)
        {
            EnsureLoaded();
            return _entries.ContainsKey(id);
        }
    }

    // Guarda el valor original de un tweak (solo la PRIMERA vez que se aplica -- llamar
    // unicamente cuando !HasEntry(id)). El payload puede ser cualquier tipo serializable: cada
    // tweak elige la forma que tenga sentido para el (bool, dictionary por sub-item, texto crudo
    // de un comando, etc.) -- el store no le impone un shape fijo.
    public void SaveOriginal<T>(string id, T originalValue)
    {
        lock (_gate)
        {
            EnsureLoaded();
            _entries[id] = new TweakStateEntry
            {
                Id                = id,
                Original          = JsonSerializer.SerializeToElement(originalValue),
                AppliedAt         = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                AppliedByWinBoost = true
            };
            Persist();
        }
    }

    public T? ReadOriginal<T>(string id)
    {
        lock (_gate)
        {
            EnsureLoaded();
            if (!_entries.TryGetValue(id, out var entry)) return default;
            try { return entry.Original.Deserialize<T>(); }
            catch { return default; }
        }
    }

    // Flag informativo/diagnostico (ver nota de clase): no toca el valor Original guardado.
    public void SetAppliedByWinBoost(string id, bool applied)
    {
        lock (_gate)
        {
            EnsureLoaded();
            if (!_entries.TryGetValue(id, out var entry)) return;
            entry.AppliedByWinBoost = applied;
            Persist();
        }
    }

    public void Remove(string id)
    {
        lock (_gate)
        {
            EnsureLoaded();
            if (_entries.Remove(id)) Persist();
        }
    }
}
