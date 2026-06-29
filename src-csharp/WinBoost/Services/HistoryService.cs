using System.Globalization;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────

public record SessionHistoryEntry(
    string    Timestamp,
    DateTime? Date,
    string    Preset,
    int       FreedMb,
    int       ActionCount,
    int       ScoreBefore,
    int       ScoreAfter,
    int       ScoreImprovement,
    string    SessionPath);

public record HistoryStats(
    int       TotalSessions,
    int       TotalFreedMb,
    double    AvgImprovement,
    int       TotalImprovement,
    DateTime? FirstSession,
    int       DaysSince);

// ─────────────────────────────────────────────────────────────────────────────

// Equivalente al modulo 8A del PS1 (motor de historial enriquecido).
public sealed class HistoryService
{
    // Mirror de Get-SessionHistory: construye sobre GetBackupSessions agregando
    // campos calculados. Solo incluye sesiones con metadata. Orden descendente.
    public Task<IReadOnlyList<SessionHistoryEntry>> GetSessionHistoryAsync() =>
        Task.Run(() =>
        {
            var result = new List<SessionHistoryEntry>();

            foreach (var s in App.Backup.GetBackupSessions())
            {
                if (!s.HasMeta || s.Meta is not { } m) continue;

                DateTime? parsed = null;
                if (DateTime.TryParseExact(m.Timestamp, "yyyy-MM-dd HH:mm:ss",
                        CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt))
                    parsed = dt;
                else if (DateTime.TryParse(m.Timestamp, CultureInfo.InvariantCulture,
                        DateTimeStyles.None, out var dt2))
                    parsed = dt2;

                result.Add(new SessionHistoryEntry(
                    Timestamp:        m.Timestamp,
                    Date:             parsed,
                    Preset:           string.IsNullOrEmpty(m.Preset) ? "Manual" : m.Preset,
                    FreedMb:          m.FreedMb,
                    ActionCount:      m.ActionCount,
                    ScoreBefore:      m.ScoreBefore,
                    ScoreAfter:       m.ScoreAfter,
                    ScoreImprovement: m.ScoreAfter - m.ScoreBefore,
                    SessionPath:      s.Path));
            }

            return (IReadOnlyList<SessionHistoryEntry>)result;
        });

    // Mirror de Get-HistoryStats: estadisticas agregadas. null si no hay sesiones.
    public async Task<HistoryStats?> GetHistoryStatsAsync()
    {
        var history = await GetSessionHistoryAsync();
        if (history.Count == 0) return null;

        int totalMb  = history.Sum(h => h.FreedMb);
        int totalImp = history.Sum(h => h.ScoreImprovement);
        double avgImp = Math.Round((double)totalImp / history.Count, 1);

        // Primera sesion: ultimo elemento (lista ya descendente por fecha)
        DateTime? firstDate = history[^1].Date;
        int daysSince = firstDate is { } fd
            ? (int)(DateTime.Now - fd).TotalDays
            : 0;

        return new HistoryStats(history.Count, totalMb, avgImp, totalImp, firstDate, daysSince);
    }
}
