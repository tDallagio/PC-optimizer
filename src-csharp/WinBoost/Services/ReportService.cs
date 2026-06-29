using System.Diagnostics;
using System.Net;
using System.Text;

namespace WinBoost.Services;

// ── Models ────────────────────────────────────────────────────────────────────

// Estado necesario para construir el reporte HTML. El MainWindow lo arma a partir
// del estado en memoria (equivalente a las variables $script:* del PS1).
public record ReportData(
    SystemSnapshot?       Sys,
    string                SysDrive,
    int                   ScoreBefore,
    int                   ScoreAfter,
    StateSnapshot?        Before,
    StateSnapshot?        After,
    double                FreedMb,
    IReadOnlyList<string> Actions,
    string?               TechnicianName);

// ─────────────────────────────────────────────────────────────────────────────

// Equivalente al modulo 10 del PS1 (exportar reporte HTML).
public sealed class ReportService
{
    // Mirror de Build-HTMLReport: HTML standalone con CSS inline.
    public static string BuildHtml(ReportData d)
    {
        string Enc(string? s) => WebUtility.HtmlEncode(s ?? "");

        string version = App.Version;
        string rptDate = DateTime.Now.ToString("yyyy-MM-dd");
        string rptTs   = DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss");

        string cpu    = d.Sys != null ? Enc(d.Sys.CpuName) : "N/D";
        string gpu    = d.Sys != null ? Enc(d.Sys.GpuName) : "N/D";
        string ram    = d.Sys != null ? $"{d.Sys.TotalRamGb} GB" : "N/D";
        string ssd    = d.Sys != null ? (d.Sys.HasSsd ? "Si (SSD)" : "No (HDD)") : "N/D";
        string laptop = d.Sys != null ? (d.Sys.IsLaptop ? "Portatil" : "Escritorio") : "Escritorio";
        string drive  = d.SysDrive;

        // Score
        int    sb       = d.ScoreBefore;
        int    sa       = d.ScoreAfter;
        int    delta    = sa - sb;
        string sign     = delta > 0 ? "+" : "";
        string colorSA  = sa >= 75 ? "#22C55E" : sa >= 45 ? "#F59E0B" : "#EF4444";
        string deltaCol = delta > 0 ? "#22C55E" : delta < 0 ? "#EF4444" : "#888888";

        // Metricas medibles
        string bootB = d.Before is { BootTimeSec: >= 0 } ? $"{d.Before.BootTimeSec} s" : "N/D";
        string ramB  = d.Before != null ? $"{d.Before.RamFreeMb} MB" : "N/D";
        string ramA  = d.After  != null ? $"{d.After.RamFreeMb} MB"  : "N/D";
        string procB = d.Before != null ? $"{d.Before.ProcCount}" : "N/D";
        string procA = d.After  != null ? $"{d.After.ProcCount}"  : "N/D";

        string ramDeltaDisp = "N/D", ramColor = "#888888";
        if (d.Before != null && d.After != null)
        {
            int diff = d.After.RamFreeMb - d.Before.RamFreeMb;
            if (diff > 0)      { ramDeltaDisp = $"+{diff} MB"; ramColor = "#22C55E"; }
            else if (diff < 0) { ramDeltaDisp = $"{diff} MB";  ramColor = "#EF4444"; }
            else               { ramDeltaDisp = "sin cambio";  ramColor = "#888888"; }
        }

        string procDeltaDisp = "N/D", procColor = "#888888";
        if (d.Before != null && d.After != null)
        {
            int diff = d.After.ProcCount - d.Before.ProcCount;
            if (diff < 0)      { procDeltaDisp = $"{diff} proc";  procColor = "#22C55E"; }
            else if (diff > 0) { procDeltaDisp = $"+{diff} proc"; procColor = "#EF4444"; }
            else               { procDeltaDisp = "sin cambio";    procColor = "#888888"; }
        }

        // Sesion
        int freed = (int)Math.Round(d.FreedMb);
        int count = d.Actions.Count;

        // Lista de acciones
        var actionsSb = new StringBuilder();
        if (d.Actions.Count > 0)
            foreach (var a in d.Actions)
                actionsSb.Append($"        <li>{Enc(a)}</li>\n");
        else
            actionsSb.Append("        <li>Sin acciones registradas en esta sesion.</li>\n");

        // Fila de tecnico (solo si hay nombre)
        string techRow = "";
        if (!string.IsNullOrWhiteSpace(d.TechnicianName))
            techRow = $"  <div class=\"row\"><span class=\"lbl\">Tecnico</span>" +
                      $"<span class=\"val\" style=\"color:#00C8FF\">{Enc(d.TechnicianName)}</span></div>";

        return $$"""
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>WinBoost v{{version}} - Reporte {{rptDate}}</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',sans-serif;background:#0D0D0D;color:#CCCCCC;padding:28px;max-width:860px;margin:0 auto}
.hdr{background:#161616;border:1px solid #2A2A2A;border-radius:8px;padding:20px 24px;margin-bottom:14px;display:flex;justify-content:space-between;align-items:center}
.hdr-t{font-size:20px;font-weight:600;color:#EEEEEE}.hdr-t span{color:#00C8FF}
.hdr-m{font-size:11px;color:#555555;text-align:right;line-height:1.6}
.sec{background:#161616;border:1px solid #2A2A2A;border-radius:8px;padding:18px 22px;margin-bottom:14px}
.sec-hd{font-size:10px;font-weight:600;color:#555555;letter-spacing:1px;text-transform:uppercase;margin-bottom:12px}
.row{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #1E1E1E}
.row:last-child{border-bottom:none}
.lbl{color:#555555;font-size:13px}.val{color:#CCCCCC;font-size:13px;font-weight:500}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.card{background:#111111;border-radius:6px;padding:14px;text-align:center}
.cv{font-size:26px;font-weight:700;color:#00C8FF}
.cl{font-size:11px;color:#555555;margin-top:4px}
ul.al{list-style:none;padding:0}
ul.al li{padding:5px 0;border-bottom:1px solid #1E1E1E;font-size:13px}
ul.al li:last-child{border-bottom:none}
ul.al li::before{content:"\25B8  ";color:#00C8FF}
.ft{text-align:center;font-size:11px;color:#3A3A3A;margin-top:10px}
</style>
</head>
<body>

<div class="hdr">
  <div class="hdr-t">WinBoost <span>v{{version}}</span> &mdash; Reporte</div>
  <div class="hdr-m">{{rptTs}}<br/>{{laptop}} &bull; {{drive}}</div>
</div>

<!-- RESULTADOS MEDIBLES -->
<div style="background:#0D1A0D;border:1px solid #1E3A1E;border-radius:10px;padding:22px 24px;margin-bottom:14px">
  <div style="font-size:10px;font-weight:600;color:#22C55E;letter-spacing:1.5px;text-transform:uppercase;margin-bottom:16px">Resultados medibles</div>
  <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:12px">

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">Score de salud</div>
      <div style="display:flex;justify-content:center;align-items:center;gap:8px;margin-bottom:8px">
        <div>
          <div style="font-size:26px;font-weight:700;color:#666666">{{sb}}</div>
          <div style="font-size:9px;color:#444444;margin-top:2px">ANTES</div>
        </div>
        <div style="font-size:14px;color:#3A3A3A">&#x2192;</div>
        <div>
          <div style="font-size:26px;font-weight:700;color:{{colorSA}}">{{sa}}</div>
          <div style="font-size:9px;color:#444444;margin-top:2px">AHORA</div>
        </div>
      </div>
      <div style="font-size:22px;font-weight:700;color:{{deltaCol}}">{{sign}}{{delta}} pts</div>
    </div>

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">RAM disponible</div>
      <div style="font-size:12px;color:#555555;margin-bottom:10px">{{ramB}} &rarr; <span style="color:#CCCCCC">{{ramA}}</span></div>
      <div style="font-size:26px;font-weight:700;color:{{ramColor}}">{{ramDeltaDisp}}</div>
    </div>

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">Procesos activos</div>
      <div style="font-size:12px;color:#555555;margin-bottom:10px">{{procB}} &rarr; <span style="color:#CCCCCC">{{procA}}</span></div>
      <div style="font-size:26px;font-weight:700;color:{{procColor}}">{{procDeltaDisp}}</div>
    </div>

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">Tiempo de arranque</div>
      <div style="font-size:24px;font-weight:700;color:#CCCCCC;margin-bottom:10px">{{bootB}}</div>
      <div style="font-size:10px;color:#444444;font-style:italic">reiniciar para ver mejora</div>
    </div>

  </div>
</div>

<div class="sec">
  <div class="sec-hd">Informacion del sistema</div>
{{techRow}}
  <div class="row"><span class="lbl">CPU</span><span class="val">{{cpu}}</span></div>
  <div class="row"><span class="lbl">GPU</span><span class="val">{{gpu}}</span></div>
  <div class="row"><span class="lbl">RAM total</span><span class="val">{{ram}}</span></div>
  <div class="row"><span class="lbl">Almacenamiento</span><span class="val">{{ssd}}</span></div>
</div>

<div class="sec">
  <div class="sec-hd">Resumen de sesion</div>
  <div class="cards">
    <div class="card"><div class="cv">{{freed}}</div><div class="cl">MB liberados</div></div>
    <div class="card"><div class="cv">{{count}}</div><div class="cl">Acciones aplicadas</div></div>
    <div class="card"><div class="cv">{{sign}}{{delta}}</div><div class="cl">Pts de mejora</div></div>
  </div>
</div>

<div class="sec">
  <div class="sec-hd">Acciones aplicadas</div>
  <ul class="al">
{{actionsSb.ToString()}}  </ul>
</div>

<div class="ft">Generado por WinBoost v{{version}} &mdash; {{rptTs}}</div>
</body>
</html>
""";
    }

    // Mirror de Export-HTMLReport: guarda en Documentos y abre en el navegador.
    // Devuelve la ruta del archivo, o null si fallo.
    public async Task<string?> ExportAsync(ReportData data)
    {
        try
        {
            string html    = await Task.Run(() => BuildHtml(data));
            string date    = DateTime.Now.ToString("yyyy-MM-dd");
            string docs    = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            string outPath = Path.Combine(docs, $"OptimizarPC_Reporte_{date}.html");
            await File.WriteAllTextAsync(outPath, html, new UTF8Encoding(false));
            Process.Start(new ProcessStartInfo(outPath) { UseShellExecute = true });
            return outPath;
        }
        catch
        {
            return null;
        }
    }
}
