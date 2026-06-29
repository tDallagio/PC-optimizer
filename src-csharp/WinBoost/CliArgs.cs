namespace WinBoost;

/// <summary>
/// Argumentos de linea de comandos soportados:
///   -Silent         Ejecuta la optimizacion sin mostrar ventana.
///   -Preset NAME    Preset a aplicar: Gaming | Prod | Safe (default: Safe)
///   -DNS INDEX      Proveedor DNS: 0=Cloudflare 1=Google 2=Quad9 3=AdGuard (default: 0)
///   -Help           Muestra esta ayuda y sale.
/// Prefijos aceptados: - | -- | /
/// </summary>
internal sealed record CliArgs(
    bool   Silent,
    string Preset,
    int    DnsIndex,
    bool   ShowHelp)
{
    internal static readonly string UsageText =
        "Uso: WinBoost.exe [-Silent] [-Preset Gaming|Prod|Safe] [-DNS 0-3]\n" +
        "\n" +
        "  -Silent      Optimiza sin mostrar ventana (requiere permisos de administrador)\n" +
        "  -Preset      Preset a aplicar: Gaming | Prod | Safe  (defecto: Safe)\n" +
        "  -DNS INDEX   Proveedor DNS: 0=Cloudflare 1=Google 2=Quad9 3=AdGuard\n" +
        "  -Help        Muestra esta ayuda\n" +
        "\n" +
        "Ejemplo:\n" +
        "  WinBoost.exe -Silent -Preset Gaming -DNS 0\n";

    internal static CliArgs Parse(string[] args)
    {
        bool   silent   = false;
        string preset   = "Safe";
        int    dnsIndex = 0;
        bool   help     = false;

        for (int i = 0; i < args.Length; i++)
        {
            string token = args[i].TrimStart('-', '/').ToLowerInvariant();

            switch (token)
            {
                case "silent":
                    silent = true;
                    break;

                case "help":
                case "h":
                case "?":
                    help = true;
                    break;

                case "preset" when i + 1 < args.Length:
                    i++;
                    preset = NormalizePreset(args[i]);
                    break;

                case "dns" when i + 1 < args.Length:
                    i++;
                    if (int.TryParse(args[i], out int idx))
                        dnsIndex = Math.Clamp(idx, 0, 3);
                    break;
            }
        }

        return new CliArgs(silent, preset, dnsIndex, help);
    }

    private static string NormalizePreset(string raw) => raw.ToLowerInvariant() switch
    {
        "gaming" or "game"         => "Gaming",
        "prod"   or "productivity" => "Prod",
        _                          => "Safe",
    };
}
