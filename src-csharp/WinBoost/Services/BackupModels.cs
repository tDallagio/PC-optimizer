using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace WinBoost.Services;

public sealed class BackupAction
{
    public string Type  { get; set; } = "";
    public string Label { get; set; } = "";
    public string Ts    { get; set; } = "";

    // reg
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? RegPath { get; set; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Native  { get; set; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? File    { get; set; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool?   Existed { get; set; }

    // service
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? SvcName { get; set; }

    // powerplan
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? PrevGuid      { get; set; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool?   PrevHibernate { get; set; }
}

public sealed class SvcEntry
{
    public string Name       { get; set; } = "";
    public string StartMode  { get; set; } = "";
    public bool   WasRunning { get; set; }
    public string Ts         { get; set; } = "";
}

public sealed class NetEntry
{
    public string Name        { get; set; } = "";
    public int    IfIndex     { get; set; }
    public string DnsServers  { get; set; } = "";
    public bool   Ipv6Enabled { get; set; }
    public string Ts          { get; set; } = "";
}

public sealed class PageFileEntry
{
    public string Name        { get; set; } = "";
    public int    InitialSize { get; set; }
    public int    MaximumSize { get; set; }
}

public sealed class PageFileBackup
{
    public bool                  AutomaticManaged { get; set; }
    public List<PageFileEntry>   PageFiles        { get; set; } = [];
}

public sealed class RestoreResult
{
    public int          Ok           { get; set; }
    public int          Failed       { get; set; }
    public int          Skipped      { get; set; }
    public List<string> InvalidFiles { get; set; } = [];
}

public sealed class BackupSessionInfo
{
    public string           Path       { get; set; } = "";
    public string           FolderName { get; set; } = "";
    public string           Timestamp  { get; set; } = "";
    public int              FreedMb    { get; set; }
    public int              Actions    { get; set; }
    public string           Preset     { get; set; } = "Desconocido";
    public bool             HasMeta    { get; set; }
    public SessionMetadata? Meta       { get; set; }
}

public sealed class SessionMetadata
{
    public string  Version     { get; set; } = "";
    public string  Timestamp   { get; set; } = "";
    public string  SessionPath { get; set; } = "";
    public string  Preset      { get; set; } = "Manual";
    public int     FreedMb     { get; set; }
    public int     ScoreBefore { get; set; }
    public int     ScoreAfter  { get; set; }
    public int     ActionCount => Actions.Count;
    public List<BackupAction> Actions  { get; set; } = [];
    public List<SvcEntry>     Services { get; set; } = [];
    public List<NetEntry>     Network  { get; set; } = [];
}
