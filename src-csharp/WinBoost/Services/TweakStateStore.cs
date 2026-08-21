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

    private Dictionary<string, TweakStateEntry> _entries = new(StringComparer.OrdinalIgnoreCase);
    private bool _loaded;

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
        EnsureLoaded();
        return _entries.ContainsKey(id);
    }

    // Guarda el valor original de un tweak (solo la PRIMERA vez que se aplica -- llamar
    // unicamente cuando !HasEntry(id)). El payload puede ser cualquier tipo serializable: cada
    // tweak elige la forma que tenga sentido para el (bool, dictionary por sub-item, texto crudo
    // de un comando, etc.) -- el store no le impone un shape fijo.
    public void SaveOriginal<T>(string id, T originalValue)
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

    public T? ReadOriginal<T>(string id)
    {
        EnsureLoaded();
        if (!_entries.TryGetValue(id, out var entry)) return default;
        try { return entry.Original.Deserialize<T>(); }
        catch { return default; }
    }

    // Flag informativo/diagnostico (ver nota de clase): no toca el valor Original guardado.
    public void SetAppliedByWinBoost(string id, bool applied)
    {
        EnsureLoaded();
        if (!_entries.TryGetValue(id, out var entry)) return;
        entry.AppliedByWinBoost = applied;
        Persist();
    }

    public void Remove(string id)
    {
        EnsureLoaded();
        if (_entries.Remove(id)) Persist();
    }
}
