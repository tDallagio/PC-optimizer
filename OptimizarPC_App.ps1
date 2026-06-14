param(
    [switch]$Silent,
    [string]$Preset = "Safe"
)
#Requires -RunAsAdministrator
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MemAPI {
    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int cls, IntPtr info, int len);

    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);

    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll,
        ref TOKEN_PRIVILEGES newState, uint bufLen, IntPtr prev, IntPtr retLen);

    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    struct LUID { public uint Low; public int High; }

    [StructLayout(LayoutKind.Sequential)]
    struct TOKEN_PRIVILEGES { public uint Count; public LUID Luid; public uint Attributes; }

    public static bool EnablePrivilege(string name) {
        IntPtr tok = IntPtr.Zero;
        try {
            if (!OpenProcessToken(GetCurrentProcess(), 0x28u, out tok)) return false;
            LUID luid;
            if (!LookupPrivilegeValue(null, name, out luid)) return false;
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.Count = 1u; tp.Luid = luid; tp.Attributes = 2u;
            AdjustTokenPrivileges(tok, false, ref tp, 0u, IntPtr.Zero, IntPtr.Zero);
            return true;
        } finally {
            if (tok != IntPtr.Zero) CloseHandle(tok);
        }
    }

    public static uint PurgeStandbyList() {
        IntPtr p = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(p, 4);
        uint r = NtSetSystemInformation(0x50, p, 4);
        Marshal.FreeHGlobal(p);
        return r;
    }
}
"@ -EA SilentlyContinue

$IS_LAPTOP = $false; $HAS_SSD = $false
try { $ct=(Get-CimInstance Win32_SystemEnclosure -EA SilentlyContinue).ChassisTypes; if($ct -contains 8 -or $ct -contains 9 -or $ct -contains 10 -or $ct -contains 14){$IS_LAPTOP=$true} } catch {}
try { if(Get-PhysicalDisk -EA SilentlyContinue | Where-Object { $_.MediaType -eq "SSD" }){$HAS_SSD=$true} } catch {}
$totalRAM    = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,0)
$cpuName     = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$gpuName     = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name.Trim()
$_osObj      = Get-CimInstance Win32_OperatingSystem
$osCaption   = $_osObj.Caption
$buildNumber = [int]$_osObj.BuildNumber
$IS_WIN11    = $buildNumber -ge 22000
$diskType  = if($HAS_SSD){"SSD"}else{"HDD"}
$SYSDRIVE  = $env:SystemDrive
$VERSION      = "4.0"
$PROFILE_PATH = "$env:USERPROFILE\.OptimizarPC\profile.json"
$BACKUP_ROOT  = "$env:USERPROFILE\.OptimizarPC\backups"
$SETTINGS_PATH = "$env:USERPROFILE\.OptimizarPC\settings.json"

# Valores por defecto de settings
$script:settings = [PSCustomObject]@{
    Theme                = "dark"
    Language             = "es"
    CloseAction          = "exit"
    ShowSplash           = $true
    ProcRefreshSec       = 3
    RunAtStartup         = $false
    BackupRoot           = $BACKUP_ROOT
    BackupRetainDays     = 30
    TrialStartDate       = ""
    TrialExpired         = $false
    TechnicianName       = ""
    GameAffinityEnabled  = $false
}

# Cargar XAML desde archivo externo
$scriptDir = if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -ne "") {
    Split-Path $MyInvocation.MyCommand.Path -Parent
} else {
    Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
}
$xamlPath = Join-Path $scriptDir "OptimizarPC_UI.xaml"
if (-not (Test-Path $xamlPath)) {
    [Windows.MessageBox]::Show(
        "No se encontro OptimizarPC_UI.xaml`nAsegurate de que ambos archivos esten en la misma carpeta:`n$scriptDir",
        "WinBoost - Archivo no encontrado","OK","Error")
    exit 1
}
try {
    $xmlReader = [System.Xml.XmlReader]::Create($xamlPath)
    $window    = [Windows.Markup.XamlReader]::Load($xmlReader)
    $xmlReader.Close()
} catch {
    [Windows.MessageBox]::Show("Error cargando UI:`n$_","Error","OK","Error")
    exit 1
}

function Get-Ctrl { param($n) $window.FindName($n) }
function New-Brush([string]$hex) {
    if ($hex.Length -eq 9) { $hex = '#' + $hex.Substring(3) }
    elseif ($hex.Length -eq 8 -and -not $hex.StartsWith('#')) { $hex = '#' + $hex }
    $conv = New-Object Windows.Media.BrushConverter
    $b    = $conv.ConvertFromString($hex)
    [void]$b.Freeze()
    return $b
}
$lblCPU=Get-Ctrl "lblCPU"; $lblGPU=Get-Ctrl "lblGPU"; $lblRAM=Get-Ctrl "lblRAM"; $lblDisk=Get-Ctrl "lblDisk"
$lblOS=Get-Ctrl "lblOS"; $badgeLaptop=Get-Ctrl "badgeLaptop"
$infoOS=Get-Ctrl "infoOS"; $infoCPU=Get-Ctrl "infoCPU"; $infoGPU=Get-Ctrl "infoGPU"
$infoRAM=Get-Ctrl "infoRAM"; $infoDisk=Get-Ctrl "infoDisk"; $infoType=Get-Ctrl "infoType"
$diskPanel=Get-Ctrl "diskPanel"; $rtbLog=Get-Ctrl "rtbLog"; $logScroll=Get-Ctrl "logScroll"
$lblLogStatus=Get-Ctrl "lblLogStatus"; $lblProgress=Get-Ctrl "lblProgress"; $lblPct=Get-Ctrl "lblPct"
$progressBar=Get-Ctrl "progressBar"; $lblSpaceFreed=Get-Ctrl "lblSpaceFreed"
$btnRun=Get-Ctrl "btnRun"; $btnSelAll=Get-Ctrl "btnSelAll"; $btnSelNone=Get-Ctrl "btnSelNone"
# Boton Detener creado dinamicamente en el footer junto a btnRun (F2.12)
$btnCancelOpt = New-Object Windows.Controls.Button
$btnCancelOpt.Content    = "Detener"
$btnCancelOpt.Margin     = New-Object Windows.Thickness(0,0,8,0)
$btnCancelOpt.Visibility = [Windows.Visibility]::Collapsed
$cancelStyle = $window.FindResource("BtnDanger")
$btnCancelOpt.Style = $cancelStyle
[void]($btnRun.Parent).Children.Insert(($btnRun.Parent).Children.IndexOf($btnRun), $btnCancelOpt)

$btnCancelOpt.Add_Click({
    $script:_cancelOptimize = $true
    $btnCancelOpt.IsEnabled = $false
    $btnCancelOpt.Content   = "Deteniendo..."
    Write-Log "Cancelacion solicitada - finalizando fase actual..." "info"
    Flush-UI
})

# Boton Analizar creado dinamicamente en el footer (F2.13)
$btnAnalyze = New-Object Windows.Controls.Button
$btnAnalyze.Content = "Analizar"
$btnAnalyze.Margin  = New-Object Windows.Thickness(0,0,8,0)
$analyzeStyle = $window.FindResource("BtnSec")
$btnAnalyze.Style = $analyzeStyle
[void]($btnSelAll.Parent).Children.Insert(($btnSelAll.Parent).Children.IndexOf($btnSelAll), $btnAnalyze)
$btnAnalyze.Add_Click({ Show-AnalysisReport })
$btnClearLog=Get-Ctrl "btnClearLog"; $btnExportLog=Get-Ctrl "btnExportLog"; $mainTabs=Get-Ctrl "mainTabs"
$btnPresetGaming=Get-Ctrl "btnPresetGaming"; $btnPresetProd=Get-Ctrl "btnPresetProd"
$btnPresetSafe=Get-Ctrl "btnPresetSafe"; $btnSaveProfile=Get-Ctrl "btnSaveProfile"
$badgeUpdate=Get-Ctrl "badgeUpdate"; $lblUpdateBadge=Get-Ctrl "lblUpdateBadge"
$btnBenchmark=Get-Ctrl "btnBenchmark"; $lblBenchStatus=Get-Ctrl "lblBenchStatus"
$lblWriteSpeed=Get-Ctrl "lblWriteSpeed"; $lblReadSpeed=Get-Ctrl "lblReadSpeed"
$lblWriteCompare=Get-Ctrl "lblWriteCompare"; $lblReadCompare=Get-Ctrl "lblReadCompare"
$btnDeepClean=Get-Ctrl "btnDeepClean"; $lblDeepCleanStatus=Get-Ctrl "lblDeepCleanStatus"
$barCPUFill=Get-Ctrl "barCPUFill"; $lblCPUPct=Get-Ctrl "lblCPUPct"
$barRAMFill=Get-Ctrl "barRAMFill"; $lblRAMVal=Get-Ctrl "lblRAMVal"
$barDiskFill=Get-Ctrl "barDiskFill"; $lblDiskPct=Get-Ctrl "lblDiskPct"
$icStartup=Get-Ctrl "icStartup"; $lblStartupStatus=Get-Ctrl "lblStartupStatus"
$lblStartupCount=Get-Ctrl "lblStartupCount"; $btnRefreshStartup=Get-Ctrl "btnRefreshStartup"
$lblRAMTotal=Get-Ctrl "lblRAMTotal"; $lblRAMUsed=Get-Ctrl "lblRAMUsed"
$lblRAMFree=Get-Ctrl "lblRAMFree"; $lblRAMFreeStatus=Get-Ctrl "lblRAMFreeStatus"
$btnFreeRAM=Get-Ctrl "btnFreeRAM"
$cboDNSProvider=Get-Ctrl "cboDNSProvider"
$lblDNSHint=Get-Ctrl "lblDNSHint"

# Controles Score de salud (Modulo 3A)
$scoreWidget          = Get-Ctrl "scoreWidget"
$scoreWidget.Add_MouseLeftButtonUp({ Set-ActiveNav 4 })
$lblScoreValue        = Get-Ctrl "lblScoreValue"
$scoreBar             = Get-Ctrl "scoreBar"
$lblScoreTooltipTitle = Get-Ctrl "lblScoreTooltipTitle"
$lblScoreTooltipDetail= Get-Ctrl "lblScoreTooltipDetail"

# Controles Score visual (Modulo 3B)
$scoreDeltaBadge      = Get-Ctrl "scoreDeltaBadge"
$lblScoreDelta        = Get-Ctrl "lblScoreDelta"
$lblScorePanelValue   = Get-Ctrl "lblScorePanelValue"
$lblScorePanelLabel   = Get-Ctrl "lblScorePanelLabel"
$btnRecalcScore       = Get-Ctrl "btnRecalcScore"
$barCatRendimiento    = Get-Ctrl "barCatRendimiento"
$barCatPrivacidad     = Get-Ctrl "barCatPrivacidad"
$barCatRed            = Get-Ctrl "barCatRed"
$barCatServicios      = Get-Ctrl "barCatServicios"
$lblCatRendimiento    = Get-Ctrl "lblCatRendimiento"
$lblCatPrivacidad     = Get-Ctrl "lblCatPrivacidad"
$lblCatRed            = Get-Ctrl "lblCatRed"
$lblCatServicios      = Get-Ctrl "lblCatServicios"

# Controles Bloatware (Modulo 4B)
$icBloat           = Get-Ctrl "icBloat"
$lblBloatCount     = Get-Ctrl "lblBloatCount"
$lblBloatMB        = Get-Ctrl "lblBloatMB"
$lblBloatSafe      = Get-Ctrl "lblBloatSafe"
$lblBloatCaution   = Get-Ctrl "lblBloatCaution"
$lblBloatStatus    = Get-Ctrl "lblBloatStatus"
$lblBloatSelected  = Get-Ctrl "lblBloatSelected"
$lblBloatWinget    = Get-Ctrl "lblBloatWinget"
$btnScanBloat      = Get-Ctrl "btnScanBloat"
$btnBloatSelAll    = Get-Ctrl "btnBloatSelAll"
$btnBloatSelNone   = Get-Ctrl "btnBloatSelNone"
$btnRemoveBloat    = Get-Ctrl "btnRemoveBloat"
$cboBloatFilter    = Get-Ctrl "cboBloatFilter"

# Controles Procesos pesados (Modulo 5B)
$icProcs            = Get-Ctrl "icProcs"
$lblProcsStatus     = Get-Ctrl "lblProcsStatus"
$lblProcsCpuTotal   = Get-Ctrl "lblProcsCpuTotal"
$lblProcsCount      = Get-Ctrl "lblProcsCount"
$btnRefreshProcs    = Get-Ctrl "btnRefreshProcs"
$btnToggleProcTimer = Get-Ctrl "btnToggleProcTimer"
$chkShowSysProcs    = Get-Ctrl "chkShowSysProcs"

# Controles Drivers (F1.7 / F1.8)
$badgeDeviceProblems     = Get-Ctrl "badgeDeviceProblems"
$icDeviceProblems        = Get-Ctrl "icDeviceProblems"
$lblDeviceProblemsStatus = Get-Ctrl "lblDeviceProblemsStatus"
$btnScanDevices          = Get-Ctrl "btnScanDevices"
$btnOpenDevMgmt          = Get-Ctrl "btnOpenDevMgmt"
$icDrivers               = Get-Ctrl "icDrivers"
$lblDriversStatus        = Get-Ctrl "lblDriversStatus"
$btnScanDrivers          = Get-Ctrl "btnScanDrivers"
$cboDriverClass          = Get-Ctrl "cboDriverClass"

# Controles Historial (Modulo 1C)
$icHistory         = Get-Ctrl "icHistory"
$lblHistoryStatus  = Get-Ctrl "lblHistoryStatus"
$btnRefreshHistory = Get-Ctrl "btnRefreshHistory"
$btnRevertLast     = Get-Ctrl "btnRevertLast"
$btnOpenBackupFolder = Get-Ctrl "btnOpenBackupFolder"
$rtbRestoreLog     = Get-Ctrl "rtbRestoreLog"
$restoreLogScroll  = Get-Ctrl "restoreLogScroll"
$lblRestoreLog     = Get-Ctrl "lblRestoreLog"
$badgeRestoreStatus= Get-Ctrl "badgeRestoreStatus"
$footerBar         = Get-Ctrl "footerBar"

# Controles sidebar (rediseno)
$navOptimizar    = Get-Ctrl "navOptimizar"
$navConsola      = Get-Ctrl "navConsola"
$navArranque     = Get-Ctrl "navArranque"
$navHerramientas = Get-Ctrl "navHerramientas"
$navInfo         = Get-Ctrl "navInfo"
$navHistorial    = Get-Ctrl "navHistorial"
$navBloatware    = Get-Ctrl "navBloatware"
$navAjustes      = Get-Ctrl "navAjustes"
$navLicencia     = Get-Ctrl "navLicencia"

# Controles Settings
$cboTheme             = Get-Ctrl "cboTheme"
$cboLanguage          = Get-Ctrl "cboLanguage"
$cboCloseAction       = Get-Ctrl "cboCloseAction"
$chkShowSplash        = Get-Ctrl "chkShowSplash"
$cboProcRefresh       = Get-Ctrl "cboProcRefresh"
$chkRunAtStartup      = Get-Ctrl "chkRunAtStartup"
$lblBackupPath        = Get-Ctrl "lblBackupPath"
$btnChangeBackupPath  = Get-Ctrl "btnChangeBackupPath"
$cboBackupRetention   = Get-Ctrl "cboBackupRetention"
$lblBackupCount       = Get-Ctrl "lblBackupCount"
$btnOpenBackups       = Get-Ctrl "btnOpenBackups"
$lblVersionAbout      = Get-Ctrl "lblVersionAbout"
$btnCheckUpdatesSettings = Get-Ctrl "btnCheckUpdatesSettings"
$lblStatsSessions     = Get-Ctrl "lblStatsSessions"
$lblStatsMB           = Get-Ctrl "lblStatsMB"
$lblStatsScore        = Get-Ctrl "lblStatsScore"
$lblStatsDays         = Get-Ctrl "lblStatsDays"
$btnResetSettings     = Get-Ctrl "btnResetSettings"

# Controles Licencia (Modulo 12C)
$badgeLicenseFree    = Get-Ctrl "badgeLicenseFree"
$badgeLicensePro     = Get-Ctrl "badgeLicensePro"
$lblLicenseStatus    = Get-Ctrl "lblLicenseStatus"
$lblHardwareID       = Get-Ctrl "lblHardwareID"
$btnCopyHWID         = Get-Ctrl "btnCopyHWID"
$txtLicenseKey       = Get-Ctrl "txtLicenseKey"
$btnActivateLicense  = Get-Ctrl "btnActivateLicense"
$lblActivationResult = Get-Ctrl "lblActivationResult"
$btnGetLicense       = Get-Ctrl "btnGetLicense"
$btnErrBadge         = Get-Ctrl "btnErrBadge"

# Controles banner trial (F0.2)
$bannerTrial         = Get-Ctrl "bannerTrial"
$lblTrialText        = Get-Ctrl "lblTrialText"
$btnTrialUpgrade     = Get-Ctrl "btnTrialUpgrade"
$lblErrCount         = Get-Ctrl "lblErrCount"

$script:navButtons = @(
    $navOptimizar, $navConsola, $navArranque, $navHerramientas,
    $navInfo, $navHistorial, $navBloatware, $navAjustes
)
$script:errorList = [System.Collections.Generic.List[string]]::new()

$checks = @{
    TempUser=Get-Ctrl "chkTempUser"; TempSys=Get-Ctrl "chkTempSys"
    Prefetch=Get-Ctrl "chkPrefetch"; WinUpdate=Get-Ctrl "chkWinUpdate"
    Browsers=Get-Ctrl "chkBrowsers"; Thumb=Get-Ctrl "chkThumb"
    Recycle=Get-Ctrl "chkRecycle";   EventLogs=Get-Ctrl "chkEventLogs"
    Power=Get-Ctrl "chkPower";       HPET=Get-Ctrl "chkHPET"
    GPUPrio=Get-Ctrl "chkGPUPrio"
    PowerThrot=Get-Ctrl "chkPowerThrot"
    Visual=Get-Ctrl "chkVisual";     MouseAccel=Get-Ctrl "chkMouseAccel"
    Startup=Get-Ctrl "chkStartup";   GameDVR=Get-Ctrl "chkGameDVR"
    GameMode=Get-Ctrl "chkGameMode"; Telemetry=Get-Ctrl "chkTelemetry"
    Cortana=Get-Ctrl "chkCortana";   Notif=Get-Ctrl "chkNotif"
    Tasks=Get-Ctrl "chkTasks";       Nagle=Get-Ctrl "chkNagle"
    TCP=Get-Ctrl "chkTCP";           DNS=Get-Ctrl "chkDNS"
    DNSFlush=Get-Ctrl "chkDNSFlush"; SvcXbox=Get-Ctrl "chkSvcXbox"
    SvcDiag=Get-Ctrl "chkSvcDiag";  SvcWER=Get-Ctrl "chkSvcWER"
    SvcSysMain=Get-Ctrl "chkSvcSysMain"; SvcMaps=Get-Ctrl "chkSvcMaps"
    SvcFax=Get-Ctrl "chkSvcFax";        SvcWSearch=Get-Ctrl "chkSvcWSearch"
    FastStartup=Get-Ctrl "chkFastStartup"; DisableIPv6=Get-Ctrl "chkDisableIPv6"
    PageFile=Get-Ctrl "chkPageFile";       TrimDesfrag=Get-Ctrl "chkTrimDesfrag"
}

# ============================================================
# INFO DEL SISTEMA
# ============================================================
$cs=if($cpuName.Length-gt26){$cpuName.Substring(0,26)+"..."}else{$cpuName}
$gs=if($gpuName.Length-gt26){$gpuName.Substring(0,26)+"..."}else{$gpuName}
$lblCPU.Text=$cs; $lblGPU.Text=$gs; $lblRAM.Text="$totalRAM GB"; $lblDisk.Text=$diskType
$lblOS.Text=$osCaption -replace "Microsoft ",""; $infoOS.Text=$osCaption
$infoCPU.Text=$cpuName; $infoGPU.Text=$gpuName; $infoRAM.Text="$totalRAM GB"
$infoDisk.Text=$diskType; $infoType.Text=if($IS_LAPTOP){"Laptop"}else{"PC Escritorio"}
if($IS_LAPTOP){$badgeLaptop.Visibility="Visible"; $checks.Power.Content="Plan Alto Rendimiento (laptop)"}
if(-not $HAS_SSD){$checks.Prefetch.IsChecked=$false; $checks.SvcSysMain.IsChecked=$false; $checks.SvcWSearch.IsChecked=$false}

# ---- Tabla de proveedores DNS ----
$script:dnsProviders = @(
    @{ Name="Cloudflare"; Primary="1.1.1.1";         Secondary="1.0.0.1"           }
    @{ Name="Google";     Primary="8.8.8.8";          Secondary="8.8.4.4"           }
    @{ Name="Quad9";      Primary="9.9.9.9";          Secondary="149.112.112.112"   }
    @{ Name="AdGuard";    Primary="94.140.14.14";     Secondary="94.140.15.15"      }
)

function Update-DNSHint {
    $idx = $cboDNSProvider.SelectedIndex
    if($idx -lt 0 -or $idx -ge $script:dnsProviders.Count){ $idx=0 }
    $p = $script:dnsProviders[$idx]
    $lblDNSHint.Text = "$($p.Name)  $($p.Primary) / $($p.Secondary)"
    $cboDNSProvider.IsEnabled = [bool]$checks.DNS.IsChecked
}

$cboDNSProvider.Add_SelectionChanged({ Update-DNSHint })
$checks.DNS.Add_Checked({   Update-DNSHint })
$checks.DNS.Add_Unchecked({ Update-DNSHint })
Update-DNSHint

function Set-ActiveNav {
    param([int]$index)
    $mainTabs.SelectedIndex = $index
    for($i = 0; $i -lt $script:navButtons.Count; $i++){
        $style = if($i -eq $index){ "BtnNavActive" } else { "BtnNav" }
        try { $script:navButtons[$i].Style = $window.FindResource($style) } catch {}
    }
    # F2.18 — navTuning no esta en $script:navButtons (igual que navLicencia)
    try {
        if($script:navTuning){
            $tuningStyle = if($index -eq 9){ "BtnNavActive" } else { "BtnNav" }
            $script:navTuning.Style = $window.FindResource($tuningStyle)
        }
    } catch {}
    $footerBar.Visibility = if($index -eq 0){ "Visible" } else { "Collapsed" }
    $footerBar.Height     = if($index -eq 0){ [double]::NaN } else { 0 }
    try {
        $content = $mainTabs.SelectedContent
        if ($content) {
            $anim          = New-Object Windows.Media.Animation.DoubleAnimation
            $anim.From     = 0.0
            $anim.To       = 1.0
            $anim.Duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds(150))
            $content.BeginAnimation([Windows.UIElement]::OpacityProperty, $anim)
        }
    } catch {}
    Flush-UI
}

$navOptimizar.Add_Click(    { Set-ActiveNav 0 })
$navConsola.Add_Click(      { Set-ActiveNav 1 })
$navArranque.Add_Click(     { Set-ActiveNav 2 })
$navHerramientas.Add_Click( { Set-ActiveNav 3 })
$navInfo.Add_Click(         { Set-ActiveNav 4 })
$navHistorial.Add_Click(    { Set-ActiveNav 5 })
$navBloatware.Add_Click(    { Set-ActiveNav 6 })
$navAjustes.Add_Click(      { Set-ActiveNav 7 })
$navLicencia.Add_Click(     { Set-ActiveNav 8 })

# ---- Modulo 2.3 — Badge de errores en sidebar ----
function Show-ErrorSummary {
    $n = $script:errorList.Count
    if($n -eq 0){ return }

    $totalTxt = if($n -eq 1){ "1 error registrado" } else { "$n errores registrados" }

    $errXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinBoost - Errores" Width="440" Height="360"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        ShowInTaskbar="False" Background="#0D0D0D" Foreground="#CCCCCC"
        FontFamily="Segoe UI" FontSize="12">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Errores detectados" FontSize="14" FontWeight="Bold" Foreground="#EF4444"/>
      <TextBlock x:Name="lblErrTotal" FontSize="11" Foreground="#666666" Margin="0,3,0,0"/>
    </StackPanel>
    <Border Grid.Row="1" Background="#161616" BorderBrush="#222222"
            BorderThickness="1" CornerRadius="6">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="2">
        <StackPanel x:Name="errStack" Margin="8,6,8,6"/>
      </ScrollViewer>
    </Border>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="btnErrConsola" Content="Ver consola" Width="110" Height="30"
              Margin="0,0,8,0" Background="#1A1A1A" Foreground="#CCCCCC"
              BorderBrush="#333333" BorderThickness="1" Cursor="Hand"/>
      <Button x:Name="btnErrClear" Content="Limpiar" Width="90" Height="30"
              Background="#2A0A0A" Foreground="#EF4444"
              BorderBrush="#5A1515" BorderThickness="1" Cursor="Hand"/>
    </StackPanel>
  </Grid>
</Window>
"@
    try {
        $reader = [System.Xml.XmlNodeReader]::new([xml]$errXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $dlgLblTotal  = $dlg.FindName("lblErrTotal")
        $dlgErrStack  = $dlg.FindName("errStack")
        $dlgBtnConsola = $dlg.FindName("btnErrConsola")
        $dlgBtnClear   = $dlg.FindName("btnErrClear")

        $dlgLblTotal.Text = $totalTxt

        foreach($entry in $script:errorList) {
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text        = $entry
            $tb.Foreground  = New-Brush "#EF4444"
            $tb.FontSize    = 11
            $tb.TextWrapping = "Wrap"
            $tb.Margin      = New-Object Windows.Thickness(0,0,0,5)
            $dlgErrStack.Children.Add($tb) | Out-Null
        }

        $dlgBtnConsola.Add_Click({
            $dlg.Close()
            Set-ActiveNav 1
        })

        $dlgBtnClear.Add_Click({
            $script:errorList.Clear()
            $btnErrBadge.Visibility = "Collapsed"
            $dlg.Close()
        })

        $dlg.ShowDialog() | Out-Null
    } catch {}
}

$btnErrBadge.Add_Click({ Show-ErrorSummary })

try {
    $drives=Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue|Where-Object{$null -ne $_.Used}
    foreach($d in $drives){
        $total=[math]::Round(($d.Used+$d.Free)/1GB,1); $used=[math]::Round($d.Used/1GB,1)
        $pct=if($total-gt0){[math]::Round($d.Used/($d.Used+$d.Free)*100,0)}else{0}
        $col=if($pct-gt85){"#EF4444"}elseif($pct-gt70){"#F59E0B"}else{"#00C8FF"}
        $sp=New-Object Windows.Controls.StackPanel; $sp.Margin=New-Object Windows.Thickness(0,0,0,10)
        $hdr=New-Object Windows.Controls.Grid
        $c1=New-Object Windows.Controls.ColumnDefinition; $c1.Width=New-Object Windows.GridLength(1,[Windows.GridUnitType]::Star)
        $c2=New-Object Windows.Controls.ColumnDefinition; $c2.Width=[Windows.GridLength]::Auto
        $hdr.ColumnDefinitions.Add($c1); $hdr.ColumnDefinitions.Add($c2)
        $t1=New-Object Windows.Controls.TextBlock; $t1.Text="Unidad $($d.Name):"; $t1.FontSize=12
        $t1.Foreground=New-Brush "#A9A9A9"
        [Windows.Controls.Grid]::SetColumn($t1,0); $hdr.Children.Add($t1)|Out-Null
        $t2=New-Object Windows.Controls.TextBlock; $t2.Text="$used GB / $total GB  ($pct%)"; $t2.FontSize=12
        $t2.Foreground=New-Brush $col
        [Windows.Controls.Grid]::SetColumn($t2,1); $hdr.Children.Add($t2)|Out-Null
        # F0.6: Grid con columnas Star — evita closure bug de add_SizeChanged
        $barOuter = New-Object Windows.Controls.Border
        $barOuter.Height = 6
        $barOuter.CornerRadius = New-Object Windows.CornerRadius(3)
        $barOuter.Margin = New-Object Windows.Thickness(0,5,0,0)
        $barOuter.ClipToBounds = $true
        $barOuter.Background = New-Brush "#696969"
        $barGrid = New-Object Windows.Controls.Grid
        $colFill = New-Object Windows.Controls.ColumnDefinition
        $colFill.Width = New-Object Windows.GridLength([math]::Max(1,$pct), [Windows.GridUnitType]::Star)
        $colRest = New-Object Windows.Controls.ColumnDefinition
        $colRest.Width = New-Object Windows.GridLength([math]::Max(1,(100-$pct)), [Windows.GridUnitType]::Star)
        $barGrid.ColumnDefinitions.Add($colFill); $barGrid.ColumnDefinitions.Add($colRest)
        $fillBdr = New-Object Windows.Controls.Border
        $fillBdr.Background = New-Brush $col
        [Windows.Controls.Grid]::SetColumn($fillBdr, 0)
        $barGrid.Children.Add($fillBdr) | Out-Null
        $barOuter.Child = $barGrid
        $sp.Children.Add($hdr)|Out-Null; $sp.Children.Add($barOuter)|Out-Null
        $diskPanel.Items.Add($sp)|Out-Null
    }
} catch {}

# ============================================================
# SETTINGS
# ============================================================
function Load-Settings {
    try {
        if(Test-Path $SETTINGS_PATH){
            $json = Get-Content $SETTINGS_PATH -Raw -EA Stop | ConvertFrom-Json
            if($null -ne $json.Theme)           { $script:settings.Theme            = $json.Theme           }
            if($null -ne $json.Language)        { $script:settings.Language         = $json.Language        }
            if($null -ne $json.CloseAction)     { $script:settings.CloseAction      = $json.CloseAction     }
            if($null -ne $json.ShowSplash)      { $script:settings.ShowSplash       = [bool]$json.ShowSplash}
            if($null -ne $json.ProcRefreshSec)  { $script:settings.ProcRefreshSec   = [int]$json.ProcRefreshSec }
            if($null -ne $json.RunAtStartup)    { $script:settings.RunAtStartup     = [bool]$json.RunAtStartup  }
            if($null -ne $json.BackupRoot)      { $script:settings.BackupRoot       = $json.BackupRoot      }
            if($null -ne $json.BackupRetainDays){ $script:settings.BackupRetainDays = [int]$json.BackupRetainDays }
            if($null -ne $json.TrialStartDate)   { $script:settings.TrialStartDate  = [string]$json.TrialStartDate  }
            if($null -ne $json.TrialExpired)     { $script:settings.TrialExpired    = [bool]$json.TrialExpired      }
            if($null -ne $json.TechnicianName)      { $script:settings.TechnicianName     = [string]$json.TechnicianName     }
            if($null -ne $json.GameAffinityEnabled){ $script:settings.GameAffinityEnabled = [bool]$json.GameAffinityEnabled }
        }
    } catch {}
}

function Save-Settings {
    try {
        $dir = Split-Path $SETTINGS_PATH
        if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $script:settings | ConvertTo-Json | Out-File $SETTINGS_PATH -Encoding UTF8
    } catch {}
}

function Apply-Theme {
    param([string]$theme = "")
    try {
        if(-not $theme){ $theme = $script:settings.Theme }
        if($theme -eq "auto"){
            $regVal = (Get-ItemProperty `
                -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
                -Name "AppsUseLightTheme" -EA SilentlyContinue).AppsUseLightTheme
            # 1 = light, 0 = dark
            $theme = if($regVal -eq 1){ "light" } else { "dark" }
        }
        $isLight = ($theme -eq "light")
        $palette = if($isLight){
            @{
                BrushAppBg   = "#F5F5F5"; BrushSidebar = "#EBEBEB"
                BrushCard    = "#FFFFFF"; BrushDeep    = "#F0F0F0"
                BrushElev    = "#E8E8E8"; BrushCtrl    = "#E0E0E0"
                BrushBorder  = "#DDDDDD"
                BrushFg1     = "#111111"; BrushFg2     = "#333333"
                BrushFgMuted = "#666666"; BrushFgDim   = "#888888"
            }
        } else {
            @{
                BrushAppBg   = "#0D0D0D"; BrushSidebar = "#111111"
                BrushCard    = "#161616"; BrushDeep    = "#0A0A0A"
                BrushElev    = "#1A1A1A"; BrushCtrl    = "#1E1E1E"
                BrushBorder  = "#2A2A2A"
                BrushFg1     = "#EEEEEE"; BrushFg2     = "#CCCCCC"
                BrushFgMuted = "#888888"; BrushFgDim   = "#555555"
            }
        }
        foreach($key in $palette.Keys){
            $window.Resources[$key] = New-Brush $palette[$key]
        }
    } catch {}
}

function Apply-Settings {
    try {
        $script:procTimerInterval = $script:settings.ProcRefreshSec
        if($script:procTimer -and $script:procTimerRunning){
            $script:procTimer.Interval = [TimeSpan]::FromSeconds($script:procTimerInterval)
        }
        $startupKey  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $startupName = "WinBoost"
        $exePath     = if($PSCommandPath){ $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        if($script:settings.RunAtStartup){
            try {
                Set-ItemProperty $startupKey -Name $startupName `
                    -Value "`"$exePath`"" -EA SilentlyContinue
            } catch {}
        } else {
            try {
                Remove-ItemProperty $startupKey -Name $startupName -EA SilentlyContinue
            } catch {}
        }
        Apply-Theme
    } catch {}
}

# ============================================================
# CARGAR PERFIL
# ============================================================
function Load-Profile {
    try {
        if(Test-Path $PROFILE_PATH){
            $json=Get-Content $PROFILE_PATH -Raw | ConvertFrom-Json
            foreach($k in $checks.Keys){
                $val=$json.$k
                if($null -ne $val){ $checks[$k].IsChecked=[bool]$val }
            }
            # Restaurar proveedor DNS seleccionado
            $dnsIdx = $json._dnsProviderIndex
            if($null -ne $dnsIdx -and $dnsIdx -ge 0 -and $dnsIdx -lt $script:dnsProviders.Count){
                $cboDNSProvider.SelectedIndex = [int]$dnsIdx
            }
        }
    } catch {}
}
Load-Profile

# Verificar actualizaciones al abrir (no bloquea la UI)
$window.Dispatcher.BeginInvoke([action]{ Check-ForUpdates }, [Windows.Threading.DispatcherPriority]::Background) | Out-Null

# ============================================================
# MODULO 1A - INFRAESTRUCTURA DE BACKUP / UNDO
# ============================================================
$script:activeSession     = $null   # path de la sesion activa
$script:sessionActions    = @()     # lista de acciones registradas en la sesion
$script:sessionSvcBackup  = @()     # estado previo de servicios
$script:sessionNetBackup  = @()     # estado previo de adaptadores de red

# ------------------------------------------------------------
# New-BackupSession
# Crea la carpeta de sesion con timestamp y devuelve su path.
# Llamar UNA vez al inicio de cada ejecucion de optimizacion.
# ------------------------------------------------------------
function New-BackupSession {
    $ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $sessionPath = Join-Path $BACKUP_ROOT $ts
    try {
        New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
        $script:activeSession    = $sessionPath
        $script:sessionActions   = @()
        $script:sessionSvcBackup = @()
        $script:sessionNetBackup = @()
        Write-Log "Sesion de backup iniciada: $ts" "ok"
    } catch {
        Write-Log "No se pudo crear sesion de backup: $_" "err"
        $script:activeSession = $null
    }
    return $script:activeSession
}

# ------------------------------------------------------------
# Save-RegBackup
# Exporta UNA clave de registro completa a un .reg numerado
# dentro de la sesion activa. Llamar ANTES de modificar la clave.
# Parametros:
#   $regPath  - ruta PS (HKLM:\...) de la clave padre
#   $label    - nombre legible para el log y el JSON
# ------------------------------------------------------------
function Save-RegBackup {
    param([string]$regPath, [string]$label)
    if(-not $script:activeSession){ return }
    try {
        # Convertir ruta PS a ruta nativa de reg.exe
        $nativePath = $regPath `
            -replace '^HKLM:\\', 'HKLM\' `
            -replace '^HKCU:\\', 'HKCU\' `
            -replace '^HKCR:\\', 'HKCR\' `
            -replace '^HKU:\\',  'HKU\'  `
            -replace '^HKCC:\\', 'HKCC\'

        $idx      = ($script:sessionActions | Where-Object { $_.type -eq "reg" }).Count
        $fileName = "reg_{0:D3}_{1}.reg" -f $idx, ($label -replace '[^a-zA-Z0-9_]','_')
        $outFile  = Join-Path $script:activeSession $fileName

        # reg export falla silenciosamente si la clave no existe todavia - esta bien
        $result = reg export $nativePath $outFile /y 2>&1
        $existed = Test-Path $outFile

        $script:sessionActions += [PSCustomObject]@{
            type     = "reg"
            label    = $label
            regPath  = $regPath
            native   = $nativePath
            file     = $fileName
            existed  = $existed
            ts       = (Get-Date -Format "HH:mm:ss")
        }
    } catch {
        # Silencioso - el backup es best-effort, no debe interrumpir la optimizacion
    }
}

# ------------------------------------------------------------
# Save-SvcBackup
# Guarda el StartType y Running state de un servicio ANTES
# de deshabilitarlo. Llamar desde Disable-Svc.
# ------------------------------------------------------------
function Save-SvcBackup {
    param([string]$svcName)
    if(-not $script:activeSession){ return }
    try {
        $svc = Get-Service -Name $svcName -EA SilentlyContinue
        if($svc){
            $cimSvc    = Get-CimInstance Win32_Service -Filter "Name='$svcName'" -EA SilentlyContinue
            $startMode = if($cimSvc){ $cimSvc.StartMode } else { $svc.StartType.ToString() }
            # Get-Service y CIM reportan "Auto" tanto para Automatic como para Automatic (Delayed Start).
            # El flag real esta en el registro; leerlo para distinguirlos correctamente.
            if($startMode -eq "Auto"){
                $delayed = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName" `
                                -Name DelayedAutoStart -EA SilentlyContinue).DelayedAutoStart
                if($delayed -eq 1){ $startMode = "AutoDelayed" }
            }
            $script:sessionSvcBackup += [PSCustomObject]@{
                name      = $svcName
                startMode = $startMode
                wasRunning= ($svc.Status -eq "Running")
                ts        = (Get-Date -Format "HH:mm:ss")
            }
            $script:sessionActions += [PSCustomObject]@{
                type    = "service"
                label   = "Servicio: $svcName"
                svcName = $svcName
                ts      = (Get-Date -Format "HH:mm:ss")
            }
        }
    } catch {}
}

# ------------------------------------------------------------
# Save-NetBackup
# Captura DNS actual y estado de IPv6 de cada adaptador activo.
# Llamar UNA vez antes de aplicar cambios de red.
# ------------------------------------------------------------
function Save-NetBackup {
    if(-not $script:activeSession){ return }
    try {
        Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
            $adapter = $_
            $dns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                        -AddressFamily IPv4 -EA SilentlyContinue).ServerAddresses
            $ipv6Binding = Get-NetAdapterBinding -Name $adapter.Name `
                               -ComponentID "ms_tcpip6" -EA SilentlyContinue
            $script:sessionNetBackup += [PSCustomObject]@{
                name        = $adapter.Name
                ifIndex     = $adapter.InterfaceIndex
                dnsServers  = if($dns){ $dns -join "," } else { "" }
                ipv6Enabled = if($ipv6Binding){ $ipv6Binding.Enabled } else { $true }
                ts          = (Get-Date -Format "HH:mm:ss")
            }
        }
        if($script:sessionNetBackup.Count -gt 0){
            $script:sessionActions += [PSCustomObject]@{
                type  = "network"
                label = "Configuracion de red ($($script:sessionNetBackup.Count) adaptadores)"
                ts    = (Get-Date -Format "HH:mm:ss")
            }
        }
    } catch {}
}

# ------------------------------------------------------------
# Save-SessionMetadata
# Escribe session.json al FINAL de la sesion con el resumen
# completo: acciones, MB liberados, score (placeholder por ahora).
# ------------------------------------------------------------
function Save-SessionMetadata {
    param(
        [int]$freedMB       = 0,
        [int]$scoreBefore   = 0,
        [int]$scoreAfter    = 0,
        [string]$preset     = "Manual"
    )
    if(-not $script:activeSession){ return }
    try {
        $meta = [PSCustomObject]@{
            version      = $VERSION
            timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            sessionPath  = $script:activeSession
            preset       = $preset
            freedMB      = $freedMB
            scoreBefore  = $scoreBefore
            scoreAfter   = $scoreAfter
            actionCount  = $script:sessionActions.Count
            actions      = $script:sessionActions
            services     = $script:sessionSvcBackup
            network      = $script:sessionNetBackup
        }
        $jsonPath = Join-Path $script:activeSession "session.json"
        $meta | ConvertTo-Json -Depth 6 | Out-File $jsonPath -Encoding UTF8
        Write-Log "Metadata de sesion guardada ($($meta.actionCount) acciones)" "ok"
        # Refrescar lista de historial automaticamente
        try { Render-HistoryItems } catch {}
    } catch {
        Write-Log "No se pudo guardar metadata: $_" "err"
    }
}

# ------------------------------------------------------------
# Get-BackupSessions
# Devuelve la lista de sesiones guardadas ordenadas por fecha
# descendente. Cada objeto tiene: path, timestamp, metadata.
# ------------------------------------------------------------
function Get-BackupSessions {
    $sessions = @()
    if(-not (Test-Path $BACKUP_ROOT)){ return $sessions }
    try {
        Get-ChildItem -Path $BACKUP_ROOT -Directory -EA SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            $jsonFile = Join-Path $_.FullName "session.json"
            $meta     = $null
            if(Test-Path $jsonFile){
                try { $meta = Get-Content $jsonFile -Raw -EA SilentlyContinue | ConvertFrom-Json }
                catch {}
            }
            $sessions += [PSCustomObject]@{
                path      = $_.FullName
                folderName= $_.Name
                timestamp = if($meta){ $meta.timestamp } else { $_.Name -replace '_',' ' }
                freedMB   = if($meta){ $meta.freedMB   } else { 0 }
                actions   = if($meta){ $meta.actionCount} else { 0 }
                preset    = if($meta){ $meta.preset     } else { "Desconocido" }
                hasMeta   = ($null -ne $meta)
                meta      = $meta
            }
        }
    } catch {}
    return $sessions
}

# ------------------------------------------------------------
# Cleanup-OldBackups
# Elimina sesiones mas antiguas que $keepDays (default 30).
# Llamar al inicio de la app para no acumular espacio en disco.
# ------------------------------------------------------------
function Cleanup-OldBackups {
    param([int]$keepDays = 30)
    if(-not (Test-Path $BACKUP_ROOT)){ return }
    try {
        $cutoff = (Get-Date).AddDays(-$keepDays)
        Get-ChildItem -Path $BACKUP_ROOT -Directory -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue } catch {}
        }
    } catch {}
}

# ============================================================
# MODULO 1B - MOTOR DE RESTAURACION / UNDO
# ============================================================

# ------------------------------------------------------------
# Test-RegFileValid — Modulo 2.6
# Verifica que un .reg tiene cabecera valida y al menos un HKEY.
# Soporta UTF-16 LE (BOM FF FE) y ANSI/UTF-8.
# ------------------------------------------------------------
function Test-RegFileValid {
    param([string]$path)
    try {
        if(-not (Test-Path $path)) { return $false }
        if((Get-Item $path).Length -lt 10) { return $false }

        $bytes = [System.IO.File]::ReadAllBytes($path)

        $enc = if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            [System.Text.Encoding]::Unicode        # UTF-16 LE
        } else {
            [System.Text.Encoding]::Default        # ANSI / UTF-8 sin BOM
        }

        $text      = $enc.GetString($bytes)
        $firstLine = (($text -split "`r`n|`n")[0]).Trim([char]0xFEFF).Trim()

        if($firstLine -ne "Windows Registry Editor Version 5.00" -and
           $firstLine -ne "REGEDIT4") {
            return $false
        }
        if($text -notmatch '\[HKEY_') { return $false }
        return $true
    } catch {
        return $false
    }
}

# ------------------------------------------------------------
# Restore-RegFromSession
# Importa todos los archivos .reg de una sesion usando reg import.
# Devuelve @{ ok=N; failed=N; skipped=N; invalidFiles=@() }
# ------------------------------------------------------------
function Restore-RegFromSession {
    param([string]$sessionPath)
    $result = @{ ok=0; failed=0; skipped=0; invalidFiles=@() }
    try {
        $regFiles = Get-ChildItem -Path $sessionPath -Filter "reg_*.reg" `
                        -EA SilentlyContinue | Sort-Object Name

        foreach($f in $regFiles){
            # Archivo vacio = clave no existia antes, hay que borrarla
            if((Get-Item $f.FullName).Length -lt 5){
                $result.skipped++
                continue
            }
            # Validar integridad antes de llamar reg.exe
            if(-not (Test-RegFileValid $f.FullName)){
                $result.failed++
                $result.invalidFiles += $f.Name
                continue
            }
            try {
                $proc = Start-Process -FilePath "reg.exe" `
                            -ArgumentList "import `"$($f.FullName)`"" `
                            -Wait -PassThru -WindowStyle Hidden `
                            -EA Stop
                if($proc.ExitCode -eq 0){ $result.ok++ }
                else                    { $result.failed++ }
            } catch {
                $result.failed++
            }
        }
    } catch {
        $result.failed++
    }
    return $result
}

# ------------------------------------------------------------
# Restore-ServicesFromSession
# Reestablece el StartupType y estado de arranque de cada
# servicio guardado en la metadata de la sesion.
# ------------------------------------------------------------
function Restore-ServicesFromSession {
    param([object]$sessionMeta)
    $result = @{ ok=0; failed=0; skipped=0 }
    if(-not $sessionMeta -or -not $sessionMeta.services){ return $result }

    $modeMap = @{
        "Auto"        = "Automatic"
        "Automatic"   = "Automatic"
        "AutoDelayed" = "Automatic"
        "Manual"      = "Manual"
        "Disabled"    = "Disabled"
        "Boot"        = "Boot"
        "System"      = "System"
    }

    foreach($svcInfo in $sessionMeta.services){
        try {
            $svc = Get-Service -Name $svcInfo.name -EA SilentlyContinue
            if(-not $svc){ $result.skipped++; continue }

            $startupType = if($modeMap.ContainsKey($svcInfo.startMode)){
                               $modeMap[$svcInfo.startMode]
                           } else { "Manual" }

            Set-Service -Name $svcInfo.name -StartupType $startupType -EA Stop

            # Restaurar delayed-start si el servicio lo tenia antes de deshabilitar
            if($svcInfo.startMode -eq "AutoDelayed"){
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($svcInfo.name)" `
                    -Name DelayedAutoStart -Value 1 -Type DWord -EA SilentlyContinue
            }

            # Si el servicio estaba corriendo originalmente, intentar iniciarlo
            if($svcInfo.wasRunning -and $startupType -ne "Disabled"){
                try { Start-Service -Name $svcInfo.name -EA SilentlyContinue } catch {}
            }
            $result.ok++
        } catch {
            $result.failed++
        }
    }
    return $result
}

# ------------------------------------------------------------
# Restore-NetworkFromSession
# Restaura DNS y binding de IPv6 por adaptador desde metadata.
# ------------------------------------------------------------
function Restore-NetworkFromSession {
    param([object]$sessionMeta)
    $result = @{ ok=0; failed=0; skipped=0 }
    if(-not $sessionMeta -or -not $sessionMeta.network){ return $result }

    foreach($netInfo in $sessionMeta.network){
        try {
            $adapter = Get-NetAdapter -EA SilentlyContinue |
                           Where-Object { $_.Name -eq $netInfo.name } |
                           Select-Object -First 1
            if(-not $adapter){ $result.skipped++; continue }

            # Restaurar DNS
            if($netInfo.dnsServers -and $netInfo.dnsServers -ne ""){
                $dnsArr = $netInfo.dnsServers -split ","
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                    -ServerAddresses $dnsArr -EA SilentlyContinue
            } else {
                # Sin DNS guardado = estaba en automatico (DHCP)
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                    -ResetServerAddresses -EA SilentlyContinue
            }

            # Restaurar binding IPv6
            $currentBinding = Get-NetAdapterBinding -Name $adapter.Name `
                                  -ComponentID "ms_tcpip6" -EA SilentlyContinue
            if($currentBinding){
                if($netInfo.ipv6Enabled -and -not $currentBinding.Enabled){
                    Enable-NetAdapterBinding  -Name $adapter.Name -ComponentID "ms_tcpip6" -EA SilentlyContinue
                } elseif(-not $netInfo.ipv6Enabled -and $currentBinding.Enabled){
                    Disable-NetAdapterBinding -Name $adapter.Name -ComponentID "ms_tcpip6" -EA SilentlyContinue
                }
            }
            $result.ok++
        } catch {
            $result.failed++
        }
    }

    # Flush DNS siempre al restaurar red
    try { ipconfig /flushdns 2>$null | Out-Null } catch {}
    return $result
}

# ------------------------------------------------------------
# Restore-HpetFromSession
# Revierte los cambios de bcdedit si HPET fue modificado.
# Lee las acciones de la sesion para saber si aplica.
# ------------------------------------------------------------
function Restore-HpetFromSession {
    param([object]$sessionMeta)
    if(-not $sessionMeta -or -not $sessionMeta.actions){ return }
    # Buscar si hubo cambio de HPET en esta sesion via las acciones de registro
    $hpetChanged = $sessionMeta.actions | Where-Object {
        $_.type -eq "reg" -and $_.label -match "useplatform|HPET|dynamictick"
    }
    # El HPET no se guarda en .reg (es bcdedit), asi que revertimos a defaults seguros
    # solo si detectamos que algo de timer fue modificado
    $timerActions = $sessionMeta.actions | Where-Object {
        $_.type -eq "reg" -and ($_.label -match "platform|tick|timer")
    }
    # Revertir bcdedit al estado default de Windows
    try {
        bcdedit /deletevalue useplatformtick    2>$null | Out-Null
        bcdedit /deletevalue disabledynamictick 2>$null | Out-Null
        bcdedit /deletevalue useplatformclock   2>$null | Out-Null
    } catch {}
}

# ------------------------------------------------------------
# Save-PowerPlanBackup
# Captura el GUID del plan de energia activo y el estado de
# hibernacion ANTES de cambiar el plan. Guarda en sessionActions.
# ------------------------------------------------------------
function Save-PowerPlanBackup {
    if(-not $script:activeSession){ return }
    try {
        $schemeOutput = powercfg /getactivescheme 2>$null | Out-String
        $prevGUID = if($schemeOutput -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'){
            $Matches[1]
        } else { "381b4222-f694-41f0-9685-ff5bb260df2e" }
        $hibVal = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
                      -Name HibernateEnabled -EA SilentlyContinue).HibernateEnabled
        $prevHibernate = if($null -ne $hibVal){ [bool]($hibVal -eq 1) } else { $true }
        $script:sessionActions += [PSCustomObject]@{
            type          = "powerplan"
            label         = "Plan de energia"
            prevGUID      = $prevGUID
            prevHibernate = $prevHibernate
            ts            = (Get-Date -Format "HH:mm:ss")
        }
    } catch {}
}

# ------------------------------------------------------------
# Save-PageFileBackup
# Captura la configuracion actual de PageFile (gestion automatica
# + settings por volumen) antes de modificarla. Guarda
# pagefile_backup.json en la sesion activa y registra la accion.
# ------------------------------------------------------------
function Save-PageFileBackup {
    if(-not $script:activeSession){ return }
    try {
        $cs       = Get-CimInstance Win32_ComputerSystem -EA Stop
        $existing = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue
        $pfList   = @()
        foreach($pf in $existing){
            $pfList += [PSCustomObject]@{
                Name        = $pf.Name
                InitialSize = $pf.InitialSize
                MaximumSize = $pf.MaximumSize
            }
        }
        $backup = [PSCustomObject]@{
            AutomaticManaged = $cs.AutomaticManagedPagefile
            PageFiles        = $pfList
        }
        $outFile = Join-Path $script:activeSession "pagefile_backup.json"
        $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $outFile -Encoding UTF8
        $script:sessionActions += [PSCustomObject]@{
            type  = "pagefile"
            label = "PageFile (Win32_PageFileSetting)"
            file  = "pagefile_backup.json"
            ts    = (Get-Date -Format "HH:mm:ss")
        }
    } catch {}
}

# ------------------------------------------------------------
# Save-NetshBackup
# Captura la salida de "netsh int tcp show global" a un archivo
# de texto en la sesion activa, para poder restaurar despues.
# ------------------------------------------------------------
function Save-NetshBackup {
    if(-not $script:activeSession){ return }
    try {
        $output  = netsh int tcp show global 2>$null | Out-String
        $outFile = Join-Path $script:activeSession "netsh_backup.txt"
        $output | Set-Content -Path $outFile -Encoding UTF8
        $script:sessionActions += [PSCustomObject]@{
            type  = "netsh"
            label = "TCP global (netsh int tcp show global)"
            file  = "netsh_backup.txt"
            ts    = (Get-Date -Format "HH:mm:ss")
        }
    } catch {}
}

# ------------------------------------------------------------
# Restore-PageFileFromSession
# Restaura la configuracion de PageFile desde pagefile_backup.json.
# ------------------------------------------------------------
function Restore-PageFileFromSession {
    param([string]$sessionPath, [scriptblock]$logFn = $null)
    $log = if($logFn){ $logFn } else { { param($m,$t) Write-Log $m $t } }
    $result = @{ ok=0; failed=0 }
    $backupFile = Join-Path $sessionPath "pagefile_backup.json"
    if(-not (Test-Path $backupFile)){ return $result }
    try {
        $backup = Get-Content $backupFile -Raw -EA Stop | ConvertFrom-Json
        $cs     = Get-CimInstance Win32_ComputerSystem -EA Stop
        if($backup.AutomaticManaged){
            Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true} -EA Stop
            & $log "PageFile: gestion automatica restaurada" "ok"
        } else {
            if($cs.AutomaticManagedPagefile){
                Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -EA Stop
            }
            $current = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue
            foreach($pf in $current){ try { Remove-CimInstance -InputObject $pf -EA SilentlyContinue } catch {} }
            foreach($pf in $backup.PageFiles){
                New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                    Name        = $pf.Name
                    InitialSize = [uint32]$pf.InitialSize
                    MaximumSize = [uint32]$pf.MaximumSize
                } -EA SilentlyContinue | Out-Null
            }
            & $log "PageFile: configuracion original restaurada ($($backup.PageFiles.Count) entrada(s))" "ok"
        }
        & $log "Cambio de PageFile efectivo tras reinicio" "info"
        $result.ok = 1
    } catch {
        & $log "Error restaurando PageFile: $_" "err"
        $result.failed = 1
    }
    return $result
}

# ------------------------------------------------------------
# Restore-NetshFromSession
# Restaura los parametros TCP globales desde netsh_backup.txt.
# ------------------------------------------------------------
function Restore-NetshFromSession {
    param([string]$sessionPath, [scriptblock]$logFn = $null)
    $log = if($logFn){ $logFn } else { { param($m,$t) Write-Log $m $t } }
    $result = @{ ok=0; failed=0 }
    $backupFile = Join-Path $sessionPath "netsh_backup.txt"
    if(-not (Test-Path $backupFile)){ return $result }
    try {
        $content = Get-Content $backupFile -Raw -EA Stop
        $tuning  = if($content -match "Receive Window Auto-Tuning Level\s*:\s*(\S+)"){ $Matches[1].ToLower() } else { "normal" }
        $chimney = if($content -match "Chimney Offload State\s*:\s*(\S+)")           { $Matches[1].ToLower() } else { "disabled" }
        $rss     = if($content -match "Receive-Side Scaling State\s*:\s*(\S+)")      { $Matches[1].ToLower() } else { "enabled" }
        $fo      = if($content -match "TCP Fast Open\s*:\s*(\S+)")                   { $Matches[1].ToLower() } else { "enabled" }
        netsh int tcp set global autotuninglevel=$tuning  2>$null | Out-Null
        netsh int tcp set global chimney=$chimney          2>$null | Out-Null
        netsh int tcp set global rss=$rss                  2>$null | Out-Null
        netsh int tcp set global fastopen=$fo              2>$null | Out-Null
        & $log "TCP global restaurado desde backup (tuning=$tuning rss=$rss)" "ok"
        $result.ok = 1
    } catch {
        & $log "Error restaurando TCP global: $_" "err"
        $result.failed = 1
    }
    return $result
}

# ------------------------------------------------------------
# Restore-Session  *** FUNCION PRINCIPAL DE UNDO ***
# Orquesta la restauracion completa de una sesion.
# Parametros:
#   $sessionPath - path de la carpeta de sesion
#   $logFn       - bloque de script para loguear { param($msg,$type) }
# Devuelve un resumen de resultados.
# ------------------------------------------------------------
function Restore-Session {
    param(
        [string]$sessionPath,
        [scriptblock]$logFn = $null
    )

    $log = if($logFn){ $logFn } else { { param($m,$t) Write-Log $m $t } }

    if(-not (Test-Path $sessionPath)){
        & $log "Sesion no encontrada: $sessionPath" "err"
        return $false
    }

    # Cargar metadata
    $jsonFile = Join-Path $sessionPath "session.json"
    $meta     = $null
    if(Test-Path $jsonFile){
        try { $meta = Get-Content $jsonFile -Raw | ConvertFrom-Json } catch {}
    }

    & $log "RESTAURANDO SESION" "head"
    & $log "Carpeta: $(Split-Path $sessionPath -Leaf)" "info"
    if($meta){ & $log "Sesion del: $($meta.timestamp)  ($($meta.actionCount) acciones)" "info" }

    $totalOk     = 0
    $totalFailed = 0

    # 1) Registro - importar .reg
    & $log "Restaurando registro..." "info"
    $regResult = Restore-RegFromSession -sessionPath $sessionPath
    $totalOk     += $regResult.ok
    $totalFailed += $regResult.failed
    & $log "Registro: $($regResult.ok) ok  $($regResult.failed) fallidos  $($regResult.skipped) omitidos" `
           $(if($regResult.failed -gt 0){"err"}else{"ok"})
    foreach($inv in $regResult.invalidFiles){
        & $log "Archivo .reg invalido o corrupto omitido: $inv" "err"
    }

    # 2) Servicios
    if($meta -and $meta.services -and @($meta.services).Count -gt 0){
        & $log "Restaurando servicios..." "info"
        $svcResult = Restore-ServicesFromSession -sessionMeta $meta
        $totalOk     += $svcResult.ok
        $totalFailed += $svcResult.failed
        & $log "Servicios: $($svcResult.ok) ok  $($svcResult.failed) fallidos  $($svcResult.skipped) omitidos" `
               $(if($svcResult.failed -gt 0){"err"}else{"ok"})
    }

    # 3) Red
    if($meta -and $meta.network -and @($meta.network).Count -gt 0){
        & $log "Restaurando configuracion de red..." "info"
        $netResult = Restore-NetworkFromSession -sessionMeta $meta
        $totalOk     += $netResult.ok
        $totalFailed += $netResult.failed
        & $log "Red: $($netResult.ok) ok  $($netResult.failed) fallidos  $($netResult.skipped) omitidos" `
               $(if($netResult.failed -gt 0){"err"}else{"ok"})
        & $log "Cache DNS limpiada" "ok"
    }

    # 4) HPET / bcdedit (sin .reg propio)
    if($meta){
        $hpetAction = $meta.actions | Where-Object { $_.label -match "HPET|useplatform|dynamictick" }
        if($hpetAction){
            & $log "Restaurando timers del sistema (bcdedit)..." "info"
            Restore-HpetFromSession -sessionMeta $meta
            & $log "Timers restaurados a defaults de Windows" "ok"
            $totalOk++
        }
    }

    # 5) Plan de energia - restaurar GUID original guardado
    if($meta){
        $powerAction = $meta.actions | Where-Object { $_.type -eq "powerplan" } | Select-Object -First 1
        if($powerAction){
            try {
                $prevGUID = $powerAction.prevGUID
                if($prevGUID){
                    powercfg /setactive $prevGUID 2>$null | Out-Null
                    & $log "Plan de energia restaurado (GUID: $prevGUID)" "ok"
                } else {
                    powercfg /setactive SCHEME_BALANCED 2>$null | Out-Null
                    & $log "Plan de energia restaurado a Equilibrado" "ok"
                }
                if($powerAction.prevHibernate -eq $true){
                    powercfg /hibernate on 2>$null | Out-Null
                    & $log "Hibernacion reactivada" "ok"
                }
                $totalOk++
            } catch {
                & $log "Error restaurando plan de energia" "err"
                $totalFailed++
            }
        }
    }

    # 6) PageFile - restaurar configuracion original
    if($meta){
        $pfAction = $meta.actions | Where-Object { $_.type -eq "pagefile" } | Select-Object -First 1
        if($pfAction){
            & $log "Restaurando PageFile..." "info"
            $pfResult = Restore-PageFileFromSession -sessionPath $sessionPath -logFn $log
            $totalOk     += $pfResult.ok
            $totalFailed += $pfResult.failed
        }
    }

    # 7) TCP global - restaurar configuracion netsh
    if($meta){
        $netshAction = $meta.actions | Where-Object { $_.type -eq "netsh" } | Select-Object -First 1
        if($netshAction){
            & $log "Restaurando TCP global (netsh)..." "info"
            $netshResult = Restore-NetshFromSession -sessionPath $sessionPath -logFn $log
            $totalOk     += $netshResult.ok
            $totalFailed += $netshResult.failed
        }
    }

    $status = if($totalFailed -eq 0){ "ok" } else { "err" }
    & $log "Restauracion completada: $totalOk cambios revertidos, $totalFailed errores" $status
    & $log "Reinicia el equipo para que todos los cambios tomen efecto." "info"

    return ($totalFailed -eq 0)
}

# ============================================================
# HELPERS (originales, ahora con backup integrado)
# ============================================================
$script:freed=0
$script:logLines=@()

function Flush-UI {
    $window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::Background)
}

function Write-Log {
    param([string]$msg,[string]$type="info")
    $ts="$(Get-Date -Format 'HH:mm:ss')"
    $colorMap=@{ok="#22C55E"; err="#EF4444"; skip="#666666"; head="#00C8FF"; info="#F59E0B"}
    $labelMap=@{ok="  OK   "; err="  !!   "; skip="  --   "; head=" ====  "; info="  >>   "}
    $col  = if($colorMap.ContainsKey($type)){$colorMap[$type]}else{"#888888"}
    $lbl  = if($labelMap.ContainsKey($type)){$labelMap[$type]}else{"  >>   "}
    $line = "$ts$lbl$msg"
    $script:logLines += $line

    if($type -eq "err") {
        $script:errorList.Add("$ts  $msg")
        $n = $script:errorList.Count
        $btnErrBadge.Visibility = "Visible"
        $lblErrCount.Text = if($n -eq 1){ "1 error" } else { "$n errores" }
    }

    $para = New-Object System.Windows.Documents.Paragraph
    $para.Margin = New-Object Windows.Thickness(0)
    $run = New-Object System.Windows.Documents.Run($line)
    $run.Foreground = New-Brush $col
    $para.Inlines.Add($run) | Out-Null
    $rtbLog.Document.Blocks.Add($para) | Out-Null
    $logScroll.ScrollToEnd()
    Flush-UI
}

function Set-Progress {
    param([int]$pct,[string]$msg)
    $lblProgress.Text=$msg; $lblPct.Text="$pct%"
    $progressBar.Value=$pct
    Flush-UI
}

# F1.1: Toast al terminar optimizacion / mantenimiento
function Show-ToastNotification {
    param([string]$Title = "WinBoost", [string]$Message = "")
    try {
        # WinRT Toast (Windows 10+)
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$Title</text><text>$Message</text></binding></visual></toast>")
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("WinBoost").Show($toast)
        return
    } catch {}
    try {
        # Fallback: NotifyIcon balloon
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        $ni = New-Object System.Windows.Forms.NotifyIcon
        try { $ni.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
            [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
        catch { $ni.Icon = [System.Drawing.SystemIcons]::Application }
        $ni.Visible = $true
        $ni.ShowBalloonTip(5000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::None)
        $script:_toastNI = $ni
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(6)
        $t.Add_Tick({ try { $script:_toastNI.Dispose() } catch {}; $this.Stop() })
        $t.Start()
    } catch {}
}

function Get-FolderMB {
    param([string]$p)
    try{return [math]::Round((Get-ChildItem $p -Recurse -Force -EA SilentlyContinue|Measure-Object -Property Length -Sum).Sum/1MB,1)}catch{return 0}
}
function Remove-Dir {
    param([string]$p,[string]$label)
    if(Test-Path $p){$mb=Get-FolderMB $p;Get-ChildItem -Path $p -Recurse -Force -EA SilentlyContinue|Remove-Item -Recurse -Force -EA SilentlyContinue;Write-Log "$label - $mb MB liberados" "ok";return $mb}
    Write-Log "$label - no encontrado" "skip";return 0
}
function Set-Reg {
    param([string]$p,[string]$n,[string]$t,$v)
    try {
        # Backup automatico de la clave padre antes de modificar
        Save-RegBackup -regPath $p -label $n
        if(-not(Test-Path $p)){New-Item -Path $p -Force|Out-Null}
        Set-ItemProperty -Path $p -Name $n -Type $t -Value $v -Force
        Write-Log "$n = $v" "ok"
    }
    catch{ Write-Log "Fallo: $n" "err" }
}
function Disable-Svc {
    param([string]$name,[string]$label)
    try {
        $s = Get-Service -Name $name -EA SilentlyContinue
        if($s -and $s.StartType -ne "Disabled"){
            # Backup del estado previo antes de deshabilitar
            Save-SvcBackup -svcName $name
            Stop-Service -Name $name -Force -EA SilentlyContinue
            Set-Service  -Name $name -StartupType Disabled -EA Stop
            Write-Log $label "ok"
        } else {
            Write-Log "$label (ya deshabilitado)" "skip"
        }
    }
    catch{ Write-Log "Sin permisos: $label" "skip" }
}

# ============================================================
# PRESETS
# ============================================================
$presetGaming=@{TempUser=$true;TempSys=$true;Prefetch=$true;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$true;HPET=$true;GPUPrio=$true;PowerThrot=$true;Visual=$true;MouseAccel=$true;Startup=$true;FastStartup=$true;PageFile=$true;TrimDesfrag=$true;GameDVR=$true;GameMode=$true;Telemetry=$true;Cortana=$true;Notif=$true;Tasks=$true;Nagle=$true;TCP=$true;DNS=$true;DNSFlush=$true;DisableIPv6=$false;SvcXbox=$true;SvcDiag=$true;SvcWER=$true;SvcSysMain=$true;SvcMaps=$true;SvcFax=$true;SvcWSearch=$true}
$presetProd  =@{TempUser=$true;TempSys=$true;Prefetch=$false;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$true;HPET=$false;GPUPrio=$false;PowerThrot=$false;Visual=$false;MouseAccel=$false;Startup=$true;FastStartup=$false;PageFile=$true;TrimDesfrag=$true;GameDVR=$true;GameMode=$true;Telemetry=$true;Cortana=$true;Notif=$false;Tasks=$true;Nagle=$false;TCP=$false;DNS=$true;DNSFlush=$true;DisableIPv6=$false;SvcXbox=$true;SvcDiag=$true;SvcWER=$false;SvcSysMain=$false;SvcMaps=$false;SvcFax=$false;SvcWSearch=$false}
$presetSafe  =@{TempUser=$true;TempSys=$true;Prefetch=$false;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$false;HPET=$false;GPUPrio=$false;PowerThrot=$false;Visual=$false;MouseAccel=$false;Startup=$true;FastStartup=$false;PageFile=$false;TrimDesfrag=$false;GameDVR=$false;GameMode=$false;Telemetry=$false;Cortana=$false;Notif=$false;Tasks=$false;Nagle=$false;TCP=$false;DNS=$true;DNSFlush=$true;DisableIPv6=$false;SvcXbox=$false;SvcDiag=$false;SvcWER=$false;SvcSysMain=$false;SvcMaps=$false;SvcFax=$false;SvcWSearch=$false}

function Apply-Preset { param($p); foreach($k in $p.Keys){if($checks.ContainsKey($k)){$checks[$k].IsChecked=$p[$k]}} }

$btnPresetGaming.Add_Click({ Apply-Preset $presetGaming })
$btnPresetProd.Add_Click({   Apply-Preset $presetProd })
$btnPresetSafe.Add_Click({   Apply-Preset $presetSafe })

$btnSaveProfile.Add_Click({
    try {
        $dir=Split-Path $PROFILE_PATH
        if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $obj=@{}
        foreach($k in $checks.Keys){$obj[$k]=[bool]$checks[$k].IsChecked}
        $obj["_dnsProviderIndex"] = $cboDNSProvider.SelectedIndex
        $obj["firstRun"]          = [bool]$script:isFirstRun
        $obj|ConvertTo-Json|Out-File $PROFILE_PATH -Encoding UTF8
        [Windows.MessageBox]::Show("Perfil guardado:`n$PROFILE_PATH","WinBoost v$VERSION","OK","Information")|Out-Null
    } catch { [Windows.MessageBox]::Show("Error al guardar: $_","Error","OK","Error")|Out-Null }
})

# ============================================================
# BOTONES AUXILIARES
# ============================================================
$btnSelAll.Add_Click({
    # EventLogs es impacto alto — no se activa con Seleccionar todo (F2.1)
    foreach($k in $checks.Keys){ if($k -ne "EventLogs"){ $checks[$k].IsChecked=$true } }
})
$btnSelNone.Add_Click({foreach($c in $checks.Values){$c.IsChecked=$false}})

$btnClearLog.Add_Click({
    $rtbLog.Document.Blocks.Clear()
    $script:logLines=@()
    $lblLogStatus.Text="Log limpiado"
})

$btnExportLog.Add_Click({
    try {
        $docsPath=[System.Environment]::GetFolderPath("MyDocuments")
        $ts=Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $outFile="$docsPath\OptimizarPC_Log_$ts.txt"
        $script:logLines|Out-File $outFile -Encoding UTF8
        [Windows.MessageBox]::Show("Log exportado a:`n$outFile","WinBoost v$VERSION","OK","Information")|Out-Null
    } catch { [Windows.MessageBox]::Show("Error al exportar: $_","Error","OK","Error")|Out-Null }
})

# ============================================================
# MODULO 3A - MOTOR DE AUDITORIA / SCORE DE SALUD
# ============================================================
# Tabla de items auditables. Cada item:
#   Id       - clave unica
#   Label    - nombre legible
#   Category - grupo (Rendimiento / Privacidad / Red / Servicios)
#   Weight   - puntos que aporta si esta OK (total = 100)
#   Check    - scriptblock que devuelve $true (OK) o $false (no aplicado)
# ---------------------------------------------------------------
$script:auditItems = @(

    # --- RENDIMIENTO (26 pts) ---
    [PSCustomObject]@{
        Id="HPET"; Label="HPET deshabilitado"; Category="Rendimiento"; Weight=5
        Check={ (bcdedit /enum 2>$null | Select-String "disabledynamictick") -match "Yes" }
    }
    [PSCustomObject]@{
        Id="GPUPrio"; Label="GPU Priority (DXGI)"; Category="Rendimiento"; Weight=5
        Check={
            $v = Get-ItemProperty `
                "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" `
                -Name "GPU Priority" -EA SilentlyContinue
            $v -and $v."GPU Priority" -ge 8
        }
    }
    [PSCustomObject]@{
        Id="PowerThrot"; Label="Power Throttling desactivado"; Category="Rendimiento"; Weight=5
        Check={
            $v = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" `
                     -Name "PowerThrottlingOff" -EA SilentlyContinue
            $v -and $v.PowerThrottlingOff -eq 1
        }
    }
    [PSCustomObject]@{
        Id="MouseAccel"; Label="Aceleracion de mouse OFF"; Category="Rendimiento"; Weight=3
        Check={
            $v = Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -EA SilentlyContinue
            $v -and $v.MouseSpeed -eq "0"
        }
    }
    [PSCustomObject]@{
        Id="FastStartup"; Label="Fast Startup deshabilitado"; Category="Rendimiento"; Weight=4
        Check={
            $v = Get-ItemProperty `
                "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
                -Name "HiberbootEnabled" -EA SilentlyContinue
            $v -and $v.HiberbootEnabled -eq 0
        }
    }
    [PSCustomObject]@{
        Id="Visual"; Label="Efectos visuales minimizados"; Category="Rendimiento"; Weight=4
        Check={
            $v = Get-ItemProperty `
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
                -Name "VisualFXSetting" -EA SilentlyContinue
            $v -and $v.VisualFXSetting -eq 2
        }
    }

    # --- PRIVACIDAD (26 pts) ---
    [PSCustomObject]@{
        Id="Telemetry"; Label="Telemetria deshabilitada"; Category="Privacidad"; Weight=8
        Check={
            $v = Get-ItemProperty `
                "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
                -Name "AllowTelemetry" -EA SilentlyContinue
            $v -and $v.AllowTelemetry -eq 0
        }
    }
    [PSCustomObject]@{
        Id="GameDVR"; Label="Game DVR Xbox OFF"; Category="Privacidad"; Weight=5
        Check={
            $v = Get-ItemProperty "HKCU:\System\GameConfigStore" `
                     -Name "GameDVR_Enabled" -EA SilentlyContinue
            $v -and $v.GameDVR_Enabled -eq 0
        }
    }
    [PSCustomObject]@{
        Id="Cortana"; Label="Cortana deshabilitada"; Category="Privacidad"; Weight=5
        Check={
            $v = Get-ItemProperty `
                "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
                -Name "AllowCortana" -EA SilentlyContinue
            $v -and $v.AllowCortana -eq 0
        }
    }
    [PSCustomObject]@{
        Id="Tasks"; Label="Tareas de telemetria deshabilitadas"; Category="Privacidad"; Weight=8
        Check={
            $disabled = 0
            $taskList = @(
                @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"},
                @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"},
                @{Path="\Microsoft\Windows\DiskDiagnostic\"; Name="Microsoft-Windows-DiskDiagnosticDataCollector"}
            )
            foreach($t in $taskList){
                try {
                    $st = (Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -EA SilentlyContinue).State
                    if($st -eq "Disabled"){ $disabled++ }
                } catch {}
            }
            $disabled -ge 2
        }
    }

    # --- RED (18 pts) ---
    [PSCustomObject]@{
        Id="DNS"; Label="DNS optimizado (no ISP)"; Category="Red"; Weight=8
        Check={
            $knownDNS = @("1.1.1.1","1.0.0.1","8.8.8.8","8.8.4.4",
                          "9.9.9.9","149.112.112.112","94.140.14.14","94.140.15.15")
            $adapter = Get-NetAdapter -EA SilentlyContinue |
                           Where-Object { $_.Status -eq "Up" } |
                           Select-Object -First 1
            if(-not $adapter){ return $false }
            $dns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                        -AddressFamily IPv4 -EA SilentlyContinue).ServerAddresses
            $dns -and ($dns | Where-Object { $knownDNS -contains $_ }).Count -gt 0
        }
    }
    [PSCustomObject]@{
        Id="Nagle"; Label="Algoritmo de Nagle OFF"; Category="Red"; Weight=5
        Check={
            $found = $false
            Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" `
                -EA SilentlyContinue | ForEach-Object {
                $v = Get-ItemProperty $_.PSPath -Name "TcpAckFrequency" -EA SilentlyContinue
                if($v -and $v.TcpAckFrequency -eq 1){ $found = $true }
            }
            $found
        }
    }
    [PSCustomObject]@{
        Id="TCPTuning"; Label="TCP/IP optimizado (RSS habilitado)"; Category="Red"; Weight=5
        Check={
            $rss = netsh int tcp show global 2>$null | Select-String "Receive-Side Scaling"
            $rss -and $rss -match "enabled"
        }
    }

    # --- SERVICIOS (22 pts) ---
    [PSCustomObject]@{
        Id="SvcDiag"; Label="DiagTrack deshabilitado"; Category="Servicios"; Weight=7
        Check={
            $s = Get-Service "DiagTrack" -EA SilentlyContinue
            $s -and $s.StartType -eq "Disabled"
        }
    }
    [PSCustomObject]@{
        Id="SvcXbox"; Label="Servicios Xbox deshabilitados"; Category="Servicios"; Weight=5
        Check={
            $disabled = @("XblAuthManager","XblGameSave","XboxNetApiSvc") | ForEach-Object {
                $s = Get-Service $_ -EA SilentlyContinue
                if($s -and $s.StartType -eq "Disabled"){ 1 } else { 0 }
            }
            ($disabled | Measure-Object -Sum).Sum -ge 2
        }
    }
    [PSCustomObject]@{
        Id="SvcFax"; Label="Fax y RemoteRegistry deshabilitados"; Category="Servicios"; Weight=5
        Check={
            $fax = Get-Service "Fax" -EA SilentlyContinue
            $rr  = Get-Service "RemoteRegistry" -EA SilentlyContinue
            ($fax -and $fax.StartType -eq "Disabled") -or
            ($rr  -and $rr.StartType  -eq "Disabled")
        }
    }
    [PSCustomObject]@{
        Id="SvcWER"; Label="Windows Error Reporting deshabilitado"; Category="Servicios"; Weight=5
        Check={
            $s = Get-Service "WerSvc" -EA SilentlyContinue
            $s -and $s.StartType -eq "Disabled"
        }
    }
)

# ------------------------------------------------------------
# Get-SystemScore
# Ejecuta todos los checks y calcula el score 0-100.
# Devuelve: Score, Items, ByCategory, OkCount, FailCount, Total
# ------------------------------------------------------------
function Get-SystemScore {
    $results     = @()
    $totalPoints = 0
    $maxPoints   = ($script:auditItems | Measure-Object Weight -Sum).Sum

    foreach($item in $script:auditItems){
        $ok = $false
        try { $ok = [bool](& $item.Check) } catch {}
        $pts = if($ok){ $item.Weight } else { 0 }
        $totalPoints += $pts
        $results += [PSCustomObject]@{
            Id       = $item.Id
            Label    = $item.Label
            Category = $item.Category
            Weight   = $item.Weight
            Ok       = $ok
            Points   = $pts
        }
    }

    $score = if($maxPoints -gt 0){
        [math]::Round($totalPoints / $maxPoints * 100, 0)
    } else { 0 }

    $byCategory = @{}
    $results | Group-Object Category | ForEach-Object {
        $catOk  = ($_.Group | Where-Object { $_.Ok }).Count
        $catMax = $_.Group.Count
        $byCategory[$_.Name] = "$catOk/$catMax"
    }

    return [PSCustomObject]@{
        Score      = [int]$score
        Items      = $results
        ByCategory = $byCategory
        OkCount    = ($results | Where-Object { $_.Ok  }).Count
        FailCount  = ($results | Where-Object { -not $_.Ok }).Count
        Total      = $results.Count
    }
}

# ------------------------------------------------------------
# Update-ScoreWidget
# Recalcula el score y actualiza el widget del header.
# Acepta resultado pre-calculado para evitar doble calculo.
# ------------------------------------------------------------
function Update-ScoreWidget {
    param([PSCustomObject]$scoreResult = $null)
    try {
        if(-not $scoreResult){ $scoreResult = Get-SystemScore }
        $score = $scoreResult.Score

        $color = if($score -ge 75){ "#22C55E" }
                 elseif($score -ge 45){ "#F59E0B" }
                 else { "#EF4444" }

        $lblScoreValue.Text       = "$score"
        $lblScoreValue.Foreground = New-Brush $color
        $scoreBar.Background = New-Brush $color
        $scoreBar.Opacity    = [math]::Max(0.15, $score / 100)
        $scoreWidget.BorderBrush = New-Brush $color

        $label = if($score -ge 75){ "Sistema bien optimizado" }
                 elseif($score -ge 45){ "Optimizacion parcial" }
                 else { "Sin optimizar" }
        $lblScoreTooltipTitle.Text = "$label  ($score/100)"

        $detail = $scoreResult.ByCategory.GetEnumerator() | Sort-Object Name |
            ForEach-Object { "$($_.Key): $($_.Value)" }
        $failItems = $scoreResult.Items | Where-Object { -not $_.Ok } |
            Select-Object -First 5 | ForEach-Object { "  - $($_.Label)" }

        $detailText = ($detail -join "  |  ")
        $detailText += if($failItems){
            "`nPendientes:`n" + ($failItems -join "`n")
        } else { "`nTodo optimizado." }
        $lblScoreTooltipDetail.Text = $detailText

        # Actualizar tambien el panel visual del tab Info (Modulo 3B)
        Update-ScorePanel -scoreResult $scoreResult

    } catch {}
    Flush-UI
}

# ------------------------------------------------------------
# Update-ScorePanel (Modulo 3B)
# Actualiza el panel de desglose por categoria en el tab Info.
# ------------------------------------------------------------
function Update-ScorePanel {
    param([PSCustomObject]$scoreResult = $null)
    try {
        if(-not $scoreResult){ $scoreResult = Get-SystemScore }
        $score = $scoreResult.Score

        $color = if($score -ge 75){ "#22C55E" }
                 elseif($score -ge 45){ "#F59E0B" }
                 else { "#EF4444" }

        $label = if($score -ge 75){ "Sistema bien optimizado" }
                 elseif($score -ge 45){ "Optimizacion parcial - hay margen de mejora" }
                 else { "Sistema sin optimizar" }

        $lblScorePanelValue.Text       = "$score"
        $lblScorePanelValue.Foreground = New-Brush $color
        $lblScorePanelLabel.Text       = $label

        # Mapeo de categoria -> controles de barra y label
        $catMap = @{
            "Rendimiento" = @{ Bar=$barCatRendimiento; Lbl=$lblCatRendimiento }
            "Privacidad"  = @{ Bar=$barCatPrivacidad;  Lbl=$lblCatPrivacidad  }
            "Red"         = @{ Bar=$barCatRed;          Lbl=$lblCatRed         }
            "Servicios"   = @{ Bar=$barCatServicios;    Lbl=$lblCatServicios   }
        }

        # Calcular ok/total por categoria
        $grouped = $scoreResult.Items | Group-Object Category
        foreach($g in $grouped){
            if(-not $catMap.ContainsKey($g.Name)){ continue }
            $okCount  = ($g.Group | Where-Object { $_.Ok }).Count
            $total    = $g.Group.Count
            $pct      = if($total -gt 0){ $okCount / $total } else { 0 }

            $bar = $catMap[$g.Name].Bar
            $lbl = $catMap[$g.Name].Lbl
            $lbl.Text = "$okCount/$total"

            # Color de la barra segun el porcentaje de la categoria
            $barColor = if($pct -ge 0.75){ "#22C55E" }
                        elseif($pct -ge 0.45){ "#F59E0B" }
                        else { "#EF4444" }
            $bar.Background = New-Brush $barColor

            # Animar el ancho de la barra
            Animate-BarWidth -bar $bar -targetPct $pct
        }
    } catch {}
}

# ------------------------------------------------------------
# Animate-BarWidth (Modulo 3B)
# Anima el ancho de una barra hasta el porcentaje objetivo
# usando DoubleAnimation sobre el ActualWidth del contenedor.
# ------------------------------------------------------------
function Animate-BarWidth {
    param(
        [Windows.Controls.Border]$bar,
        [double]$targetPct
    )
    try {
        $parent = $bar.Parent
        if(-not $parent){ return }
        # El ancho objetivo se calcula sobre el ancho del contenedor padre
        $containerWidth = $parent.ActualWidth
        if($containerWidth -le 0){
            # Si aun no se renderizo, fijar directamente al hacer layout
            $bar.Width = 0
            $bar.Tag   = $targetPct
            return
        }
        $targetWidth = $containerWidth * $targetPct

        $anim = New-Object Windows.Media.Animation.DoubleAnimation
        $anim.From     = $bar.ActualWidth
        $anim.To       = $targetWidth
        $anim.Duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds(500))
        $ease = New-Object Windows.Media.Animation.CubicEase
        $ease.EasingMode = [Windows.Media.Animation.EasingMode]::EaseOut
        $anim.EasingFunction = $ease

        $bar.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $anim)
    } catch {
        # Fallback sin animacion
        try {
            $parent = $bar.Parent
            if($parent -and $parent.ActualWidth -gt 0){
                $bar.Width = $parent.ActualWidth * $targetPct
            }
        } catch {}
    }
}

# ------------------------------------------------------------
# Animate-ScoreCount (Modulo 3B)
# Anima el numero del score del header contando desde un valor
# inicial hasta el final, usando un DispatcherTimer.
# ------------------------------------------------------------
function Animate-ScoreCount {
    param(
        [int]$from,
        [int]$to,
        [int]$durationMs = 800
    )
    try {
        $steps    = 20
        $interval = [math]::Max(20, [math]::Round($durationMs / $steps))
        $diff     = $to - $from
        $script:scoreAnimStep    = 0
        $script:scoreAnimFrom    = $from
        $script:scoreAnimDiff    = $diff
        $script:scoreAnimSteps   = $steps

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($interval)
        $timer.Add_Tick({
            $script:scoreAnimStep++
            $progress = $script:scoreAnimStep / $script:scoreAnimSteps
            if($progress -ge 1){ $progress = 1 }
            # Easing cubico out
            $eased = 1 - [math]::Pow(1 - $progress, 3)
            $current = [int][math]::Round($script:scoreAnimFrom + $script:scoreAnimDiff * $eased)

            $col = if($current -ge 75){ "#22C55E" }
                   elseif($current -ge 45){ "#F59E0B" }
                   else { "#EF4444" }
            $lblScoreValue.Text       = "$current"
            $lblScoreValue.Foreground = New-Brush $col
            $lblScorePanelValue.Text       = "$current"
            $lblScorePanelValue.Foreground = New-Brush $col

            if($script:scoreAnimStep -ge $script:scoreAnimSteps){
                $this.Stop()
            }
        })
        $timer.Start()
    } catch {
        # Sin animacion: fijar directo
        $lblScoreValue.Text = "$to"
    }
}

# ------------------------------------------------------------
# Show-ScoreDelta (Modulo 3B)
# Muestra el badge de delta (+N / -N) junto al score del header.
# ------------------------------------------------------------
function Show-ScoreDelta {
    param([int]$delta)
    try {
        if($delta -eq 0){
            $scoreDeltaBadge.Visibility = "Collapsed"
            return
        }
        $sign  = if($delta -gt 0){ "+" } else { "" }
        $col   = if($delta -gt 0){ "#22C55E" } else { "#EF4444" }
        $bgCol = if($delta -gt 0){ "#0A2A0A" } else { "#2A0A0A" }

        $lblScoreDelta.Text       = "$sign$delta"
        $lblScoreDelta.Foreground = New-Brush $col
        $scoreDeltaBadge.Background = New-Brush $bgCol
        $scoreDeltaBadge.Visibility = "Visible"
    } catch {}
}

# ------------------------------------------------------------
# Evento: boton Recalcular score (Modulo 3B)
# ------------------------------------------------------------
$btnRecalcScore.Add_Click({
    $btnRecalcScore.IsEnabled = $false
    $lblScorePanelLabel.Text  = "Recalculando..."
    Flush-UI
    try {
        $scoreResult = Get-SystemScore
        $scoreDeltaBadge.Visibility = "Collapsed"
        Update-ScoreWidget -scoreResult $scoreResult
        # Animar desde 0 al recalcular manualmente para dar feedback visual
        Animate-ScoreCount -from 0 -to $scoreResult.Score -durationMs 700
    } catch {}
    $btnRecalcScore.IsEnabled = $true
    Flush-UI
})

# ============================================================
# MODULO 2 - MODAL DE CONFIRMACION PRE-EJECUCION
# ============================================================

# ------------------------------------------------------------
# Build-ActionPlan
# Analiza $sel y devuelve una lista ordenada de acciones
# planificadas con categoria, descripcion e impacto visual.
# Cada objeto: @{ Category; Label; Detail; Impact; Icon }
# Impact: "low" | "medium" | "high"
# ------------------------------------------------------------
function Build-ActionPlan {
    param([hashtable]$sel)

    $plan = [System.Collections.Generic.List[PSCustomObject]]::new()

    function Add-Action {
        param([string]$cat, [string]$label, [string]$detail, [string]$impact)
        $plan.Add([PSCustomObject]@{
            Category = $cat
            Label    = $label
            Detail   = $detail
            Impact   = $impact
        })
    }

    # --- SEGURIDAD ---
    if($sel["Startup"]){
        Add-Action "Seguridad" "Punto de restauracion" `
            "Crea un punto de restauracion de Windows antes de aplicar cambios" "low"
    }

    # --- LIMPIEZA ---
    if($sel["TempUser"])  { Add-Action "Limpieza" "Temp usuario"      "%TEMP% - archivos temporales del perfil de usuario"         "low" }
    if($sel["TempSys"])   { Add-Action "Limpieza" "Temp sistema"      "C:\Windows\Temp - temporales del sistema operativo"         "low" }
    if($sel["Prefetch"])  { Add-Action "Limpieza" "Prefetch (SSD)"    "C:\Windows\Prefetch - solo recomendado en SSD"              "low" }
    if($sel["WinUpdate"]) { Add-Action "Limpieza" "Cache Windows Update" "SoftwareDistribution\Download - paquetes ya instalados" "low" }
    if($sel["Browsers"])  { Add-Action "Limpieza" "Cache navegadores" "Chrome, Edge, Firefox, Brave, Opera - no borra contrasenas" "low" }
    if($sel["Thumb"])     { Add-Action "Limpieza" "Thumbnails"        "Cache de miniaturas del Explorador - se regenera solo"      "low" }
    if($sel["Recycle"])   { Add-Action "Limpieza" "Papelera"          "Vacia la papelera permanentemente"                          "low" }
    if($sel["EventLogs"]) { Add-Action "Limpieza" "Logs de eventos"   "Borra logs Aplicacion/Sistema/etc. Log de Seguridad NO se toca. Elimina registros forenses." "high" }

    # --- RENDIMIENTO ---
    if($sel["Power"])      { Add-Action "Rendimiento" "Plan de energia"        "Activa Ultimate Performance / Alto Rendimiento"         "medium" }
    if($sel["HPET"])       { Add-Action "Rendimiento" "Deshabilitar HPET"      "bcdedit: useplatformtick, disabledynamictick"           "medium" }
    if($sel["GPUPrio"])    { Add-Action "Rendimiento" "GPU Priority"           "Registro DXGI: GPU Priority=8, Scheduling=High"         "medium" }
    if($sel["PowerThrot"]) { Add-Action "Rendimiento" "Power Throttling OFF"   "PowerThrottlingOff=1 - evita bajadas de frecuencia"     "medium" }
    if($sel["Visual"])     { Add-Action "Rendimiento" "Efectos visuales min."  "VisualFXSetting=2 - desactiva animaciones de Windows"   "low"    }
    if($sel["MouseAccel"]) { Add-Action "Rendimiento" "Mouse accel OFF"        "MouseSpeed=0, MouseThreshold1/2=0"                      "low"    }
    if($sel["FastStartup"]){ Add-Action "Rendimiento" "Fast Startup OFF"       "HiberbootEnabled=0 + powercfg hibernate off"            "medium" }
    if($sel["PageFile"]){
        $script:_altDriveForPageFile = ""
        $script:_pageFileMoveToAlt   = $false
        try {
            $altDrv = Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue |
                Where-Object { $_.Root -ne "$SYSDRIVE\" -and $null -ne $_.Used } |
                Select-Object -First 1
            if($altDrv){ $script:_altDriveForPageFile = $altDrv.Root.TrimEnd('\') }
        } catch {}
        $pfDetail = if($script:_altDriveForPageFile -ne ""){
            "Tamanio fijo segun RAM. Disco secundario $($script:_altDriveForPageFile) detectado (ver opcion al pie de este resumen)."
        } else { "Tamanio fijo segun RAM via Win32_PageFileSetting" }
        Add-Action "Rendimiento" "Optimizar PageFile" $pfDetail "high"
    }
    if($sel["TrimDesfrag"]){
        $trimDetail = if($HAS_SSD){"Optimize-Volume ReTrim en SSD"}else{"Desfrag semanal en HDD"}
        Add-Action "Rendimiento" "TRIM / Desfrag" $trimDetail "low"
    }

    # --- PRIVACIDAD ---
    if($sel["GameDVR"])    { Add-Action "Privacidad" "Game DVR / Xbox OFF"  "GameDVR_Enabled=0, AllowGameDVR=0"                      "medium" }
    if($sel["GameMode"])   { Add-Action "Privacidad" "Game Mode OFF"        "AutoGameModeEnabled=0 - evita stutters en AMD/Ryzen"     "medium" }
    if($sel["Telemetry"])  { Add-Action "Privacidad" "Telemetria Windows"   "AllowTelemetry=0 - detiene envio de datos a Microsoft"   "medium" }
    if($sel["Cortana"])    { Add-Action "Privacidad" "Cortana OFF"          "AllowCortana=0 via politica de grupo"                    "medium" }
    if($sel["Notif"])      { Add-Action "Privacidad" "Notificaciones OFF"   "ToastEnabled=0 - sin interrupciones mientras se juega"   "low"    }
    if($sel["Tasks"])      { Add-Action "Privacidad" "Tareas telemetria"    "Deshabilita 5 tareas programadas de recopilacion de datos" "medium" }

    # --- RED ---
    if($sel["Nagle"])      { Add-Action "Red" "Nagle OFF"        "TcpAckFrequency=1, TCPNoDelay=1 en todos los adaptadores"  "medium" }
    if($sel["TCP"])        { Add-Action "Red" "TCP/IP gaming"    "netsh: autotuning normal, chimney disabled, RSS, FastOpen"  "medium" }
    if($sel["DNS"]){
        $dnsIdx  = $cboDNSProvider.SelectedIndex
        $dnsProv = if($dnsIdx -ge 0 -and $dnsIdx -lt $script:dnsProviders.Count){ $script:dnsProviders[$dnsIdx] } else { $script:dnsProviders[0] }
        Add-Action "Red" "DNS $($dnsProv.Name)" "$($dnsProv.Primary) / $($dnsProv.Secondary) en todos los adaptadores activos" "low"
    }
    if($sel["DNSFlush"])   { Add-Action "Red" "Flush DNS"         "ipconfig /flushdns - limpia cache DNS local"               "low"    }
    if($sel["DisableIPv6"]){ Add-Action "Red" "Preferir IPv4 sobre IPv6" "DisabledComponents=0x20 — IPv6 sigue activo, Windows prefiere IPv4. Seguro en todas las redes." "low" }

    # --- SERVICIOS ---
    if($sel["SvcXbox"])    { Add-Action "Servicios" "Xbox Live (3 svcs)"   "XblAuthManager, XblGameSave, XboxNetApiSvc -> Disabled"  "medium" }
    if($sel["SvcDiag"])    { Add-Action "Servicios" "DiagTrack"            "Connected User Experiences and Telemetry -> Disabled"    "medium" }
    if($sel["SvcWER"])     { Add-Action "Servicios" "Error Reporting"      "WerSvc -> Disabled"                                      "medium" }
    if($sel["SvcSysMain"]) { Add-Action "Servicios" "SysMain / Superfetch" "SysMain -> Disabled (solo SSD)"                         "medium" }
    if($sel["SvcMaps"])    { Add-Action "Servicios" "Maps / Geo"           "MapsBroker, lfsvc -> Disabled"                           "medium" }
    if($sel["SvcFax"])     { Add-Action "Servicios" "Fax / Remote Reg"     "Fax, RemoteRegistry -> Disabled"                         "medium" }
    if($sel["SvcWSearch"]) { Add-Action "Servicios" "Windows Search"       "WSearch -> Disabled (solo SSD)"                          "medium" }

    return $plan
}

# ------------------------------------------------------------
# New-ActionRow  (helper interno de Show-ConfirmDialog)
# Construye el Border de una sola accion para el ItemsControl del modal.
# ------------------------------------------------------------
function New-ActionRow {
    param([PSCustomObject]$action)
    $impactColor = @{ high="#EF4444"; medium="#F59E0B"; low="#22C55E" }
    $impactLabel = @{ high="Alto";    medium="Medio";   low="Bajo"    }
    $impKey = if($action.Impact){ "$($action.Impact)".ToLower().Trim() } else { "low" }
    if(-not $impactColor.ContainsKey($impKey)){ $impKey = "low" }
    $col   = $impactColor[$impKey]
    $bgCol = switch($impKey){ "high" { "#2A0A0A" } "medium" { "#2A1A00" } default { "#0A2A0A" } }

    $rowBdr = New-Object Windows.Controls.Border
    $rowBdr.Padding      = New-Object Windows.Thickness(10,6,10,6)
    $rowBdr.Margin       = New-Object Windows.Thickness(0,1,0,0)
    $rowBdr.Background   = New-Brush "#161616"
    $rowBdr.CornerRadius = New-Object Windows.CornerRadius(5)

    $rowGrid = New-Object Windows.Controls.Grid
    foreach($w in @(1, 65)){
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if($w -eq 1){
            [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        } else {
            [Windows.GridLength]::new($w)
        }
        $rowGrid.ColumnDefinitions.Add($cd)
    }

    $textPanel = New-Object Windows.Controls.StackPanel
    $lblTxt = New-Object Windows.Controls.TextBlock
    $lblTxt.Text       = $action.Label
    $lblTxt.FontSize   = 12
    $lblTxt.Foreground = New-Brush "#DDDDDD"
    $detTxt = New-Object Windows.Controls.TextBlock
    $detTxt.Text         = $action.Detail
    $detTxt.FontSize     = 10
    $detTxt.TextWrapping = [Windows.TextWrapping]::Wrap
    $detTxt.Foreground   = New-Brush "#555555"
    $detTxt.Margin       = New-Object Windows.Thickness(0,2,0,0)
    $textPanel.Children.Add($lblTxt) | Out-Null
    $textPanel.Children.Add($detTxt) | Out-Null
    [Windows.Controls.Grid]::SetColumn($textPanel, 0)

    $impBdr = New-Object Windows.Controls.Border
    $impBdr.CornerRadius        = New-Object Windows.CornerRadius(3)
    $impBdr.Padding             = New-Object Windows.Thickness(7,3,7,3)
    $impBdr.VerticalAlignment   = [Windows.VerticalAlignment]::Center
    $impBdr.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
    $impBdr.Background          = New-Brush $bgCol
    $impBdr.BorderBrush         = New-Brush $col
    $impBdr.BorderThickness     = New-Object Windows.Thickness(1)
    $impTxt = New-Object Windows.Controls.TextBlock
    $impTxt.Text       = if($impactLabel.ContainsKey($impKey)){ $impactLabel[$impKey] } else { $impKey }
    $impTxt.FontSize   = 10
    $impTxt.Foreground = New-Brush $col
    $impBdr.Child = $impTxt
    [Windows.Controls.Grid]::SetColumn($impBdr, 1)

    $rowGrid.Children.Add($textPanel) | Out-Null
    $rowGrid.Children.Add($impBdr)    | Out-Null
    $rowBdr.Child = $rowGrid
    return $rowBdr
}

# ------------------------------------------------------------
# Show-ConfirmDialog
# Muestra la ventana modal de confirmacion.
# Devuelve $true si el usuario confirma, $false si cancela.
# ------------------------------------------------------------
function Show-ConfirmDialog {
    param([System.Collections.Generic.List[PSCustomObject]]$plan)

    # Calcular resumen
    $totalActions  = $plan.Count
    $highImpact    = @($plan | Where-Object { $_.Impact -eq "high"   }).Count
    $medImpact     = @($plan | Where-Object { $_.Impact -eq "medium" }).Count
    $lowImpact     = @($plan | Where-Object { $_.Impact -eq "low"    }).Count
    $categories    = $plan | Select-Object -ExpandProperty Category -Unique

    # Colores de impacto
    $impactColor = @{ high="#EF4444"; medium="#F59E0B"; low="#22C55E" }
    $impactLabel = @{ high="Alto";    medium="Medio";   low="Bajo"    }

    # ---- XAML de la ventana modal ----
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinBoost - Confirmar optimizacion"
        Width="620" Height="560" MinWidth="500" MinHeight="400"
        WindowStartupLocation="CenterOwner"
        Background="#0D0D0D" FontFamily="Segoe UI"
        ResizeMode="CanResize" ShowInTaskbar="False">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Border Grid.Row="0" Background="#161616" BorderBrush="#2A2A2A" BorderThickness="0,0,0,1" Padding="20,14">
      <StackPanel>
        <TextBlock Text="Resumen de optimizacion" FontSize="15" FontWeight="SemiBold" Foreground="#EEEEEE"/>
        <TextBlock Text="Revisa los cambios que se van a aplicar antes de continuar." FontSize="11" Foreground="#888888" Margin="0,3,0,0"/>
      </StackPanel>
    </Border>

    <!-- Stats -->
    <Border Grid.Row="1" Background="#111111" BorderBrush="#2A2A2A" BorderThickness="0,0,0,1" Padding="20,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
          <TextBlock x:Name="lblTotal"  Text="$totalActions" FontSize="26" FontWeight="Bold" Foreground="#00C8FF" HorizontalAlignment="Center"/>
          <TextBlock Text="acciones"    FontSize="10" Foreground="#555555" HorizontalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Column="1" HorizontalAlignment="Center">
          <TextBlock Text="$highImpact"  FontSize="26" FontWeight="Bold" Foreground="#EF4444" HorizontalAlignment="Center"/>
          <TextBlock Text="impacto alto" FontSize="10" Foreground="#555555" HorizontalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Column="2" HorizontalAlignment="Center">
          <TextBlock Text="$medImpact"   FontSize="26" FontWeight="Bold" Foreground="#F59E0B" HorizontalAlignment="Center"/>
          <TextBlock Text="impacto medio" FontSize="10" Foreground="#555555" HorizontalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Column="3" HorizontalAlignment="Center">
          <TextBlock Text="$lowImpact"  FontSize="26" FontWeight="Bold" Foreground="#22C55E" HorizontalAlignment="Center"/>
          <TextBlock Text="impacto bajo" FontSize="10" Foreground="#555555" HorizontalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Lista de acciones -->
    <Border Grid.Row="2" Background="#0A0A0A" Margin="12,10,12,0"
            CornerRadius="8" BorderBrush="#2A2A2A" BorderThickness="1">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="4">
        <ItemsControl x:Name="icPlan" Padding="4"/>
      </ScrollViewer>
    </Border>

    <!-- Footer botones -->
    <Border Grid.Row="3" Background="#111111" BorderBrush="#2A2A2A"
            BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="Se creara un Punto de Restauracion de Windows antes de aplicar los cambios."
                   FontSize="11" Foreground="#555555" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="btnCancel" Content="Cancelar" Width="100" Height="32" Margin="0,0,10,0"
                  Background="#1E1E1E" Foreground="#CCCCCC" BorderBrush="#2A2A2A"
                  BorderThickness="1" Cursor="Hand" FontSize="12">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                        BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2A2A2A"/>
                    <Setter Property="BorderBrush" Value="#00C8FF"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
          <Button x:Name="btnConfirm" Content="Ejecutar optimizacion" Height="32" Padding="18,0"
                  Background="#00C8FF" Foreground="#0D0D0D" BorderThickness="0"
                  Cursor="Hand" FontSize="12" FontWeight="SemiBold">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#33D6FF"/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

    try {
        $xmlReader = [System.Xml.XmlReader]::Create(
            [System.IO.StringReader]::new($dialogXaml))
        $dialog = [Windows.Markup.XamlReader]::Load($xmlReader)
        $xmlReader.Close()
    } catch {
        # Si falla el dialog por cualquier razon, permitir ejecucion
        Write-Log "Modal de confirmacion no disponible: $_" "skip"
        return $true
    }

    $icPlan    = $dialog.FindName("icPlan")
    $btnConfirm= $dialog.FindName("btnConfirm")
    $btnCancel = $dialog.FindName("btnCancel")

    # Construir filas de acciones agrupadas por categoria
    $currentCat = ""
    foreach($action in ($plan | Sort-Object Category, Label)){
        if($action.Category -ne $currentCat){
            $currentCat = $action.Category
            $catBorder  = New-Object Windows.Controls.Border
            $catBorder.Padding = New-Object Windows.Thickness(10,8,10,4)
            $catBorder.Margin  = New-Object Windows.Thickness(0,4,0,0)
            $catTxt = New-Object Windows.Controls.TextBlock
            $catTxt.Text       = $action.Category.ToUpper()
            $catTxt.FontSize   = 10
            $catTxt.FontWeight = [Windows.FontWeights]::SemiBold
            $catTxt.Foreground = New-Brush "#555555"
            $catBorder.Child = $catTxt
            $icPlan.Items.Add($catBorder) | Out-Null
        }
        $icPlan.Items.Add((New-ActionRow $action)) | Out-Null
    }

    # Opcion de disco secundario para PageFile (F2.11: pregunta movida del hilo de optimizacion)
    $script:_pageFileCbx = $null
    if($script:_altDriveForPageFile -ne ""){
        $altRoot = $script:_altDriveForPageFile
        $pfBdr = New-Object Windows.Controls.Border
        $pfBdr.Padding         = New-Object Windows.Thickness(12,10,12,10)
        $pfBdr.Margin          = New-Object Windows.Thickness(0,6,0,0)
        $pfBdr.Background      = New-Brush "#091520"
        $pfBdr.BorderBrush     = New-Brush "#1A4A6A"
        $pfBdr.BorderThickness = New-Object Windows.Thickness(1)
        $pfBdr.CornerRadius    = New-Object Windows.CornerRadius(6)
        $pfStack = New-Object Windows.Controls.StackPanel
        $pfCbx = New-Object Windows.Controls.CheckBox
        $pfCbx.IsChecked  = $false
        $pfCbx.Foreground = New-Brush "#DDDDDD"
        $pfCbx.FontSize   = 12
        $pfCbx.Content    = "Mover PageFile al disco secundario ($altRoot)"
        $pfNote = New-Object Windows.Controls.TextBlock
        $pfNote.Text         = "Recomendado si $altRoot tiene mas espacio libre que $SYSDRIVE."
        $pfNote.FontSize     = 10
        $pfNote.Foreground   = New-Brush "#888888"
        $pfNote.Margin       = New-Object Windows.Thickness(22,4,0,0)
        $pfNote.TextWrapping = [Windows.TextWrapping]::Wrap
        $pfStack.Children.Add($pfCbx)  | Out-Null
        $pfStack.Children.Add($pfNote) | Out-Null
        $pfBdr.Child = $pfStack
        $icPlan.Items.Add($pfBdr) | Out-Null
        $script:_pageFileCbx = $pfCbx
    }

    # Resultado del dialogo
    $script:dialogResult = $false

    $btnConfirm.Add_Click({
        if($script:_pageFileCbx){
            $script:_pageFileMoveToAlt = ($script:_pageFileCbx.IsChecked -eq $true)
        }
        $script:dialogResult = $true
        $dialog.Close()
    })
    $btnCancel.Add_Click({
        $script:dialogResult = $false
        $dialog.Close()
    })

    $dialog.Owner = $window
    $dialog.ShowDialog() | Out-Null

    return $script:dialogResult
}

# ============================================================
# ANALISIS — MODO SOLO LECTURA (F2.13)
# ============================================================

function Show-AnalysisReport {
    $btnAnalyze.IsEnabled = $false
    $btnAnalyze.Content   = "Analizando..."
    Flush-UI

    $scoreResult = $null
    try { $scoreResult = Get-SystemScore } catch { Write-Log "Error en analisis: $_" "err" }

    $btnAnalyze.IsEnabled = $true
    $btnAnalyze.Content   = "Analizar"
    Flush-UI

    if(-not $scoreResult){ return }

    $score     = $scoreResult.Score
    $failing   = @($scoreResult.Items | Where-Object { -not $_.Ok })
    $earnedPts = ($scoreResult.Items | Where-Object { $_.Ok }  | Measure-Object -Property Weight -Sum).Sum
    $maxPts    = ($scoreResult.Items                            | Measure-Object -Property Weight -Sum).Sum
    $potGain   = ($failing                                      | Measure-Object -Property Weight -Sum).Sum
    $failCount = $failing.Count

    $newScore = if($maxPts -gt 0 -and $potGain -gt 0){
        [math]::Min(100, [math]::Round(($earnedPts + $potGain) / $maxPts * 100, 0))
    } else { $score }

    $scoreColor    = if($score -ge 75){ "#22C55E" } elseif($score -ge 45){ "#F59E0B" } else { "#EF4444" }
    $scoreLabel    = if($score -ge 75){ "Buen estado" } elseif($score -ge 45){ "Mejorable" } else { "Critico" }
    $potText       = if($potGain -gt 0){ "+$potGain pts" } else { "Maximo alcanzado" }
    $potSubtext    = if($potGain -gt 0){ "potencial: $newScore / 100" } else { "todo optimizado" }
    $potColor      = if($potGain -gt 0){ "#22C55E" } else { "#888888" }
    $failCountText = if($failCount -gt 0){ "$failCount mejora$(if($failCount -ne 1){'s'} else {''}) disponible$(if($failCount -ne 1){'s'})" } else { "Sistema optimizado" }

    $dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinBoost - Analisis del sistema"
        Width="560" Height="540" MinWidth="460" MinHeight="420"
        WindowStartupLocation="CenterOwner"
        Background="#0D0D0D" FontFamily="Segoe UI"
        ResizeMode="CanResize" ShowInTaskbar="False">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#161616" BorderBrush="#222222" BorderThickness="0,0,0,1" Padding="20,14">
      <StackPanel>
        <TextBlock Text="Analisis del sistema" FontSize="15" FontWeight="SemiBold" Foreground="#EEEEEE"/>
        <TextBlock Text="Solo lectura. No se aplica ningun cambio." FontSize="11" Foreground="#888888" Margin="0,3,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="1" Background="#111111" BorderBrush="#222222" BorderThickness="0,0,0,1" Padding="20,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="$score / 100" FontSize="38" FontWeight="Bold" Foreground="$scoreColor"/>
          <TextBlock Text="$scoreLabel" FontSize="12" Foreground="#888888" Margin="0,4,0,0"/>
          <TextBlock Text="$failCountText" FontSize="11" Foreground="#555555" Margin="0,2,0,0"/>
        </StackPanel>
        <Border Grid.Column="1" CornerRadius="7" Padding="18,10" VerticalAlignment="Center"
                Background="#0A1A0A" BorderBrush="#1A4A1A" BorderThickness="1">
          <StackPanel HorizontalAlignment="Center">
            <TextBlock Text="Potencial" FontSize="10" Foreground="#888888" HorizontalAlignment="Center"/>
            <TextBlock Text="$potText" FontSize="20" FontWeight="Bold"
                       Foreground="$potColor" HorizontalAlignment="Center" Margin="0,3,0,0"/>
            <TextBlock Text="$potSubtext" FontSize="10" Foreground="#555555"
                       HorizontalAlignment="Center" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
    <Border Grid.Row="2" Background="#0A0A0A" Margin="12,10,12,0"
            CornerRadius="8" BorderBrush="#222222" BorderThickness="1">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="4">
        <ItemsControl x:Name="icAnalysis" Padding="4"/>
      </ScrollViewer>
    </Border>
    <Border Grid.Row="3" Background="#111111" BorderBrush="#222222" BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="lblAnalNote" Grid.Column="0"
                   FontSize="11" Foreground="#555555" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="btnAnalClose" Content="Cerrar" Width="90" Height="32" Margin="0,0,10,0"
                  Background="#1E1E1E" Foreground="#CCCCCC" BorderBrush="#333333"
                  BorderThickness="1" Cursor="Hand" FontSize="12">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                        BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2A2A2A"/>
                    <Setter Property="BorderBrush" Value="#555555"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
          <Button x:Name="btnAnalSelect" Height="32" Padding="18,0"
                  Background="#00C8FF" Foreground="#0D0D0D" BorderThickness="0"
                  Cursor="Hand" FontSize="12" FontWeight="SemiBold">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border Background="{TemplateBinding Background}" CornerRadius="6"
                        Padding="{TemplateBinding Padding}" Opacity="{TemplateBinding Opacity}">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#33D6FF"/>
                  </Trigger>
                  <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="0.35"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

    $dlg = $null
    try {
        $xmlRdr = [System.Xml.XmlReader]::Create([System.IO.StringReader]$dlgXaml)
        $dlg    = [Windows.Markup.XamlReader]::Load($xmlRdr)
        $xmlRdr.Close()
    } catch {
        Write-Log "Error al cargar dialogo de analisis: $_" "err"
        return
    }

    $icAnal      = $dlg.FindName("icAnalysis")
    $btnClose    = $dlg.FindName("btnAnalClose")
    $btnSelect   = $dlg.FindName("btnAnalSelect")
    $lblNote     = $dlg.FindName("lblAnalNote")

    if($failCount -eq 0){
        $lblNote.Text      = "El sistema ya esta optimizado."
        $btnSelect.Content = "Sin mejoras pendientes"
        $btnSelect.IsEnabled = $false
    } else {
        $lblNote.Text      = "Los cambios aplicados se pueden revertir desde Historial."
        $btnSelect.Content = "Seleccionar recomendadas ($failCount)"
    }

    $catColors = @{
        "Rendimiento" = "#00C8FF"
        "Privacidad"  = "#A855F7"
        "Red"         = "#22C55E"
        "Servicios"   = "#F59E0B"
    }

    if($failCount -gt 0){
        $currentCat = ""
        foreach($item in ($failing | Sort-Object Category, Label)){
            if($item.Category -ne $currentCat){
                $currentCat = $item.Category
                $catBdr = New-Object Windows.Controls.Border
                $catBdr.Padding = New-Object Windows.Thickness(10,10,10,3)
                $catBdr.Margin  = New-Object Windows.Thickness(0,4,0,0)
                $catTxt = New-Object Windows.Controls.TextBlock
                $catTxt.Text       = $item.Category.ToUpper()
                $catTxt.FontSize   = 10
                $catTxt.FontWeight = [Windows.FontWeights]::SemiBold
                $catCol = if($catColors.ContainsKey($item.Category)){ $catColors[$item.Category] } else { "#777777" }
                $catTxt.Foreground = New-Brush $catCol
                $catBdr.Child = $catTxt
                $icAnal.Items.Add($catBdr) | Out-Null
            }

            $rowBdr = New-Object Windows.Controls.Border
            $rowBdr.Padding         = New-Object Windows.Thickness(10,7,10,7)
            $rowBdr.Margin          = New-Object Windows.Thickness(0,1,0,0)
            $rowBdr.Background      = New-Brush "#161616"
            $rowBdr.CornerRadius    = New-Object Windows.CornerRadius(5)

            $rowGrid = New-Object Windows.Controls.Grid
            $cdStar  = New-Object Windows.Controls.ColumnDefinition
            $cdStar.Width  = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
            $cdFixed = New-Object Windows.Controls.ColumnDefinition
            $cdFixed.Width = [Windows.GridLength]::new(64)
            $rowGrid.ColumnDefinitions.Add($cdStar)  | Out-Null
            $rowGrid.ColumnDefinitions.Add($cdFixed) | Out-Null

            $lblRow = New-Object Windows.Controls.TextBlock
            $lblRow.Text              = $item.Label
            $lblRow.FontSize          = 12
            $lblRow.Foreground        = New-Brush "#DDDDDD"
            $lblRow.VerticalAlignment = [Windows.VerticalAlignment]::Center
            [Windows.Controls.Grid]::SetColumn($lblRow, 0)

            $ptsBdr = New-Object Windows.Controls.Border
            $ptsBdr.CornerRadius        = New-Object Windows.CornerRadius(4)
            $ptsBdr.Padding             = New-Object Windows.Thickness(6,3,6,3)
            $ptsBdr.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
            $ptsBdr.VerticalAlignment   = [Windows.VerticalAlignment]::Center
            $ptsBdr.Background          = New-Brush "#1A1200"
            $ptsBdr.BorderBrush         = New-Brush "#F59E0B"
            $ptsBdr.BorderThickness     = New-Object Windows.Thickness(1)
            $ptsTxt = New-Object Windows.Controls.TextBlock
            $ptsTxt.Text       = "+$($item.Weight) pts"
            $ptsTxt.FontSize   = 10
            $ptsTxt.Foreground = New-Brush "#F59E0B"
            $ptsBdr.Child = $ptsTxt
            [Windows.Controls.Grid]::SetColumn($ptsBdr, 1)

            $rowGrid.Children.Add($lblRow) | Out-Null
            $rowGrid.Children.Add($ptsBdr) | Out-Null
            $rowBdr.Child = $rowGrid
            $icAnal.Items.Add($rowBdr) | Out-Null
        }
    } else {
        $okBdr = New-Object Windows.Controls.Border
        $okBdr.Padding = New-Object Windows.Thickness(20,40,20,20)
        $okTxt = New-Object Windows.Controls.TextBlock
        $okTxt.Text                = "No se encontraron mejoras pendientes. Sistema ya optimizado."
        $okTxt.FontSize            = 12
        $okTxt.Foreground          = New-Brush "#22C55E"
        $okTxt.TextWrapping        = [Windows.TextWrapping]::Wrap
        $okTxt.TextAlignment       = [Windows.TextAlignment]::Center
        $okTxt.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $okBdr.Child = $okTxt
        $icAnal.Items.Add($okBdr) | Out-Null
    }

    $btnClose.Add_Click({ $dlg.Close() })

    $capturedFailing = $failing
    $btnSelect.Add_Click({
        foreach($fi in $capturedFailing){
            if($checks.ContainsKey($fi.Id)){
                $checks[$fi.Id].IsChecked = $true
            }
        }
        $dlg.Close()
        Set-ActiveNav 0
        Write-Log "$($capturedFailing.Count) optimizaciones recomendadas preseleccionadas. Revisa y pulsa Optimizar." "info"
        Flush-UI
    })

    $dlg.Owner = $window
    $dlg.ShowDialog() | Out-Null
}

# ============================================================
# EJECUTAR — FUNCIONES EXTRAIDAS (F2.5)
# ============================================================

function Invoke-CleanupTweaks {
    param([hashtable]$sel)
    Write-Log "LIMPIEZA DE ARCHIVOS" "head"; Set-Progress 8 "Limpiando temporales..."
    if($sel["TempUser"])  { $script:freed += Remove-Dir $env:TEMP "Temp usuario"; $script:_optApplied++ }
    if($sel["TempSys"])   { $script:freed += Remove-Dir "$SYSDRIVE\Windows\Temp" "Temp sistema"; $script:_optApplied++ }
    if($sel["Prefetch"]) {
        if($HAS_SSD) { $script:freed += Remove-Dir "$SYSDRIVE\Windows\Prefetch" "Prefetch"; $script:_optApplied++ }
        else         { Write-Log "Prefetch omitido (requiere SSD)" "skip"; $script:_optSkipped++ }
    }
    if($sel["WinUpdate"]) {
        Stop-Service -Name wuauserv -Force -EA SilentlyContinue
        $script:freed += Remove-Dir "$SYSDRIVE\Windows\SoftwareDistribution\Download" "WUpdate cache"
        Start-Service -Name wuauserv -EA SilentlyContinue
        $script:_optApplied++
    }
    if($sel["Browsers"]) {
        Set-Progress 14 "Cache navegadores..."
        @(@{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache";N="Chrome"},
          @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache";N="Edge"},
          @{P="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache";N="Brave"},
          @{P="$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache";N="Opera"},
          @{P="$env:APPDATA\Mozilla\Firefox\Profiles";N="Firefox"}) |
        ForEach-Object { $script:freed += Remove-Dir $_.P "Cache $($_.N)" }
        $script:_optApplied++
    }
    if($sel["Thumb"])   { $script:freed += Remove-Dir "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" "Thumbnails"; $script:_optApplied++ }
    if($sel["Recycle"]) {
        try   { Clear-RecycleBin -Force -EA SilentlyContinue; Write-Log "Papelera vaciada" "ok"; $script:_optApplied++ }
        catch { Write-Log "Papelera: archivos en uso" "skip" }
    }
    if($sel["EventLogs"]) {
        Set-Progress 18 "Logs de eventos..."
        Get-WinEvent -ListLog * -EA SilentlyContinue |
            Where-Object { $_.IsEnabled -and $_.LogName -ne "Security" } |
            ForEach-Object { try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch {} }
        Write-Log "Logs de eventos limpiados (Security excluido)" "ok"
        $script:_optApplied++
    }
    $mb = [math]::Round($script:freed, 1)
    Write-Log "Total liberado: $mb MB" "ok"
    $lblSpaceFreed.Text = "$mb MB liberados"
}

function Invoke-RegistryTweaks {
    param([hashtable]$sel)
    Write-Log "REGISTRO" "head"; Set-Progress 44 "Tweaks de registro..."
    $gp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if($sel["GPUPrio"]) {
        Set-Reg $gp "GPU Priority" DWord 8
        Set-Reg $gp "Priority" DWord 6
        Set-Reg $gp "Scheduling Category" String "High"
        Set-Reg $gp "SFIO Priority" String "High"
        Set-Reg $gp "Background Only" String "False"
        $script:_optApplied++
    }
    if($sel["PowerThrot"]) { Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" DWord 1; $script:_optApplied++ }
    if($sel["MouseAccel"]) {
        Set-Reg "HKCU:\Control Panel\Mouse" "MouseSpeed" String "0"
        Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold1" String "0"
        Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold2" String "0"
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" "MouseDataQueueSize" DWord 20
        $script:_optApplied++
    }
    if($sel["GameDVR"] -or $sel["GameMode"]) { Set-Progress 52 "Game DVR..."; Write-Log "GAME DVR / XBOX" "head" }
    if($sel["GameDVR"]) {
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" DWord 0
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" DWord 2
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" DWord 1
        Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" DWord 0
        $script:_optApplied++
    }
    if($sel["GameMode"]) {
        Set-Reg "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" DWord 0
        Set-Reg "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" DWord 0
        $script:_optApplied++
    }
    if($sel["Telemetry"] -or $sel["Cortana"] -or $sel["Notif"] -or $sel["Tasks"]) { Set-Progress 60 "Privacidad..."; Write-Log "PRIVACIDAD / TELEMETRIA" "head" }
    if($sel["Telemetry"]) {
        Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" DWord 0
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" DWord 0
        $script:_optApplied++
    }
    if($sel["Cortana"]) { Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" DWord 0; $script:_optApplied++ }
    if($sel["Notif"])   { Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" "ToastEnabled" DWord 0; $script:_optApplied++ }
    if($sel["Tasks"]) {
        $telTasks = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        )
        foreach($t in $telTasks) {
            try { Disable-ScheduledTask -TaskPath (Split-Path $t) -TaskName (Split-Path $t -Leaf) -EA SilentlyContinue | Out-Null } catch {}
        }
        Write-Log "Tareas telemetria deshabilitadas" "ok"
        $script:_optApplied++
    }
}

function Invoke-NetworkTweaks {
    param([hashtable]$sel)
    if(-not ($sel["Nagle"] -or $sel["TCP"] -or $sel["DNS"] -or $sel["DNSFlush"] -or $sel["DisableIPv6"])) { return }
    Set-Progress 70 "Red..."; Write-Log "RED" "head"
    if($sel["DNS"] -or $sel["DisableIPv6"]) { Save-NetBackup }
    if($sel["TCP"]) { Save-NetshBackup }
    if($sel["Nagle"]) {
        $nagleCount = 0
        Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA SilentlyContinue | ForEach-Object {
            $ip = Get-ItemProperty -Path $_.PSPath -Name "DhcpIPAddress" -EA SilentlyContinue
            if($ip -and $ip.DhcpIPAddress -and $ip.DhcpIPAddress -ne "0.0.0.0") {
                Set-Reg $_.PSPath "TcpAckFrequency" DWord 1
                Set-Reg $_.PSPath "TCPNoDelay" DWord 1
                $nagleCount++
            }
        }
        Write-Log "Nagle OFF en $nagleCount adaptador(es)" "ok"
        $script:_optApplied++
    }
    if($sel["TCP"]) { netsh int tcp set global autotuninglevel=normal 2>$null|Out-Null; netsh int tcp set global chimney=disabled 2>$null|Out-Null; netsh int tcp set global rss=enabled 2>$null|Out-Null; netsh int tcp set global fastopen=enabled 2>$null|Out-Null; Write-Log "TCP/IP optimizado" "ok"; $script:_optApplied++ }
    if($sel["DNS"]) {
        $dnsIdx = $cboDNSProvider.SelectedIndex
        if($dnsIdx -lt 0 -or $dnsIdx -ge $script:dnsProviders.Count) { $dnsIdx = 0 }
        $dnsProv = $script:dnsProviders[$dnsIdx]
        $dn = 0
        Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
            try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses($dnsProv.Primary, $dnsProv.Secondary) -EA Stop; $dn++ } catch {}
        }
        Write-Log "DNS $($dnsProv.Name) ($($dnsProv.Primary) / $($dnsProv.Secondary)) en $dn adaptador(es)" "ok"
        $script:_optApplied++
    }
    if($sel["DNSFlush"]) { ipconfig /flushdns 2>$null|Out-Null; Write-Log "Cache DNS limpiada" "ok"; $script:_optApplied++ }
    if($sel["DisableIPv6"]) {
        Set-Progress 75 "Preferencia IPv4..."
        Write-Log "IPv4 PREFERIDO SOBRE IPv6" "head"
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" DWord 0x20
        Write-Log "IPv4 preferido sobre IPv6 (DisabledComponents=0x20, IPv6 activo)" "ok"
        $script:_optApplied++
    }
}

function Invoke-ServiceTweaks {
    param([hashtable]$sel)
    if(-not ($sel["SvcXbox"] -or $sel["SvcDiag"] -or $sel["SvcWER"] -or $sel["SvcSysMain"] -or $sel["SvcMaps"] -or $sel["SvcFax"] -or $sel["SvcWSearch"])) { return }
    Set-Progress 82 "Servicios..."; Write-Log "SERVICIOS" "head"
    if($sel["SvcXbox"])   { Disable-Svc "XblAuthManager" "Xbox Live Auth"; Disable-Svc "XblGameSave" "Xbox GameSave"; Disable-Svc "XboxNetApiSvc" "Xbox Networking"; $script:_optApplied++ }
    if($sel["SvcDiag"])   { Disable-Svc "DiagTrack" "DiagTrack"; $script:_optApplied++ }
    if($sel["SvcWER"])    { Disable-Svc "WerSvc" "Windows Error Reporting"; $script:_optApplied++ }
    if($sel["SvcSysMain"]) {
        if($HAS_SSD) { Disable-Svc "SysMain" "SysMain/Superfetch"; $script:_optApplied++ }
        else         { Write-Log "SysMain/Superfetch omitido (requiere SSD)" "skip"; $script:_optSkipped++ }
    }
    if($sel["SvcMaps"])   { Disable-Svc "MapsBroker" "Maps Broker"; Disable-Svc "lfsvc" "Geolocation"; $script:_optApplied++ }
    if($sel["SvcFax"])    { Disable-Svc "Fax" "Fax"; Disable-Svc "RemoteRegistry" "Remote Registry"; $script:_optApplied++ }
    if($sel["SvcWSearch"]) {
        if($HAS_SSD) { Disable-Svc "WSearch" "Windows Search (indexado)"; $script:_optApplied++ }
        else         { Write-Log "Windows Search omitido (requiere SSD)" "skip"; $script:_optSkipped++ }
    }
}

# ============================================================
# INVOKE-OPTIMIZEFINISH
# Ejecuta el tramo final de la optimizacion: efectos visuales,
# progreso 100, habilitacion de botones, score y modal comparativa.
# Llamado en forma sincrona (ruta HDD/sin-TRIM) o desde el
# DispatcherTimer de TRIM cuando el Start-Job termina (ruta async SSD).
# ============================================================
$script:trimJob      = $null
$script:trimTimer    = $null
$script:trimSel      = $null
$script:trimJobStart = $null
$script:_optApplied        = 0     # F2.6: cambios aplicados en esta sesion
$script:_optSkipped        = 0     # F2.6: condiciones no cumplidas (hardware, etc.)
$script:_altDriveForPageFile = ""    # F2.11: disco secundario detectado en Build-ActionPlan
$script:_pageFileMoveToAlt   = $false # F2.11: decision del usuario en el modal de confirmacion
$script:_pageFileCbx         = $null  # F2.11: referencia al CheckBox del modal
$script:_cancelOptimize      = $false # F2.12: flag de cancelacion entre fases de optimizacion
$script:diskJob              = $null  # F2.14: job de escaneo de espacio en disco
$script:diskTimer            = $null  # F2.14: timer de polling del job

function Invoke-OptimizeFinish {
    param([hashtable]$sel)

    if($sel["Visual"]){Set-Progress 96 "Efectos visuales..."; Write-Log "EFECTOS VISUALES" "head"
        Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" DWord 2
        Set-Reg "HKCU:\Control Panel\Desktop" "FontSmoothing" String "2"
        if($totalRAM-le8){Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" DWord 0;Write-Log "Transparencia OFF (RAM baja)" "ok"}
        $script:_optApplied++
    }

    $wasCancelled = $script:_cancelOptimize
    Set-Progress 100 $(if($wasCancelled){ "Detenido" } else { "Completado" })
    if($wasCancelled){
        Write-Log "Optimizacion detenida. Los cambios aplicados hasta este punto permanecen activos." "info"
    } else {
        Write-Log "Optimizacion completada. Reinicia para aplicar todos los cambios." "ok"
    }
    $lblLogStatus.Text = if($wasCancelled){ "Detenido" } else { "Completado" }
    $btnRun.IsEnabled=$true; $btnSelAll.IsEnabled=$true; $btnSelNone.IsEnabled=$true
    $btnCancelOpt.Visibility = [Windows.Visibility]::Collapsed
    $script:_cancelOptimize  = $false
    Flush-UI

    # Recalcular score y metadata en background sin bloquear la UI
    $script:scoreBeforeCapture = $script:scoreBefore
    $window.Dispatcher.BeginInvoke([action]{
        try {
            $scoreResultAfter  = Get-SystemScore
            $script:scoreAfter = $scoreResultAfter.Score
            Update-ScorePanel  -scoreResult $scoreResultAfter
            $hdrColor = if($script:scoreAfter -ge 75){ "#22C55E" }
                        elseif($script:scoreAfter -ge 45){ "#F59E0B" }
                        else { "#EF4444" }
            $scoreBar.Background     = New-Brush $hdrColor
            $scoreBar.Opacity        = [math]::Max(0.15, $script:scoreAfter / 100)
            $scoreWidget.BorderBrush = New-Brush $hdrColor
            Animate-ScoreCount -from $script:scoreBeforeCapture `
                               -to   $script:scoreAfter -durationMs 900
            $delta = $script:scoreAfter - $script:scoreBeforeCapture
            Show-ScoreDelta -delta $delta
            $sign = if($delta -ge 0){ "+" } else { "" }
            Write-Log "Score de salud: $($script:scoreBeforeCapture) -> $($script:scoreAfter)  ($sign$delta pts)" `
                      $(if($delta -ge 0){ "ok" } else { "info" })
            $skipLine = if($script:_optSkipped -gt 0){ ", $($script:_optSkipped) condiciones no cumplidas" } else { "" }
            Write-Log "RESUMEN: $($script:_optApplied) cambios aplicados$skipLine" "head"
            Save-SessionMetadata -freedMB    ([int]$script:freed) `
                                 -scoreBefore $script:scoreBeforeCapture `
                                 -scoreAfter  $script:scoreAfter `
                                 -preset "Manual"
            Show-ToastNotification -Title "WinBoost" `
                -Message "Optimizacion completada. $($script:_optApplied) cambios aplicados. Score: $($script:scoreAfter)/100 ($sign$delta pts)"
        } catch {}

        $script:snapshotAfter   = $null
        $script:snapshotCompare = $null
        try {
            $script:snapshotAfter   = Get-SystemSnapshot -Score $script:scoreAfter
            $script:snapshotCompare = Compare-Snapshots -Before $script:snapshotBefore `
                                                        -After  $script:snapshotAfter
        } catch {}

        $cmpResult = "later"
        try { $cmpResult = Show-CompareDialog } catch {}
        if ($cmpResult -eq "restart") {
            Restart-Computer -Force
        } elseif ($cmpResult -eq "log") {
            Set-ActiveNav 1
            Flush-UI
        }
    }, [Windows.Threading.DispatcherPriority]::Background) | Out-Null
}

$btnRun.Add_Click({
    # --- Gate Pro: tweaks de registro y servicios ---
    if (Lock-ProFeature "Tweaks de registro y servicios") { return }

    $sel=@{}; foreach($k in $checks.Keys){$sel[$k]=[bool]$checks[$k].IsChecked}

    # --- Verificar que hay algo seleccionado ---
    $anySelected = $sel.Values | Where-Object { $_ -eq $true }
    if(-not $anySelected){
        [Windows.MessageBox]::Show(
            "No hay ninguna opcion seleccionada.`nSelecciona al menos una opcion antes de ejecutar.",
            "WinBoost v$VERSION",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    # --- Modal de confirmacion pre-ejecucion (Modulo 2) ---
    $plan      = Build-ActionPlan -sel $sel
    $confirmed = Show-ConfirmDialog -plan $plan
    if(-not $confirmed){ return }

    # --- Capturar score ANTES de optimizar (Modulo 3A) ---
    $script:scoreBefore = 0
    try { $script:scoreBefore = (Get-SystemScore).Score } catch {}

    # --- Snapshot de estado ANTES (Modulo 11A) ---
    $script:snapshotBefore = $null
    try { $script:snapshotBefore = Get-SystemSnapshot -Score $script:scoreBefore } catch {}

    # --- A partir de aqui el usuario confirmo ---
    $btnRun.IsEnabled=$false; $btnSelAll.IsEnabled=$false; $btnSelNone.IsEnabled=$false
    $script:_cancelOptimize  = $false
    $btnCancelOpt.IsEnabled  = $true
    $btnCancelOpt.Content    = "Detener"
    $btnCancelOpt.Visibility = [Windows.Visibility]::Visible
    $lblSpaceFreed.Text=""; $script:freed=0; $script:logLines=@(); $script:_optApplied=0; $script:_optSkipped=0
    $rtbLog.Document.Blocks.Clear()
    Set-ActiveNav 1; $lblLogStatus.Text="Ejecutando..."; Flush-UI

    # --- Iniciar sesion de backup para esta ejecucion ---
    New-BackupSession | Out-Null

    # Siempre crear restore point antes de cualquier cambio al sistema (F0.1)
    Set-Progress 2 "Creando punto de restauracion (puede tardar 30-60 s)..."
    Write-Log "PUNTO DE RESTAURACION" "head"
    try {
        Enable-ComputerRestore -Drive "$SYSDRIVE\" -EA SilentlyContinue
        Checkpoint-Computer -Description "WinBoost pre-optimizacion" -RestorePointType "MODIFY_SETTINGS" -EA Stop
        Write-Log "Punto de restauracion creado" "ok"
    } catch {
        Write-Log "Advertencia: no se pudo crear el punto de restauracion. Continuando de todas formas." "skip"
    }
    Flush-UI

    Invoke-CleanupTweaks $sel
    if($script:_cancelOptimize){ Write-Log "Optimizacion cancelada por el usuario." "skip"; Invoke-OptimizeFinish -sel $sel; return }

    if($sel["Power"]){Set-Progress 30 "Plan de energia..."; Write-Log "PLAN DE ENERGIA" "head"
        Save-PowerPlanBackup
        if(-not $IS_LAPTOP){$g="e9a42b02-d5df-448d-aa00-03f14749eb61"
            if(-not(powercfg /list|Select-String $g)){powercfg -duplicatescheme $g 2>$null}
            $pl=powercfg /list|Select-String $g
            if($pl){$guid=($pl.ToString() -split '\s+'|Where-Object{$_ -match '^[0-9a-f-]{36}$'})[0];powercfg /setactive $guid;Write-Log "Ultimate Performance activado" "ok"}
            else{powercfg /setactive SCHEME_MIN;Write-Log "Alto Rendimiento activado" "ok"}
            powercfg /hibernate off;Write-Log "Hibernate desactivado" "ok"}
        else{powercfg /setactive SCHEME_MIN;Write-Log "Alto Rendimiento activado (laptop)" "ok"}
        powercfg /change standby-timeout-ac 0
        $script:_optApplied++}

    if($sel["HPET"]){Set-Progress 36 "HPET..."; Write-Log "HPET / TIMER" "head"
        bcdedit /deletevalue useplatformclock 2>$null|Out-Null
        bcdedit /set useplatformtick yes 2>$null|Out-Null
        bcdedit /set disabledynamictick yes 2>$null|Out-Null
        Write-Log "HPET deshabilitado - TSC activado" "ok"
        $script:_optApplied++}

    Invoke-RegistryTweaks $sel
    if($script:_cancelOptimize){ Write-Log "Optimizacion cancelada por el usuario." "skip"; Invoke-OptimizeFinish -sel $sel; return }

    Invoke-NetworkTweaks $sel

    Invoke-ServiceTweaks $sel
    if($script:_cancelOptimize){ Write-Log "Optimizacion cancelada por el usuario." "skip"; Invoke-OptimizeFinish -sel $sel; return }

    if($sel["FastStartup"]){Set-Progress 88 "Fast Startup..."; Write-Log "FAST STARTUP" "head"
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" DWord 0
        powercfg /hibernate off 2>$null | Out-Null
        Write-Log "Fast Startup deshabilitado (HiberbootEnabled=0 + hibernate off)" "ok"
        $script:_optApplied++
    }

    # ----------------------------------------------------------
    # PAGEFILE
    # ----------------------------------------------------------
    if($sel["PageFile"]){Set-Progress 91 "Optimizando PageFile..."; Write-Log "PAGEFILE" "head"
        # Backup del estado actual antes de cualquier modificacion
        Save-PageFileBackup
        try {
            # Calcular min/max optimos: min=max(4096, RAM_MB), max=max(8192, RAM_MB*2)
            $pfMin = [math]::Max(4096, [math]::Min($totalRAM * 1024, 8192))
            $pfMax = [math]::Max(8192, [math]::Min($totalRAM * 1024 * 2, 16384))

            # Destino del PageFile: decidido en el modal de confirmacion (F2.11)
            $targetDrive = $SYSDRIVE
            if($script:_altDriveForPageFile -ne "" -and $script:_pageFileMoveToAlt){
                $targetDrive = $script:_altDriveForPageFile
            }

            # Deshabilitar gestion automatica
            $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
            if($cs.AutomaticManagedPagefile){
                Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -EA Stop
                Write-Log "Gestion automatica de PageFile desactivada" "ok"
            }

            # CREAR el nuevo PageFile PRIMERO (antes de borrar los existentes)
            $pfPath = "$targetDrive\pagefile.sys"
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name        = $pfPath
                InitialSize = [uint32]$pfMin
                MaximumSize = [uint32]$pfMax
            } -EA Stop | Out-Null

            # Verificar que el nuevo PageFile existe antes de borrar los anteriores
            $verify = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue |
                          Where-Object { $_.Name -eq $pfPath }
            if(-not $verify){
                throw "Verificacion fallida: el nuevo PageFile no aparece en Win32_PageFileSetting"
            }

            # Ahora borrar los PageFiles anteriores (excepto el recien creado)
            $existing = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue
            foreach($pf in $existing){
                if($pf.Name -ne $pfPath){
                    try { Remove-CimInstance -InputObject $pf -EA SilentlyContinue } catch {}
                }
            }

            Write-Log "PageFile: $pfPath  min=$pfMin MB  max=$pfMax MB" "ok"
            Write-Log "Cambio efectivo tras reinicio" "info"
            $script:_optApplied++
        } catch {
            # Rollback: reactivar gestion automatica para no dejar el sistema sin pagefile
            try {
                $cs2 = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
                if($cs2 -and -not $cs2.AutomaticManagedPagefile){
                    Set-CimInstance -InputObject $cs2 -Property @{AutomaticManagedPagefile=$true} -EA SilentlyContinue
                    Write-Log "PageFile: se restauro gestion automatica tras error" "skip"
                }
            } catch {}
            Write-Log "Error configurando PageFile: $_" "err"
        }
    }

    # ----------------------------------------------------------
    # TRIM / DESFRAG SCHEDULE
    # ----------------------------------------------------------
    if($sel["TrimDesfrag"]){Set-Progress 94 "TRIM / Desfrag schedule..."; Write-Log "TRIM / DESFRAG" "head"
        try {
            if($HAS_SSD){
                # SSD: asegurar que TRIM este habilitado y forzar una pasada inmediata
                $trimState = (fsutil behavior query DisableDeleteNotify 2>$null) -join ""
                if($trimState -match "= 1"){
                    fsutil behavior set DisableDeleteNotify 0 2>$null | Out-Null
                    Write-Log "TRIM re-habilitado (DisableDeleteNotify=0)" "ok"
                } else {
                    Write-Log "TRIM ya estaba habilitado" "ok"
                }

                # Habilitar y configurar la tarea programada de Optimize-Volume (semanal)
                $taskName = "Microsoft\Windows\Defrag\ScheduledDefrag"
                try {
                    Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -EA Stop | Out-Null
                    Write-Log "Tarea ScheduledDefrag habilitada (TRIM semanal automatico)" "ok"
                } catch { Write-Log "No se pudo habilitar tarea de TRIM: $_" "skip" }

                # Ejecutar TRIM via Start-Job para no bloquear la UI (F0.12)
                $ssdVolumes = Get-PhysicalDisk -EA SilentlyContinue |
                    Where-Object { $_.MediaType -eq "SSD" } |
                    Get-Disk -EA SilentlyContinue |
                    Get-Partition -EA SilentlyContinue |
                    Get-Volume -EA SilentlyContinue |
                    Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }

                if($ssdVolumes){
                    $trimLetters         = @($ssdVolumes | ForEach-Object { $_.DriveLetter })
                    $script:trimSel      = $sel
                    $script:trimJobStart = Get-Date
                    $script:trimJob = Start-Job -ScriptBlock {
                        param($letters)
                        foreach($dl in $letters){
                            try {
                                Optimize-Volume -DriveLetter $dl -ReTrim -NormalPriority -EA SilentlyContinue
                                [PSCustomObject]@{ DriveLetter=$dl; OK=$true }
                            } catch {
                                [PSCustomObject]@{ DriveLetter=$dl; OK=$false }
                            }
                        }
                    } -ArgumentList (,$trimLetters)

                    Set-Progress 94 "TRIM en progreso (puede tardar varios minutos)..."
                    Write-Log "TRIM lanzado en background para $($trimLetters.Count) volumen(es) SSD" "info"
                    Flush-UI

                    $script:trimTimer          = New-Object Windows.Threading.DispatcherTimer
                    $script:trimTimer.Interval = [TimeSpan]::FromSeconds(1)
                    $script:trimTimer.Add_Tick({
                        if($script:_cancelOptimize){
                            $script:trimTimer.Stop()
                            Remove-Job $script:trimJob -Force -EA SilentlyContinue
                            $script:trimJob = $null
                            Write-Log "Optimizacion cancelada durante TRIM." "skip"
                            Invoke-OptimizeFinish -sel $script:trimSel
                            return
                        }
                        if($script:trimJob.State -eq "Running"){
                            $elapsed = [int]((Get-Date) - $script:trimJobStart).TotalSeconds
                            Set-Progress 94 "TRIM en progreso... $elapsed s"
                            return
                        }
                        $script:trimTimer.Stop()
                        try {
                            $trimResults = Receive-Job $script:trimJob -EA SilentlyContinue
                            foreach($r in $trimResults){
                                if($r.OK){ Write-Log "TRIM completado en $($r.DriveLetter):" "ok" }
                                else     { Write-Log "TRIM omitido en $($r.DriveLetter):" "skip" }
                            }
                            if(@($trimResults | Where-Object { $_.OK }).Count -gt 0){ $script:_optApplied++ }
                        } catch {}
                        Remove-Job $script:trimJob -Force -EA SilentlyContinue
                        $script:trimJob = $null
                        Invoke-OptimizeFinish -sel $script:trimSel
                    })
                    $script:trimTimer.Start()
                    return  # UI queda libre; el timer completa la optimizacion al terminar el job
                }

            } else {
                # HDD: habilitar la tarea de desfragmentacion semanal
                try {
                    Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -EA Stop | Out-Null
                    Write-Log "Desfragmentacion semanal habilitada (HDD)" "ok"
                    $script:_optApplied++
                } catch { Write-Log "No se pudo habilitar tarea de desfrag: $_" "skip" }

                # Verificar que Optimize-Volume este configurado para cada volumen HDD fijo
                $hddVolumes = Get-Volume -EA SilentlyContinue |
                    Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter }
                foreach($vol in $hddVolumes){
                    try {
                        $defragInfo = Get-StorageSetting -EA SilentlyContinue
                        Write-Log "HDD $($vol.DriveLetter): desfrag programado habilitado" "ok"
                    } catch {}
                }
            }
        } catch {
            Write-Log "Error en TRIM/Desfrag: $_" "err"
        }
    }

    # Ruta sin TRIM async (HDD, o SSD sin volumenes, o TrimDesfrag no seleccionado)
    Invoke-OptimizeFinish -sel $sel
})


# ============================================================
# CHECK DE ACTUALIZACIONES (GitHub JSON)
# URL del version.json en tu GitHub Gist o repo.
# Campos esperados: version, releaseUrl, downloadUrl, sha256, changelog
# ============================================================
$UPDATE_CHECK_URL        = "https://raw.githubusercontent.com/tDallagio/OptimizarPC/main/version.json"
$script:updateReleaseUrl = ""
$script:updateMeta       = $null

function Check-ForUpdates {
    try {
        $response  = Invoke-RestMethod -Uri $UPDATE_CHECK_URL -TimeoutSec 5 -ErrorAction Stop
        $remoteVer = [version]($response.version -replace "[^0-9.]","")
        $localVer  = [version]($VERSION -replace "[^0-9.]","")
        $script:updateReleaseUrl = $response.releaseUrl

        if ($remoteVer -gt $localVer) {
            $script:updateMeta = [PSCustomObject]@{
                Version     = [string]$response.version
                Changelog   = if ($response.changelog)   { [string]$response.changelog }   else { "Sin detalles disponibles." }
                ReleaseUrl  = if ($response.releaseUrl)  { [string]$response.releaseUrl }  else { "" }
                DownloadUrl = if ($response.downloadUrl) { [string]$response.downloadUrl } else { "" }
                Sha256      = if ($response.sha256)      { ([string]$response.sha256).ToUpper() } else { "" }
            }
            $badgeUpdate.Visibility = "Visible"
            $lblUpdateBadge.Text    = "v$($response.version) disponible"
        }
    } catch {
        # Sin conexion o URL invalida: ignorar silenciosamente
    }
}

# Click en el badge: muestra changelog y opciones de descarga
$badgeUpdate.Add_MouseLeftButtonUp({
    if ($script:updateMeta) {
        Show-ChangelogDialog
    } elseif ($script:updateReleaseUrl) {
        Start-Process $script:updateReleaseUrl
    }
})


# ============================================================
# BENCHMARK RAPIDO DE DISCO
# ============================================================
$script:benchWritePre = 0; $script:benchReadPre = 0

$btnBenchmark.Add_Click({
    $btnBenchmark.IsEnabled = $false
    $lblBenchStatus.Text    = "Midiendo escritura..."
    Flush-UI
    try {
        $testFile  = "$env:TEMP\OptimizarPC_bench_$(Get-Random).tmp"
        $sizeMB    = 100
        $chunkData = New-Object byte[] (1MB)
        [System.Random]::new().NextBytes($chunkData)

        # ---- ESCRITURA (WriteThrough: bypasa cache del SO) ----
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = [System.IO.FileStream]::new(
                  $testFile,
                  [System.IO.FileMode]::Create,
                  [System.IO.FileAccess]::Write,
                  [System.IO.FileShare]::None,
                  (1MB),
                  [System.IO.FileOptions]::WriteThrough)
        for ($i = 0; $i -lt $sizeMB; $i++) { $fs.Write($chunkData, 0, $chunkData.Length) }
        $fs.Flush(); $fs.Close(); $fs.Dispose()
        $sw.Stop()
        $writeMBs = [math]::Round($sizeMB / $sw.Elapsed.TotalSeconds, 1)

        $lblBenchStatus.Text = "Midiendo lectura..."
        Flush-UI

        # ---- LECTURA (SequentialScan) ----
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = [System.IO.FileStream]::new(
                  $testFile,
                  [System.IO.FileMode]::Open,
                  [System.IO.FileAccess]::Read,
                  [System.IO.FileShare]::Read,
                  (1MB),
                  [System.IO.FileOptions]::SequentialScan)
        $buf = New-Object byte[] (1MB)
        while ($fs.Read($buf, 0, $buf.Length) -gt 0) {}
        $fs.Close(); $fs.Dispose()
        $sw.Stop()
        $readMBs = [math]::Round($sizeMB / $sw.Elapsed.TotalSeconds, 1)

        Remove-Item $testFile -Force -EA SilentlyContinue

        $lblWriteSpeed.Text = "$writeMBs"
        $lblReadSpeed.Text  = "$readMBs"

        if ($script:benchWritePre -eq 0) {
            $script:benchWritePre = $writeMBs
            $script:benchReadPre  = $readMBs
            $lblWriteCompare.Text = "(referencia guardada)"
            $lblReadCompare.Text  = "(referencia guardada)"
            $lblBenchStatus.Text  = "Referencia guardada - optimiza y vuelve a ejecutar para comparar"
        } else {
            $wDiff = [math]::Round($writeMBs - $script:benchWritePre, 1)
            $rDiff = [math]::Round($readMBs  - $script:benchReadPre,  1)
            $wSign = if($wDiff -ge 0){"+"}else{""}
            $rSign = if($rDiff -ge 0){"+"}else{""}
            $lblWriteCompare.Text = "$wSign$wDiff MB/s vs antes ($($script:benchWritePre))"
            $lblReadCompare.Text  = "$rSign$rDiff MB/s vs antes ($($script:benchReadPre))"
            $wColor = if($wDiff -ge 0){ "#22C55E" } else { "#EF4444" }
            $rColor = if($rDiff -ge 0){ "#22C55E" } else { "#EF4444" }
            $lblWriteCompare.Foreground = New-Brush $wColor
            $lblReadCompare.Foreground  = New-Brush $rColor
            $script:benchWritePre = $writeMBs
            $script:benchReadPre  = $readMBs
            $lblBenchStatus.Text  = "Comparacion completada"
        }
    } catch {
        Write-Log "Error en benchmark: $_" "err"
        $lblBenchStatus.Text = "Error — ver consola"
    }
    $btnBenchmark.IsEnabled = $true
    Flush-UI
})

# ============================================================
# LIMPIEZA PROFUNDA DE CACHE
# ============================================================
$btnDeepClean.Add_Click({
    $r = [Windows.MessageBox]::Show(
        "Se limpiaran caches del sistema, reportes WER y logs no esenciales.`nEl Explorador se reiniciara brevemente.`n`nContinuar?",
        "WinBoost v$VERSION",
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Warning)
    if ($r -ne [Windows.MessageBoxResult]::Yes) { return }

    $btnDeepClean.IsEnabled  = $false
    $totalMB = 0.0

    # ---- 1. Cache del Explorador (iconcache + thumbcache) ----
    $lblDeepCleanStatus.Text = "Deteniendo Explorer..."; Flush-UI
    $iconMB = 0.0
    try {
        Stop-Process -Name explorer -Force -EA SilentlyContinue
        Start-Sleep -Milliseconds 1500

        $old = "$env:LOCALAPPDATA\IconCache.db"
        if(Test-Path $old){ $iconMB += (Get-Item $old).Length/1MB; Remove-Item $old -Force -EA SilentlyContinue }

        $cacheDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        $cacheFiles = Get-ChildItem -Path $cacheDir -Include "iconcache_*.db","thumbcache_*.db" `
                          -Force -EA SilentlyContinue
        foreach ($f in $cacheFiles){
            $iconMB += $f.Length / 1MB
            Remove-Item $f.FullName -Force -EA SilentlyContinue
        }
    } catch {
        Write-Log "Cache Explorer: $_" "err"
    } finally {
        # finally garantiza reinicio de Explorer incluso ante excepcion no capturada o cierre de la app
        if(-not (Get-Process explorer -EA SilentlyContinue)){ Start-Process explorer }
    }
    $iconMB   = [math]::Round($iconMB, 1)
    $totalMB += $iconMB
    Write-Log "Cache Explorer: $iconMB MB liberados" "ok"
    $lblDeepCleanStatus.Text = "WER..."; Flush-UI

    # ---- 2. WER — reportes de errores ----
    $werMB = 0.0
    $werPaths = @(
        "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
    )
    foreach ($p in $werPaths){
        if(Test-Path $p){
            $werMB += Get-FolderMB $p
            Get-ChildItem -Path $p -Recurse -Force -EA SilentlyContinue |
                Remove-Item -Recurse -Force -EA SilentlyContinue
        }
    }
    $werMB    = [math]::Round($werMB, 1)
    $totalMB += $werMB
    Write-Log "WER reports: $werMB MB liberados" "ok"
    $lblDeepCleanStatus.Text = "Logs..."; Flush-UI

    # ---- 3. Logs de Windows (CBS, DISM) ----
    $logMB = 0.0
    $logTargets = @(
        "$env:SystemRoot\Logs\CBS",
        "$env:SystemRoot\Logs\DISM"
    )
    foreach ($p in $logTargets){
        if(Test-Path $p){
            $logMB += Get-FolderMB $p
            Get-ChildItem -Path $p -Filter "*.log"  -Force -EA SilentlyContinue |
                Remove-Item -Force -EA SilentlyContinue
            Get-ChildItem -Path $p -Filter "*.cab"  -Force -EA SilentlyContinue |
                Remove-Item -Force -EA SilentlyContinue
        }
    }
    $logMB    = [math]::Round($logMB, 1)
    $totalMB += $logMB
    Write-Log "Logs CBS/DISM: $logMB MB liberados" "ok"
    $lblDeepCleanStatus.Text = "Shader cache..."; Flush-UI

    # ---- 4. Cache de shaders Direct3D ----
    $shaderMB = 0.0
    $shaderPaths = @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\AMD\DxCache"
    )
    foreach ($p in $shaderPaths){
        if(Test-Path $p){
            $shaderMB += Get-FolderMB $p
            Get-ChildItem -Path $p -Recurse -Force -EA SilentlyContinue |
                Remove-Item -Recurse -Force -EA SilentlyContinue
        }
    }
    $shaderMB = [math]::Round($shaderMB, 1)
    $totalMB += $shaderMB
    Write-Log "Shader cache: $shaderMB MB liberados" "ok"

    $totalMB = [math]::Round($totalMB, 1)
    Write-Log "LIMPIEZA PROFUNDA: $totalMB MB totales liberados" "head"
    $lblDeepCleanStatus.Text = "Listo  $totalMB MB liberados"
    $btnDeepClean.IsEnabled  = $true
    Flush-UI
})

# ============================================================
# MONITOR EN TIEMPO REAL  (DispatcherTimer - tick cada 1 s)
# ============================================================
$script:monitorTotalRAMMB = $totalRAM * 1024   # total RAM del sistema en MB (entero)
$script:shuttingDown      = $false              # F2.2: guard contra NextValue() post-Dispose

try {
    $script:pcCPU     = New-Object System.Diagnostics.PerformanceCounter("Processor",   "% Processor Time", "_Total")
    $script:pcRAMFree = New-Object System.Diagnostics.PerformanceCounter("Memory",       "Available MBytes")
    $script:pcDisk    = New-Object System.Diagnostics.PerformanceCounter("PhysicalDisk", "% Disk Time",      "_Total")
    $script:pcCPU.NextValue()     | Out-Null   # primer valor es siempre 0 - descartar
    $script:pcDisk.NextValue()    | Out-Null
    $script:pcRAMFree.NextValue() | Out-Null
} catch {}

# Brushes pre-definidos y congelados: evita allocations por GC en cada tick
$brMon = @{
    Green  = New-Brush "#22C55E"
    Yellow = New-Brush "#F59E0B"
    Red    = New-Brush "#EF4444"
    Blue   = New-Brush "#00C8FF"
}

$script:monitorTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:monitorTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:monitorTimer.Add_Tick({
    if ($script:shuttingDown) { return }
    try {
        $cpu  = [math]::Min(100, [math]::Round($script:pcCPU.NextValue(),     0))
        $disk = [math]::Min(100, [math]::Round($script:pcDisk.NextValue(),    0))
        $free = [math]::Round($script:pcRAMFree.NextValue(), 0)
        $used = [math]::Max(0, $script:monitorTotalRAMMB - $free)
        $ramPct = [math]::Min(100,[math]::Round($used / [math]::Max(1,$script:monitorTotalRAMMB) * 100, 0))
        $usedGB = [math]::Round($used / 1024, 1)
        $totGB  = $script:monitorTotalRAMMB / 1024

        $barCPUFill.Height  = [math]::Max(2, [math]::Round(110 * $cpu    / 100, 0)); $lblCPUPct.Text = "$cpu%"
        $barRAMFill.Height  = [math]::Max(2, [math]::Round(110 * $ramPct / 100, 0)); $lblRAMVal.Text = "$usedGB / $totGB GB"
        $barDiskFill.Height = [math]::Max(2, [math]::Round(110 * $disk   / 100, 0)); $lblDiskPct.Text = "$disk%"

        $barCPUFill.Background  = if($cpu    -gt 85){$brMon.Red}elseif($cpu    -gt 60){$brMon.Yellow}else{$brMon.Green}
        $barRAMFill.Background  = if($ramPct -gt 85){$brMon.Red}elseif($ramPct -gt 70){$brMon.Yellow}else{$brMon.Blue}
        $barDiskFill.Background = if($disk   -gt 85){$brMon.Red}elseif($disk   -gt 60){$brMon.Yellow}else{$brMon.Green}
    } catch {}
})
$script:monitorTimer.Start()

$window.Add_Closing({
    param($s, $e)
    if($script:settings.CloseAction -eq "minimize"){
        $e.Cancel = $true
        $window.WindowState = [Windows.WindowState]::Minimized
        return
    }
    # F2.2: marcar shutdown ANTES de Stop() para que ticks ya encolados en el Dispatcher salgan
    $script:shuttingDown = $true
    # Detener todos los timers (F0.4 / F0.12)
    try { $script:monitorTimer.Stop() } catch {}
    try { Stop-ProcTimer } catch {}
    try { $script:gamingTimer.Stop() } catch {}
    try { if ($script:applyTimer) { $script:applyTimer.Stop() } } catch {}
    try { if ($script:trimTimer)  { $script:trimTimer.Stop()  } } catch {}
    # Cancelar cualquier Start-Job pendiente (F0.4)
    try { Get-Job | Remove-Job -Force -EA SilentlyContinue } catch {}
    # Liberar PerformanceCounters (F0.4)
    try { $script:pcCPU.Dispose(); $script:pcRAMFree.Dispose(); $script:pcDisk.Dispose() } catch {}
    # Reiniciar Explorer si fue detenido por limpieza profunda y no se recupero (F0.11)
    try { if(-not (Get-Process explorer -EA SilentlyContinue)){ Start-Process explorer } } catch {}
})


# ============================================================
# GESTOR DE ARRANQUE
# ============================================================
$script:startupItems = @()
$APPR_HKCU   = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
$APPR_HKLM   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
$APPR_FOLDER = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"

function Get-ApprState {
    param([string]$apprPath, [string]$name)
    try {
        $v = Get-ItemPropertyValue -Path $apprPath -Name $name -EA SilentlyContinue
        if ($v -and $v.Length -ge 1) { return ($v[0] -ne 0x03 -and $v[0] -ne 0x08) }
    } catch {}
    return $true
}

function Load-StartupItems {
    $script:startupItems = @()

    # HKCU\Run
    $runHKCU = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try {
        $p = Get-ItemProperty -Path $runHKCU -EA SilentlyContinue
        if ($p) {
            $p.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                $script:startupItems += [PSCustomObject]@{
                    Name     = $_.Name
                    Path     = $_.Value
                    Source   = "HKCU"
                    Enabled  = Get-ApprState $APPR_HKCU $_.Name
                    ApprPath = $APPR_HKCU
                    FileName = ""
                }
            }
        }
    } catch {}

    # HKLM\Run
    $runHKLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try {
        $p = Get-ItemProperty -Path $runHKLM -EA SilentlyContinue
        if ($p) {
            $p.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                $script:startupItems += [PSCustomObject]@{
                    Name     = $_.Name
                    Path     = $_.Value
                    Source   = "HKLM"
                    Enabled  = Get-ApprState $APPR_HKLM $_.Name
                    ApprPath = $APPR_HKLM
                    FileName = ""
                }
            }
        }
    } catch {}

    # Carpeta Startup del usuario
    $userStartup = [System.Environment]::GetFolderPath("Startup")
    try {
        Get-ChildItem -Path $userStartup -File -EA SilentlyContinue |
        Where-Object { $_.Extension -ne ".ini" } |
        ForEach-Object {
            $fname = $_.Name
            $script:startupItems += [PSCustomObject]@{
                Name     = [System.IO.Path]::GetFileNameWithoutExtension($fname)
                Path     = $_.FullName
                Source   = "Startup"
                Enabled  = Get-ApprState $APPR_FOLDER $fname
                ApprPath = $APPR_FOLDER
                FileName = $fname
            }
        }
    } catch {}

    # Carpeta Startup comun (todos los usuarios)
    $allStartup = [System.Environment]::GetFolderPath("CommonStartup")
    try {
        Get-ChildItem -Path $allStartup -File -EA SilentlyContinue |
        Where-Object { $_.Extension -ne ".ini" } |
        ForEach-Object {
            $fname = $_.Name
            $script:startupItems += [PSCustomObject]@{
                Name     = [System.IO.Path]::GetFileNameWithoutExtension($fname)
                Path     = $_.FullName
                Source   = "Startup All"
                Enabled  = $true
                ApprPath = $APPR_FOLDER
                FileName = $fname
            }
        }
    } catch {}
}

function Render-StartupItems {
    $icStartup.Items.Clear()
    $styleOn  = $window.FindResource("BtnToggleOn")
    $styleOff = $window.FindResource("BtnToggleOff")

    $i = 0
    foreach ($item in $script:startupItems) {
        $rowBorder = New-Object Windows.Controls.Border
        $rowBorder.Padding = New-Object Windows.Thickness(12,5,12,5)
        $rowBorder.BorderThickness = New-Object Windows.Thickness(0,0,0,1)
        $rowBorder.BorderBrush = New-Brush "#1A1A1A"

        $grid = New-Object Windows.Controls.Grid
        foreach ($w in @(80,180,75,1,95)) {
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if($w -eq 1){
                [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            } else {
                [Windows.GridLength]::new($w)
            }
            $grid.ColumnDefinitions.Add($cd)
        }

        # Col 0 - Badge estado
        $stBdr = New-Object Windows.Controls.Border
        $stBdr.CornerRadius = New-Object Windows.CornerRadius(3)
        $stBdr.Padding = New-Object Windows.Thickness(6,2,6,2)
        $stBdr.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $stBdr.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
        $stBdr.Background = New-Brush $(if($item.Enabled){"#0A2A0A"}else{"#222222"})
        $stTxt = New-Object Windows.Controls.TextBlock
        $stTxt.Text = if($item.Enabled){"Activo"}else{"Inactivo"}
        $stTxt.FontSize = 10
        $stTxt.Foreground = New-Brush $(if($item.Enabled){"#22C55E"}else{"#555555"})
        $stBdr.Child = $stTxt
        [Windows.Controls.Grid]::SetColumn($stBdr, 0)

        # Col 1 - Nombre
        $nameTxt = New-Object Windows.Controls.TextBlock
        $nameTxt.Text = $item.Name
        $nameTxt.FontSize = 12
        $nameTxt.Foreground = New-Brush "#D3D3D3"
        $nameTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $nameTxt.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
        $nameTxt.Margin = New-Object Windows.Thickness(0,0,6,0)
        [Windows.Controls.Grid]::SetColumn($nameTxt, 1)

        # Col 2 - Badge origen
        $srcBdr = New-Object Windows.Controls.Border
        $srcBdr.CornerRadius = New-Object Windows.CornerRadius(3)
        $srcBdr.Padding = New-Object Windows.Thickness(5,2,5,2)
        $srcBdr.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $srcBdr.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
        $srcBdr.Background = New-Brush "#1A1A2A"
        $srcTxt = New-Object Windows.Controls.TextBlock
        $srcTxt.Text = $item.Source
        $srcTxt.FontSize = 10
        $srcTxt.Foreground = New-Brush "#7788AA"
        $srcBdr.Child = $srcTxt
        [Windows.Controls.Grid]::SetColumn($srcBdr, 2)

        # Col 3 - Ruta
        $pathTxt = New-Object Windows.Controls.TextBlock
        $pathTxt.Text = $item.Path
        $pathTxt.FontSize = 11
        $pathTxt.Foreground = New-Brush "#444444"
        $pathTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $pathTxt.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
        $pathTxt.Margin = New-Object Windows.Thickness(8,0,8,0)
        [Windows.Controls.Grid]::SetColumn($pathTxt, 3)

        # Col 4 - Boton toggle
        $toggleBtn = New-Object Windows.Controls.Button
        $toggleBtn.Tag     = $i
        $toggleBtn.Content = if($item.Enabled){"Deshabilitar"}else{"Habilitar"}
        $toggleBtn.Style   = if($item.Enabled){$styleOn}else{$styleOff}
        $toggleBtn.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $toggleBtn.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($toggleBtn, 4)

        $toggleBtn.Add_Click({
            $idx = [int]$args[0].Tag
            Toggle-StartupItem $idx
        })

        $grid.Children.Add($stBdr)    | Out-Null
        $grid.Children.Add($nameTxt)  | Out-Null
        $grid.Children.Add($srcBdr)   | Out-Null
        $grid.Children.Add($pathTxt)  | Out-Null
        $grid.Children.Add($toggleBtn)| Out-Null

        $rowBorder.Child = $grid
        $icStartup.Items.Add($rowBorder) | Out-Null
        $i++
    }

    $total   = $script:startupItems.Count
    $activos = ($script:startupItems | Where-Object { $_.Enabled }).Count
    $lblStartupCount.Text  = "$total programas en total  |  $activos activos  |  $($total - $activos) deshabilitados"
    $lblStartupStatus.Text = "Lista actualizada"
    Flush-UI
}

function Toggle-StartupItem {
    param([int]$idx)
    $item      = $script:startupItems[$idx]
    $newState  = -not $item.Enabled
    $valBytes  = if($newState){ [byte[]](0x02,0,0,0,0,0,0,0,0,0,0,0) }
                 else         { [byte[]](0x03,0,0,0,0,0,0,0,0,0,0,0) }
    try {
        if (-not (Test-Path $item.ApprPath)) {
            New-Item -Path $item.ApprPath -Force | Out-Null
        }
        $keyName = if($item.FileName -ne ""){ $item.FileName } else { $item.Name }
        Set-ItemProperty -Path $item.ApprPath -Name $keyName -Type Binary -Value $valBytes -Force
        $item.Enabled = $newState
        $lblStartupStatus.Text = "$(if($newState){'Habilitado'}else{'Deshabilitado'}): $($item.Name)"
        Render-StartupItems
    } catch {
        Write-Log "Error en arranque: $_" "err"
        $lblStartupStatus.Text = "Error — ver consola"
    }
}

$btnRefreshStartup.Add_Click({
    $lblStartupStatus.Text = "Actualizando..."
    Flush-UI
    Load-StartupItems
    Render-StartupItems
})

# ============================================================
# LIBERADOR DE RAM
# ============================================================
function Update-RAMDisplay {
    try {
        $os     = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        $totGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        $lblRAMTotal.Text = "$totGB GB"
        $lblRAMUsed.Text  = "$usedGB GB"
        $lblRAMFree.Text  = "$freeGB GB"
    } catch {}
}

function Invoke-StandbyListPurge {
    # Habilita SeProfileSingleProcessPrivilege antes de purgar
    # NtSetSystemInformation(0x50, cmd=4) = MemoryPurgeStandbyList
    # NTSTATUS 0 = STATUS_SUCCESS; cualquier otro valor = fallo real
    try {
        [MemAPI]::EnablePrivilege("SeProfileSingleProcessPrivilege") | Out-Null
        $ntstatus = [MemAPI]::PurgeStandbyList()
        if ($ntstatus -ne 0) {
            Write-Log "Standby purge NTSTATUS: 0x$($ntstatus.ToString('X8'))" "skip"
        }
        return ($ntstatus -eq 0)
    } catch {
        return $false
    }
}

$btnFreeRAM.Add_Click({
    $btnFreeRAM.IsEnabled  = $false
    $lblRAMFreeStatus.Text = "Liberando procesos..."
    Flush-UI
    try {
        $osBefore   = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        $freeBefore = $osBefore.FreePhysicalMemory

        # Paso 1: EmptyWorkingSet en todos los procesos accesibles
        $count = 0
        Get-Process -EA SilentlyContinue | ForEach-Object {
            try { [MemAPI]::EmptyWorkingSet($_.Handle) | Out-Null; $count++ } catch {}
        }

        # Medir Working Set liberado antes de purgar Standby
        $osAfterWS = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        $freedMB   = if ($osAfterWS) { [math]::Round(($osAfterWS.FreePhysicalMemory - $freeBefore) / 1KB, 0) } else { 0 }
        $sign      = if ($freedMB -ge 0) { "+" } else { "" }
        Write-Log "Working Set liberado: ${sign}${freedMB} MB ($count procesos)" "ok"

        # Paso 2: Purgar Standby List y medir delta
        $lblRAMFreeStatus.Text = "Purgando Standby List..."
        Flush-UI

        $standbyFreedMB = 0
        try {
            # PerformanceCounter es mas preciso y rapido que WMI para medir memoria libre
            $pcFree = New-Object System.Diagnostics.PerformanceCounter("Memory", "Free & Zero Page List Bytes", "")
            $pcFree.NextValue() | Out-Null
            Start-Sleep -Milliseconds 150
            $freeBytesBefore = $pcFree.NextValue()

            $purgeOk = Invoke-StandbyListPurge

            if ($purgeOk) {
                Start-Sleep -Milliseconds 1000
                $freeBytesAfter = $pcFree.NextValue()
                $standbyFreedMB = [math]::Max(0, [math]::Round(
                    ($freeBytesAfter - $freeBytesBefore) / 1MB, 0))
                Write-Log "Standby List purgada: +$standbyFreedMB MB adicionales liberados" "ok"
            } else {
                Write-Log "Purga de Standby List omitida (requiere admin)" "skip"
            }
            try { $pcFree.Dispose() } catch {}
        } catch {
            Write-Log "Standby List: no se pudo purgar" "skip"
        }

        Update-RAMDisplay

        $totalFreedMB = $freedMB + $standbyFreedMB
        $standbyInfo  = if ($standbyFreedMB -gt 0) { " + $standbyFreedMB MB standby" } else { "" }
        $lblRAMFreeStatus.Text = "Completado  |  +$freedMB MB Working Set$standbyInfo  |  Total: +$totalFreedMB MB  |  $count procesos"
    } catch {
        Write-Log "Error al liberar RAM: $_" "err"
        $lblRAMFreeStatus.Text = "Error — ver consola"
    }
    $btnFreeRAM.IsEnabled = $true
    Flush-UI
})

# ============================================================
# MODULO 1C - UI DE HISTORIAL / UNDO
# ============================================================

# ------------------------------------------------------------
# Write-RestoreLog
# Logger dedicado para la consola de restauracion en la UI.
# Misma firma que Write-Log para ser compatible con Restore-Session.
# ------------------------------------------------------------
function Write-RestoreLog {
    param([string]$msg, [string]$type = "info")
    $ts  = Get-Date -Format "HH:mm:ss"
    $colorMap = @{
        ok   = "#22C55E"; err  = "#EF4444"; skip = "#666666"
        head = "#00C8FF"; info = "#F59E0B"
    }
    $labelMap = @{
        ok   = "  OK   "; err  = "  !!   "; skip = "  --   "
        head = " ====  "; info = "  >>   "
    }
    $col  = if($colorMap.ContainsKey($type)){ $colorMap[$type] } else { "#888888" }
    $lbl  = if($labelMap.ContainsKey($type)){ $labelMap[$type] } else { "  >>   " }
    $line = "$ts$lbl$msg"

    $para = New-Object System.Windows.Documents.Paragraph
    $para.Margin = New-Object Windows.Thickness(0)
    $run  = New-Object System.Windows.Documents.Run($line)
    $run.Foreground = New-Brush $col
    $para.Inlines.Add($run) | Out-Null
    $rtbRestoreLog.Document.Blocks.Add($para) | Out-Null
    $restoreLogScroll.ScrollToEnd()

    # Actualizar badge de estado en la cabecera del log
    $lblRestoreLog.Text = $msg.Substring(0, [math]::Min($msg.Length, 55))
    $badgeRestoreStatus.Background = New-Brush $(if($type -eq "err"){"#2A0A0A"}elseif($type -eq "ok"){"#0A2A0A"}else{"#1A1A1A"})
    $lblRestoreLog.Foreground = New-Brush $col
    Flush-UI
}

# ------------------------------------------------------------
# New-EmptyState  (Modulo 1.3)
# Devuelve un Border centrado con icono grande + titulo + subtitulo
# para mostrar cuando una lista no tiene datos.
# ------------------------------------------------------------
function New-EmptyState {
    param(
        [string]$iconChar,
        [string]$title,
        [string]$subtitle,
        [int]$vertPadding = 40
    )
    $wrapper = New-Object Windows.Controls.Border
    $wrapper.Padding = New-Object Windows.Thickness(0, $vertPadding, 0, $vertPadding)

    $sp = New-Object Windows.Controls.StackPanel
    $sp.HorizontalAlignment = [Windows.HorizontalAlignment]::Center

    $icon           = New-Object Windows.Controls.TextBlock
    $icon.Text      = $iconChar
    $icon.FontSize  = 44
    $icon.FontFamily = New-Object Windows.Media.FontFamily("Segoe UI Symbol")
    $icon.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $icon.Foreground = New-Brush "#303030"
    $sp.Children.Add($icon) | Out-Null

    $lbl            = New-Object Windows.Controls.TextBlock
    $lbl.Text       = $title
    $lbl.FontSize   = 14
    $lbl.FontWeight = [Windows.FontWeights]::SemiBold
    $lbl.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $lbl.Margin     = New-Object Windows.Thickness(0, 14, 0, 6)
    $lbl.Foreground = New-Brush "#606060"
    $sp.Children.Add($lbl) | Out-Null

    $sub              = New-Object Windows.Controls.TextBlock
    $sub.Text         = $subtitle
    $sub.FontSize     = 11
    $sub.TextWrapping = [Windows.TextWrapping]::Wrap
    $sub.TextAlignment = [Windows.TextAlignment]::Center
    $sub.MaxWidth     = 300
    $sub.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $sub.Foreground   = New-Brush "#454545"
    $sp.Children.Add($sub) | Out-Null

    $wrapper.Child = $sp
    return $wrapper
}

# ------------------------------------------------------------
# Render-HistoryItems
# Construye dinamicamente la lista de sesiones en icHistory.
# ------------------------------------------------------------
function Render-HistoryItems {
    $icHistory.Items.Clear()
    $rtbRestoreLog.Document.Blocks.Clear()
    $lblRestoreLog.Text   = "Sin actividad"
    $lblHistoryStatus.Text = "Cargando..."
    Flush-UI

    $sessions = Get-BackupSessions

    if($sessions.Count -eq 0){
        $icHistory.Items.Add((New-EmptyState `
            ([char]0x23F1) `
            "Sin historial" `
            "Ejecuta una optimizacion para crear la primera sesion de backup.")) | Out-Null
        $lblHistoryStatus.Text = "Sin sesiones guardadas"
        return
    }

    $styleRevert = $window.FindResource("BtnDanger")
    $i = 0

    foreach($session in $sessions){
        $isFirst = ($i -eq 0)

        $rowBorder = New-Object Windows.Controls.Border
        $rowBorder.Padding         = New-Object Windows.Thickness(14,8,14,8)
        $rowBorder.BorderThickness = New-Object Windows.Thickness(0,0,0,1)
        $rowBorder.BorderBrush     = New-Brush "#1A1A1A"

        # Resaltar la sesion mas reciente
        if($isFirst){
            $rowBorder.Background = New-Brush "#0D1A0D"
        }

        $grid = New-Object Windows.Controls.Grid
        foreach($w in @(150, 90, 70, 75, 1, 110)){
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if($w -eq 1){
                [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            } else {
                [Windows.GridLength]::new($w)
            }
            $grid.ColumnDefinitions.Add($cd)
        }

        # Col 0 - Fecha
        $tsText = New-Object Windows.Controls.TextBlock
        $tsText.Text      = $session.timestamp
        $tsText.FontSize  = 11
        $tsText.Foreground = New-Brush $(if($isFirst){"#EEEEEE"}else{"#CCCCCC"})
        $tsText.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($tsText, 0)

        # Col 1 - Preset badge
        $presetBdr = New-Object Windows.Controls.Border
        $presetBdr.CornerRadius       = New-Object Windows.CornerRadius(3)
        $presetBdr.Padding            = New-Object Windows.Thickness(6,2,6,2)
        $presetBdr.VerticalAlignment  = [Windows.VerticalAlignment]::Center
        $presetBdr.HorizontalAlignment= [Windows.HorizontalAlignment]::Left
        $presetColor = switch($session.preset){
            "Gaming"        { "#0D1F2D" } "Productividad" { "#1A1A0D" }
            "Conservador"   { "#1A0D1A" } default         { "#1A1A1A" }
        }
        $presetFg = switch($session.preset){
            "Gaming"        { "#00C8FF" } "Productividad" { "#F59E0B" }
            "Conservador"   { "#A855F7" } default         { "#888888" }
        }
        $presetBdr.Background = New-Brush $presetColor
        $presetTxt = New-Object Windows.Controls.TextBlock
        $presetTxt.Text       = $session.preset
        $presetTxt.FontSize   = 10
        $presetTxt.Foreground = New-Brush $presetFg
        $presetBdr.Child = $presetTxt
        [Windows.Controls.Grid]::SetColumn($presetBdr, 1)

        # Col 2 - Acciones
        $actText = New-Object Windows.Controls.TextBlock
        $actText.Text      = "$($session.actions) acc."
        $actText.FontSize  = 11
        $actText.Foreground = New-Brush "#888888"
        $actText.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($actText, 2)

        # Col 3 - MB liberados
        $mbText = New-Object Windows.Controls.TextBlock
        $mbText.Text     = "$($session.freedMB) MB"
        $mbText.FontSize = 11
        $mbText.Foreground = New-Brush "#22C55E"
        $mbText.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($mbText, 3)

        # Col 4 - Estado (tiene metadata o no)
        $stateBdr = New-Object Windows.Controls.Border
        $stateBdr.CornerRadius       = New-Object Windows.CornerRadius(3)
        $stateBdr.Padding            = New-Object Windows.Thickness(6,2,6,2)
        $stateBdr.VerticalAlignment  = [Windows.VerticalAlignment]::Center
        $stateBdr.HorizontalAlignment= [Windows.HorizontalAlignment]::Left
        $stateBdr.Margin             = New-Object Windows.Thickness(8,0,0,0)
        $stateColor = if($session.hasMeta){ "#0A2A0A" } else { "#2A2A0A" }
        $stateFg    = if($session.hasMeta){ "#22C55E" } else { "#F59E0B" }
        $stateLabel = if($session.hasMeta){ "Completo" } else { "Sin metadata" }
        $stateBdr.Background = New-Brush $stateColor
        $stateTxt = New-Object Windows.Controls.TextBlock
        $stateTxt.Text       = $stateLabel
        $stateTxt.FontSize   = 10
        $stateTxt.Foreground = New-Brush $stateFg
        $stateBdr.Child = $stateTxt
        [Windows.Controls.Grid]::SetColumn($stateBdr, 4)

        # Col 5 - Boton revertir
        $revertBtn = New-Object Windows.Controls.Button
        $revertBtn.Content            = if($isFirst){ "Revertir" } else { "Revertir" }
        $revertBtn.Style              = $styleRevert
        $revertBtn.Tag                = $session.path
        $revertBtn.Padding            = New-Object Windows.Thickness(10,4,10,4)
        $revertBtn.FontSize           = 11
        $revertBtn.VerticalAlignment  = [Windows.VerticalAlignment]::Center
        $revertBtn.HorizontalAlignment= [Windows.HorizontalAlignment]::Center
        $revertBtn.ToolTip            = "Revertir sesion del $($session.timestamp)"
        [Windows.Controls.Grid]::SetColumn($revertBtn, 5)

        $revertBtn.Add_Click({
            param($sender, $e)
            $path = $sender.Tag
            Invoke-RevertSession -sessionPath $path
        })

        $grid.Children.Add($tsText)    | Out-Null
        $grid.Children.Add($presetBdr) | Out-Null
        $grid.Children.Add($actText)   | Out-Null
        $grid.Children.Add($mbText)    | Out-Null
        $grid.Children.Add($stateBdr)  | Out-Null
        $grid.Children.Add($revertBtn) | Out-Null

        $rowBorder.Child = $grid
        $icHistory.Items.Add($rowBorder) | Out-Null
        $i++
    }

    $lblHistoryStatus.Text = "$($sessions.Count) sesion(es) guardada(s)"
    Flush-UI
}

# ------------------------------------------------------------
# Invoke-RevertSession
# Muestra confirmacion, llama Restore-Session con el logger
# de la UI y actualiza la lista al terminar.
# ------------------------------------------------------------
function Invoke-RevertSession {
    param([string]$sessionPath)

    # --- Gate Pro: revertir sesion ---
    if (Lock-ProFeature "Revertir sesion") { return }

    $folderName = Split-Path $sessionPath -Leaf

    $confirm = [Windows.MessageBox]::Show(
        "Vas a revertir la sesion:`n$folderName`n`nEsto restaurara los valores de registro, servicios y red al estado anterior a esa optimizacion.`n`nContinuar?",
        "WinBoost - Revertir sesion",
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Warning)

    if($confirm -ne [Windows.MessageBoxResult]::Yes){ return }

    # Deshabilitar botones durante la restauracion
    $btnRevertLast.IsEnabled    = $false
    $btnRefreshHistory.IsEnabled= $false
    $icHistory.IsEnabled        = $false
    $rtbRestoreLog.Document.Blocks.Clear()
    Flush-UI

    # Logger que escribe en rtbRestoreLog
    $uiLogger = {
        param([string]$msg, [string]$type = "info")
        Write-RestoreLog -msg $msg -type $type
    }

    $ok = Restore-Session -sessionPath $sessionPath -logFn $uiLogger

    # Re-habilitar UI
    $btnRevertLast.IsEnabled    = $true
    $btnRefreshHistory.IsEnabled= $true
    $icHistory.IsEnabled        = $true
    Flush-UI

    if($ok){
        [Windows.MessageBox]::Show(
            "Sesion revertida correctamente.`n`nReinicia el equipo para que todos los cambios tomen efecto.",
            "WinBoost - Restauracion completada",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
    } else {
        [Windows.MessageBox]::Show(
            "La restauracion termino con algunos errores.`n`nRevisa el log de restauracion para ver los detalles.",
            "WinBoost - Restauracion con errores",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Warning) | Out-Null
    }
}

# ------------------------------------------------------------
# Eventos de la pestaña Historial
# ------------------------------------------------------------
$btnRefreshHistory.Add_Click({ Render-HistoryItems })

$btnOpenBackupFolder.Add_Click({
    try {
        if(-not (Test-Path $BACKUP_ROOT)){
            New-Item -ItemType Directory -Path $BACKUP_ROOT -Force | Out-Null
        }
        Start-Process "explorer.exe" $BACKUP_ROOT
    } catch {}
})

$btnRevertLast.Add_Click({
    $sessions = Get-BackupSessions
    if($sessions.Count -eq 0){
        [Windows.MessageBox]::Show(
            "No hay sesiones de backup guardadas.",
            "WinBoost - Historial",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    Invoke-RevertSession -sessionPath $sessions[0].path
})

# ============================================================
# MODULO 4B - UI DEL DETECTOR DE BLOATWARE
# ============================================================

# Lista de bloatware detectado (cache de sesion)
$script:bloatList      = $null
$script:bloatChecks    = @{}   # idx -> CheckBox

# Colores por categoria
$script:bloatCatColor = @{
    "Juegos"       = "#00C8FF"
    "Comunicacion" = "#A855F7"
    "Telemetria"   = "#EF4444"
    "OEM"          = "#F59E0B"
    "Utilidades"   = "#888888"
}

# ------------------------------------------------------------
# Update-BloatStats
# Recalcula el footer de seleccion cada vez que cambia un check.
# ------------------------------------------------------------
function Update-BloatStats {
    $selCount = 0
    $selMB    = 0
    foreach($idx in $script:bloatChecks.Keys){
        if($script:bloatChecks[$idx].IsChecked){
            $selCount++
            $selMB += $script:bloatList[$idx].EstimateMB
        }
    }
    $lblBloatSelected.Text  = "$selCount app(s) seleccionada(s)  |  ~$selMB MB estimados"
    $btnRemoveBloat.IsEnabled = ($selCount -gt 0)
    Flush-UI
}

# ------------------------------------------------------------
# Render-BloatItems
# Construye la lista de filas en icBloat segun el filtro activo.
# ------------------------------------------------------------
function Render-BloatItems {
    param([string]$filterCategory = "Todas las categorias")

    $icBloat.Items.Clear()
    $script:bloatChecks = @{}

    if(-not $script:bloatList -or $script:bloatList.Count -eq 0){
        $icBloat.Items.Add((New-EmptyState `
            ([char]0x2713) `
            "Sistema limpio" `
            "No se detecto bloatware instalado en este equipo.")) | Out-Null
        $btnRemoveBloat.IsEnabled = $false
        $lblBloatSelected.Text = "0 apps seleccionadas  |  0 MB estimados"
        return
    }

    # Filtrar por categoria si corresponde
    $filtered = if($filterCategory -eq "Todas las categorias"){
        $script:bloatList
    } else {
        $script:bloatList | Where-Object { $_.Category -eq $filterCategory }
    }

    $i = 0
    foreach($item in $filtered){

        $rowBdr = New-Object Windows.Controls.Border
        $rowBdr.Padding         = New-Object Windows.Thickness(14,7,14,7)
        $rowBdr.BorderThickness = New-Object Windows.Thickness(0,0,0,1)
        $rowBdr.BorderBrush     = New-Brush "#1A1A1A"

        $grid = New-Object Windows.Controls.Grid
        foreach($w in @(32, 1, 100, 70, 75, 80)){
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if($w -eq 1){
                [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            } else {
                [Windows.GridLength]::new($w)
            }
            $grid.ColumnDefinitions.Add($cd)
        }

        # Col 0 — Checkbox
        $chk = New-Object Windows.Controls.CheckBox
        $chk.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        $chk.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $chk.IsChecked = ($item.Risk -eq "safe")
        $chk.Tag       = $i
        $chk.Add_Click({ Update-BloatStats })
        [Windows.Controls.Grid]::SetColumn($chk, 0)
        $script:bloatChecks[$i] = $chk

        # Col 1 — Nombre
        $nameTxt = New-Object Windows.Controls.TextBlock
        $nameTxt.Text              = $item.Name
        $nameTxt.FontSize          = 12
        $nameTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $nameTxt.TextTrimming      = [Windows.TextTrimming]::CharacterEllipsis
        $nameTxt.Margin            = New-Object Windows.Thickness(0,0,8,0)
        $nameTxt.Foreground        = New-Brush "#CCCCCC"
        [Windows.Controls.Grid]::SetColumn($nameTxt, 1)

        # Col 2 — Badge categoria
        $catColor = if($script:bloatCatColor.ContainsKey($item.Category)){
            $script:bloatCatColor[$item.Category]
        } else { "#888888" }

        $catBdr = New-Object Windows.Controls.Border
        $catBdr.CornerRadius       = New-Object Windows.CornerRadius(3)
        $catBdr.Padding            = New-Object Windows.Thickness(6,2,6,2)
        $catBdr.VerticalAlignment  = [Windows.VerticalAlignment]::Center
        $catBdr.HorizontalAlignment= [Windows.HorizontalAlignment]::Left
        $catBdr.Background         = New-Brush $(switch($item.Category){
                    "Juegos"       {"#0D1F2D"}
                    "Comunicacion" {"#1A0D2D"}
                    "Telemetria"   {"#2A0A0A"}
                    "OEM"          {"#2A1A00"}
                    default        {"#1A1A1A"}
                })
        $catTxt = New-Object Windows.Controls.TextBlock
        $catTxt.Text       = $item.Category
        $catTxt.FontSize   = 10
        $catTxt.Foreground = New-Brush $catColor
        $catBdr.Child = $catTxt
        [Windows.Controls.Grid]::SetColumn($catBdr, 2)

        # Col 3 — Metodo badge
        $methodColor = switch($item.Method){
            "appx"         { "#555555" }
            "winget"       { "#22C55E" }
            "appx+winget"  { "#00C8FF" }
            default        { "#555555" }
        }
        $methodLabel = switch($item.Method){
            "appx"         { "AppX" }
            "winget"       { "winget" }
            "appx+winget"  { "AppX+wg" }
            default        { $item.Method }
        }
        $mthBdr = New-Object Windows.Controls.Border
        $mthBdr.CornerRadius       = New-Object Windows.CornerRadius(3)
        $mthBdr.Padding            = New-Object Windows.Thickness(5,2,5,2)
        $mthBdr.VerticalAlignment  = [Windows.VerticalAlignment]::Center
        $mthBdr.HorizontalAlignment= [Windows.HorizontalAlignment]::Left
        $mthBdr.Background         = New-Brush "#1A1A1A"
        $mthTxt = New-Object Windows.Controls.TextBlock
        $mthTxt.Text       = $methodLabel
        $mthTxt.FontSize   = 10
        $mthTxt.Foreground = New-Brush $methodColor
        $mthBdr.Child = $mthTxt
        [Windows.Controls.Grid]::SetColumn($mthBdr, 3)

        # Col 4 — Espacio estimado
        $mbTxt = New-Object Windows.Controls.TextBlock
        $mbTxt.Text              = "~$($item.EstimateMB) MB"
        $mbTxt.FontSize          = 11
        $mbTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $mbTxt.Foreground        = New-Brush "#666666"
        [Windows.Controls.Grid]::SetColumn($mbTxt, 4)

        # Col 5 — Badge riesgo
        $riskColor = if($item.Risk -eq "safe"){ "#22C55E" } else { "#F59E0B" }
        $riskBgCol = if($item.Risk -eq "safe"){ "#0A2A0A" } else { "#2A1A00" }
        $riskLabel = if($item.Risk -eq "safe"){ "Seguro" } else { "Precaucion" }

        $riskBdr = New-Object Windows.Controls.Border
        $riskBdr.CornerRadius       = New-Object Windows.CornerRadius(3)
        $riskBdr.Padding            = New-Object Windows.Thickness(7,2,7,2)
        $riskBdr.VerticalAlignment  = [Windows.VerticalAlignment]::Center
        $riskBdr.HorizontalAlignment= [Windows.HorizontalAlignment]::Center
        $riskBdr.Background         = New-Brush $riskBgCol
        $riskBdr.BorderBrush        = New-Brush $riskColor
        $riskBdr.BorderThickness    = New-Object Windows.Thickness(1)
        $riskTxt = New-Object Windows.Controls.TextBlock
        $riskTxt.Text       = $riskLabel
        $riskTxt.FontSize   = 10
        $riskTxt.Foreground = New-Brush $riskColor
        $riskBdr.Child = $riskTxt
        [Windows.Controls.Grid]::SetColumn($riskBdr, 5)

        $grid.Children.Add($chk)     | Out-Null
        $grid.Children.Add($nameTxt) | Out-Null
        $grid.Children.Add($catBdr)  | Out-Null
        $grid.Children.Add($mthBdr)  | Out-Null
        $grid.Children.Add($mbTxt)   | Out-Null
        $grid.Children.Add($riskBdr) | Out-Null

        $rowBdr.Child = $grid
        $icBloat.Items.Add($rowBdr) | Out-Null
        $i++
    }

    Update-BloatStats
    Flush-UI
}

# ------------------------------------------------------------
# Start-BloatScan
# Ejecuta el escaneo, actualiza stats y renderiza la lista.
# ------------------------------------------------------------
function Start-BloatScan {
    $btnScanBloat.IsEnabled   = $false
    $btnRemoveBloat.IsEnabled = $false
    $lblBloatStatus.Text      = "Escaneando..."
    $lblBloatCount.Text       = "..."
    $lblBloatMB.Text          = "..."
    Flush-UI

    try {
        $script:bloatList = Get-BloatwareList
        $summary          = Get-BloatwareSummary -list $script:bloatList

        $lblBloatCount.Text   = "$($summary.Count)"
        $lblBloatMB.Text      = "$($summary.TotalMB)"
        $lblBloatSafe.Text    = "$($summary.SafeCount)"
        $lblBloatCaution.Text = "$($summary.CautionCount)"

        $wingetOk = Test-WingetAvailable
        $lblBloatWinget.Text  = if($wingetOk){
            "winget disponible"
        } else {
            "winget no detectado - apps Win32/OEM no escaneadas"
        }

        # Aplicar filtro actual al renderizar
        $filterText = "Todas las categorias"
        try {
            $sel = $cboBloatFilter.SelectedItem
            if($sel){ $filterText = $sel.Content }
        } catch {}

        Render-BloatItems -filterCategory $filterText

        $lblBloatStatus.Text = if($summary.Count -eq 0){
            "Sin bloatware detectado"
        } else {
            "Escaneo completado"
        }
    } catch {
        Write-Log "Error en escaneo bloatware: $_" "err"
        $lblBloatStatus.Text = "Error — ver consola"
    }
    $btnScanBloat.IsEnabled = $true
    Flush-UI
}

# ============================================================
# MODULO 4C - MOTOR DE DESINSTALACION DE BLOATWARE
# ============================================================

# ------------------------------------------------------------
# Remove-BloatItem
# Desinstala UN item de bloatware.
# Maneja AppX (Remove-AppxPackage) y winget (winget uninstall).
# Devuelve [PSCustomObject]@{ Name; Ok; Method; Message }
# ------------------------------------------------------------
function Remove-BloatItem {
    param([PSCustomObject]$item)

    $result = [PSCustomObject]@{
        Name    = $item.Name
        Ok      = $false
        Method  = $item.Method
        Message = ""
    }

    # --- Intentar via AppX primero ---
    if($item.PackageFN -and
       ($item.Method -eq "appx" -or $item.Method -eq "appx+winget")){
        try {
            # Quitar para el usuario actual
            Get-AppxPackage -Name "*$($item.PackageFN.Split('_')[0])*" `
                -EA SilentlyContinue |
                Remove-AppxPackage -EA Stop

            # Quitar el paquete provisionado (evita que vuelva al crear nuevos usuarios)
            Get-AppxProvisionedPackage -Online -EA SilentlyContinue |
                Where-Object { $_.PackageName -like "*$($item.PackageFN.Split('_')[0])*" } |
                Remove-AppxProvisionedPackage -Online -EA SilentlyContinue | Out-Null

            $result.Ok      = $true
            $result.Message = "Eliminado via AppX"
            return $result
        } catch {
            $result.Message = "AppX fallo: $($_.Exception.Message)"
            # Continuar a winget si aplica
        }
    }

    # --- Intentar via winget ---
    if($item.WingetId -and
       ($item.Method -eq "winget" -or $item.Method -eq "appx+winget")){
        try {
            if(-not (Test-WingetAvailable)){
                $result.Message = "winget no disponible"
                return $result
            }
            $proc = Start-Process -FilePath "winget" `
                -ArgumentList "uninstall --id `"$($item.WingetId)`" --silent --accept-source-agreements --disable-interactivity" `
                -Wait -PassThru -WindowStyle Hidden -EA Stop

            if($proc.ExitCode -eq 0){
                $result.Ok      = $true
                $result.Message = "Eliminado via winget"
            } else {
                $result.Message = "winget ExitCode=$($proc.ExitCode)"
            }
        } catch {
            $result.Message = "winget error: $($_.Exception.Message)"
        }
    }

    return $result
}

# ------------------------------------------------------------
# Save-BloatBackup
# Guarda la lista de bloatware que existia antes de desinstalar
# en la sesion de backup activa, como referencia para historial.
# ------------------------------------------------------------
function Save-BloatBackup {
    param([System.Collections.Generic.List[PSCustomObject]]$itemsToRemove)
    if(-not $script:activeSession){ return }
    try {
        $snapshot = $itemsToRemove | ForEach-Object {
            [PSCustomObject]@{
                Name      = $_.Name
                Category  = $_.Category
                Method    = $_.Method
                PackageFN = $_.PackageFN
                WingetId  = $_.WingetId
                RemovedAt = (Get-Date -Format "HH:mm:ss")
            }
        }
        $outFile = Join-Path $script:activeSession "bloatware_removed.json"
        $snapshot | ConvertTo-Json -Depth 4 | Out-File $outFile -Encoding UTF8
    } catch {}
}

# ------------------------------------------------------------
# Invoke-RemoveBloat
# Orquesta la desinstalacion de todos los items seleccionados.
# Muestra confirmacion, ejecuta en orden, loguea en la consola
# principal y re-escanea al terminar.
# ------------------------------------------------------------
function Invoke-RemoveBloat {

    # --- Gate Pro: desinstalar bloatware ---
    if (Lock-ProFeature "Desinstalar bloatware") { return }

    # Recopilar items seleccionados
    $toRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach($idx in ($script:bloatChecks.Keys | Sort-Object)){
        if($script:bloatChecks[$idx].IsChecked){
            $toRemove.Add($script:bloatList[$idx])
        }
    }

    if($toRemove.Count -eq 0){ return }

    # Separar seguros de precaucion para el mensaje de confirmacion
    $safeItems    = @($toRemove | Where-Object { $_.Risk -eq "safe"    })
    $cautionItems = @($toRemove | Where-Object { $_.Risk -eq "caution" })
    $totalMB      = ($toRemove | Measure-Object EstimateMB -Sum).Sum

    $confirmMsg = "Vas a desinstalar $($toRemove.Count) app(s):`n"
    $confirmMsg += "  Seguras:    $($safeItems.Count)`n"
    $confirmMsg += "  Precaucion: $($cautionItems.Count)`n"
    $confirmMsg += "  Espacio estimado: ~$totalMB MB`n`n"

    if($cautionItems.Count -gt 0){
        $confirmMsg += "Apps marcadas como Precaucion:`n"
        foreach($c in $cautionItems){ $confirmMsg += "  - $($c.Name)`n" }
        $confirmMsg += "`n"
    }
    $confirmMsg += "Esta accion no es facilmente reversible.`nContinuar?"

    $confirm = [Windows.MessageBox]::Show(
        $confirmMsg,
        "WinBoost - Desinstalar bloatware",
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Warning)

    if($confirm -ne [Windows.MessageBoxResult]::Yes){ return }

    # --- Deshabilitar UI ---
    $btnScanBloat.IsEnabled   = $false
    $btnRemoveBloat.IsEnabled = $false
    $btnBloatSelAll.IsEnabled = $false
    $btnBloatSelNone.IsEnabled= $false
    Set-ActiveNav 1   # Ir a la consola para ver el log
    Flush-UI

    # Guardar backup de lo que habia
    Save-BloatBackup -itemsToRemove $toRemove

    Write-Log "DESINSTALACION DE BLOATWARE" "head"
    Write-Log "$($toRemove.Count) app(s) seleccionadas - ~$totalMB MB estimados" "info"

    $okCount     = 0
    $failCount   = 0
    $i           = 0

    foreach($item in $toRemove){
        $i++
        $pct  = [int][math]::Round($i / $toRemove.Count * 100)
        Set-Progress $pct "Desinstalando: $($item.Name)..."
        Write-Log "Desinstalando: $($item.Name)" "info"
        Flush-UI

        $res = Remove-BloatItem -item $item

        if($res.Ok){
            Write-Log "$($item.Name) - $($res.Message)" "ok"
            $okCount++
        } else {
            Write-Log "$($item.Name) - $($res.Message)" "err"
            $failCount++
        }
    }

    # --- Resumen final ---
    Set-Progress 100 "Desinstalacion completada"
    Write-Log "Desinstalacion completada: $okCount ok  $failCount fallidos" `
              $(if($failCount -eq 0){ "ok" } else { "err" })
    $lblLogStatus.Text = "Bloatware eliminado"

    # Re-habilitar UI
    $btnScanBloat.IsEnabled    = $true
    $btnBloatSelAll.IsEnabled  = $true
    $btnBloatSelNone.IsEnabled = $true
    Flush-UI

    # Re-escanear automaticamente para reflejar cambios
    Set-ActiveNav 6   # Volver al tab Bloatware
    Start-BloatScan

    if($okCount -gt 0){
        [Windows.MessageBox]::Show(
            "Desinstalacion completada.`n`n$okCount app(s) eliminadas correctamente.`n$(if($failCount -gt 0){ "$failCount fallaron - revisa la consola para detalles." } else { '' })",
            "WinBoost - Bloatware eliminado",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
    } else {
        [Windows.MessageBox]::Show(
            "No se pudo desinstalar ninguna app.`nRevisa la consola para ver los detalles de cada error.",
            "WinBoost - Error en desinstalacion",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Warning) | Out-Null
    }
}

# ------------------------------------------------------------
# Eventos de la pestana Bloatware
# ------------------------------------------------------------
$btnScanBloat.Add_Click({ Start-BloatScan })

$btnRemoveBloat.Add_Click({ Invoke-RemoveBloat })

$btnBloatSelAll.Add_Click({
    # Selecciona solo los "safe" visibles
    foreach($idx in $script:bloatChecks.Keys){
        if($script:bloatList[$idx].Risk -eq "safe"){
            $script:bloatChecks[$idx].IsChecked = $true
        }
    }
    Update-BloatStats
})

$btnBloatSelNone.Add_Click({
    foreach($chk in $script:bloatChecks.Values){ $chk.IsChecked = $false }
    Update-BloatStats
})

$cboBloatFilter.Add_SelectionChanged({
    if(-not $script:bloatList){ return }
    $filterText = "Todas las categorias"
    try {
        $sel = $cboBloatFilter.SelectedItem
        if($sel){ $filterText = $sel.Content }
    } catch {}
    Render-BloatItems -filterCategory $filterText
})

# ============================================================
# MODULO 5B - UI DE PROCESOS PESADOS
# ============================================================

$script:procTimerRunning  = $false
$script:procTimer         = $null
$script:procTimerInterval = 3   # segundos entre refreshes
$script:_procSample1      = $null  # F2.8: snapshot anterior de TotalProcessorTime
$script:_procSampleTime1  = $null  # F2.8: timestamp de esa snapshot

# Brushes pre-congelados para el timer (evita allocs en cada tick)
$brProc = @{
    Red    = New-Brush "#EF4444"
    Yellow = New-Brush "#F59E0B"
    Green  = New-Brush "#22C55E"
    Blue   = New-Brush "#00C8FF"
    Gray   = New-Brush "#555555"
    White  = New-Brush "#CCCCCC"
}

# ------------------------------------------------------------
# Render-ProcessList
# Construye las filas de la lista de procesos.
# Llamado despues de Get-HeavyProcesses.
# ------------------------------------------------------------
function Render-ProcessList {
    param([System.Collections.Generic.List[PSCustomObject]]$procList)

    $icProcs.Items.Clear()

    if(-not $procList -or $procList.Count -eq 0){
        $icProcs.Items.Add((New-EmptyState `
            ([char]0x2699) `
            "Sin actividad pesada" `
            "No se encontraron procesos que consuman recursos significativos." `
            20)) | Out-Null
        return
    }

    $styleDanger = $window.FindResource("BtnDanger")

    foreach($p in $procList){

        $rowBdr = New-Object Windows.Controls.Border
        $rowBdr.Padding         = New-Object Windows.Thickness(14,6,14,6)
        $rowBdr.BorderThickness = New-Object Windows.Thickness(0,0,0,1)
        $rowBdr.BorderBrush     = New-Brush "#1A1A1A"

        if($p.IsSystem){
            $rowBdr.Background = New-Brush "#0A0A0F"
        }

        $grid = New-Object Windows.Controls.Grid
        foreach($w in @(160, 55, 90, 90, 1, 85)){
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if($w -eq 1){
                [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            } else {
                [Windows.GridLength]::new($w)
            }
            $grid.ColumnDefinitions.Add($cd)
        }

        # Col 0 — Nombre del proceso
        $namePanel = New-Object Windows.Controls.StackPanel
        $nameTxt = New-Object Windows.Controls.TextBlock
        $nameTxt.Text              = $p.Name
        $nameTxt.FontSize          = 12
        $nameTxt.FontWeight        = [Windows.FontWeights]::SemiBold
        $nameTxt.Foreground        = if($p.IsSystem){ $brProc.Gray } else { $brProc.White }
        $nameTxt.TextTrimming      = [Windows.TextTrimming]::CharacterEllipsis
        $nameTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        if($p.Description -and $p.Description -ne ""){
            $descTxt = New-Object Windows.Controls.TextBlock
            $descTxt.Text      = $p.Description
            $descTxt.FontSize  = 10
            $descTxt.Foreground= $brProc.Gray
            $descTxt.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
            $namePanel.Children.Add($nameTxt) | Out-Null
            $namePanel.Children.Add($descTxt) | Out-Null
        } else {
            $namePanel.Children.Add($nameTxt) | Out-Null
        }
        $namePanel.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($namePanel, 0)

        # Col 1 — PID
        $pidTxt = New-Object Windows.Controls.TextBlock
        $pidTxt.Text              = "$($p.PID)"
        $pidTxt.FontSize          = 11
        $pidTxt.Foreground        = $brProc.Gray
        $pidTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($pidTxt, 1)

        # Col 2 — CPU% con barra y color reactivo
        $cpuPanel = New-Object Windows.Controls.StackPanel
        $cpuPanel.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $cpuColor = if($p.CpuPct -ge 50){ $brProc.Red }
                    elseif($p.CpuPct -ge 20){ $brProc.Yellow }
                    else { $brProc.Blue }

        $cpuTxt = New-Object Windows.Controls.TextBlock
        $cpuTxt.Text      = "$($p.CpuPct)%"
        $cpuTxt.FontSize  = 12
        $cpuTxt.FontWeight= [Windows.FontWeights]::SemiBold
        $cpuTxt.Foreground= $cpuColor

        # Barra de CPU: Grid de dos columnas Star — WPF calcula el ancho, sin closures
        $cpuPct_ = [math]::Min(100, [math]::Max(0, $p.CpuPct))
        $cpuBarGrid = New-Object Windows.Controls.Grid
        $cpuBarGrid.Height = 3
        $cpuBarGrid.Margin = New-Object Windows.Thickness(0,2,8,0)
        $colFill  = New-Object Windows.Controls.ColumnDefinition
        $colFill.Width  = [Windows.GridLength]::new($cpuPct_,                      [Windows.GridUnitType]::Star)
        $colEmpty = New-Object Windows.Controls.ColumnDefinition
        $colEmpty.Width = [Windows.GridLength]::new([math]::Max(0, 100 - $cpuPct_),[Windows.GridUnitType]::Star)
        $cpuBarGrid.ColumnDefinitions.Add($colFill)
        $cpuBarGrid.ColumnDefinitions.Add($colEmpty)
        $bdrFill = New-Object Windows.Controls.Border
        $bdrFill.Background   = $cpuColor
        $bdrFill.CornerRadius = New-Object Windows.CornerRadius(2)
        [Windows.Controls.Grid]::SetColumn($bdrFill, 0)
        $bdrEmpty = New-Object Windows.Controls.Border
        $bdrEmpty.Background  = New-Brush "#1A1A1A"
        $bdrEmpty.CornerRadius = New-Object Windows.CornerRadius(2)
        [Windows.Controls.Grid]::SetColumn($bdrEmpty, 1)
        $cpuBarGrid.Children.Add($bdrFill)  | Out-Null
        $cpuBarGrid.Children.Add($bdrEmpty) | Out-Null

        $cpuPanel.Children.Add($cpuTxt)     | Out-Null
        $cpuPanel.Children.Add($cpuBarGrid) | Out-Null
        [Windows.Controls.Grid]::SetColumn($cpuPanel, 2)

        # Col 3 — RAM con color reactivo
        $ramColor = if($p.RamMB -ge 1024){ $brProc.Red }
                    elseif($p.RamMB -ge 300){ $brProc.Yellow }
                    else { $brProc.Green }

        $ramLabel = if($p.RamMB -ge 1024){
            "$([math]::Round($p.RamMB/1024,1)) GB"
        } else {
            "$($p.RamMB) MB"
        }
        $ramTxt = New-Object Windows.Controls.TextBlock
        $ramTxt.Text              = $ramLabel
        $ramTxt.FontSize          = 11
        $ramTxt.Foreground        = $ramColor
        $ramTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($ramTxt, 3)

        # Col 4 — Empresa / Path
        $companyTxt = New-Object Windows.Controls.TextBlock
        $companyTxt.Text         = if($p.Company){ $p.Company }
                                   elseif($p.Path){ $p.Path   }
                                   else           { ""         }
        $companyTxt.FontSize     = 10
        $companyTxt.Foreground   = $brProc.Gray
        $companyTxt.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
        $companyTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $companyTxt.Margin       = New-Object Windows.Thickness(8,0,8,0)
        [Windows.Controls.Grid]::SetColumn($companyTxt, 4)

        # Col 5 — Boton terminar (solo para procesos no-sistema)
        if(-not $p.IsSystem){
            $killBtn = New-Object Windows.Controls.Button
            $killBtn.Content             = "Terminar"
            $killBtn.Style               = $styleDanger
            $killBtn.Tag                 = $p.PID
            $killBtn.Padding             = New-Object Windows.Thickness(8,3,8,3)
            $killBtn.FontSize            = 10
            $killBtn.VerticalAlignment   = [Windows.VerticalAlignment]::Center
            $killBtn.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
            $killBtn.ToolTip             = "Terminar $($p.Name) (PID $($p.PID))"
            $killBtn.Add_Click({
                param($sender, $e)
                $pid_ = [int]$sender.Tag
                $proc = $script:procsList | Where-Object { $_.PID -eq $pid_ } |
                            Select-Object -First 1
                $pname = if($proc){ $proc.Name } else { "PID $pid_" }

                $confirm = [Windows.MessageBox]::Show(
                    "Terminar el proceso '$pname' (PID $pid_)?`n`nLos datos no guardados se perderan.",
                    "WinBoost - Terminar proceso",
                    [Windows.MessageBoxButton]::YesNo,
                    [Windows.MessageBoxImage]::Warning)

                if($confirm -ne [Windows.MessageBoxResult]::Yes){ return }

                $res = Stop-ManagedProcess -pid_ $pid_
                if($res.Ok){
                    Write-Log $res.Message "ok"
                    # Refrescar lista inmediatamente
                    Refresh-ProcessList
                } else {
                    Write-Log $res.Message "err"
                    [Windows.MessageBox]::Show(
                        $res.Message,
                        "WinBoost - Error",
                        [Windows.MessageBoxButton]::OK,
                        [Windows.MessageBoxImage]::Warning) | Out-Null
                }
            })
            [Windows.Controls.Grid]::SetColumn($killBtn, 5)
            $grid.Children.Add($killBtn) | Out-Null
        } else {
            # Badge "Sistema" para procesos del sistema
            $sysBdr = New-Object Windows.Controls.Border
            $sysBdr.CornerRadius       = New-Object Windows.CornerRadius(3)
            $sysBdr.Padding            = New-Object Windows.Thickness(6,3,6,3)
            $sysBdr.VerticalAlignment  = [Windows.VerticalAlignment]::Center
            $sysBdr.HorizontalAlignment= [Windows.HorizontalAlignment]::Center
            $sysBdr.Background         = New-Brush "#1A1A2A"
            $sysTxt = New-Object Windows.Controls.TextBlock
            $sysTxt.Text       = "Sistema"
            $sysTxt.FontSize   = 10
            $sysTxt.Foreground = $brProc.Gray
            $sysBdr.Child      = $sysTxt
            [Windows.Controls.Grid]::SetColumn($sysBdr, 5)
            $grid.Children.Add($sysBdr) | Out-Null
        }

        $grid.Children.Add($namePanel)   | Out-Null
        $grid.Children.Add($pidTxt)      | Out-Null
        $grid.Children.Add($cpuPanel)    | Out-Null
        $grid.Children.Add($ramTxt)      | Out-Null
        $grid.Children.Add($companyTxt)  | Out-Null

        $rowBdr.Child = $grid
        $icProcs.Items.Add($rowBdr) | Out-Null
    }
}

# ------------------------------------------------------------
# Refresh-ProcessList
# Ejecuta Get-HeavyProcesses y actualiza la UI.
# Respeta el toggle de "mostrar sistema".
# ------------------------------------------------------------
$script:procsList = $null

function Refresh-ProcessList {
    $lblProcsStatus.Text = "Actualizando..."
    Flush-UI

    try {
        $showSys = [bool]$chkShowSysProcs.IsChecked
        $procs   = Get-HeavyProcesses -TopN 15 -IncludeSystem $showSys
        $script:procsList = $procs

        # Stats rapidas en el header
        $cpuTotal = [math]::Round(($procs | Measure-Object CpuPct -Sum).Sum, 1)
        $lblProcsCpuTotal.Text = "$cpuTotal%"
        $lblProcsCount.Text    = "$($procs.Count)"

        Render-ProcessList -procList $procs

        $ts = Get-Date -Format "HH:mm:ss"
        $lblProcsStatus.Text = "Actualizado $ts"
    } catch {
        Write-Log "Error al actualizar procesos: $_" "err"
        $lblProcsStatus.Text = "Error — ver consola"
    }
    Flush-UI
}

# ------------------------------------------------------------
# Start-ProcTimer / Stop-ProcTimer
# Arranca o detiene el DispatcherTimer de auto-refresh.
# ------------------------------------------------------------
function Start-ProcTimer {
    if($script:procTimerRunning){ return }
    $script:procTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:procTimer.Interval = [TimeSpan]::FromSeconds($script:procTimerInterval)
    $script:procTimer.Add_Tick({
        try { Refresh-ProcessList } catch {}
    })
    $script:procTimer.Start()
    $script:procTimerRunning      = $true
    $btnToggleProcTimer.Content   = "Auto-refresh ON"
    $btnToggleProcTimer.Foreground= New-Brush "#00C8FF"
}

function Stop-ProcTimer {
    if(-not $script:procTimerRunning){ return }
    try { $script:procTimer.Stop() } catch {}
    $script:procTimerRunning      = $false
    $btnToggleProcTimer.Content   = "Auto-refresh OFF"
    $btnToggleProcTimer.Foreground= New-Brush "#555555"
}

# ------------------------------------------------------------
# Eventos del panel de procesos
# ------------------------------------------------------------
$btnRefreshProcs.Add_Click({ Refresh-ProcessList })

$btnToggleProcTimer.Add_Click({
    if($script:procTimerRunning){ Stop-ProcTimer }
    else                        { Start-ProcTimer; Refresh-ProcessList }
})

$chkShowSysProcs.Add_Click({ Refresh-ProcessList })

# ============================================================
# MODULO F1.7 / F1.8 — DISPOSITIVOS CON PROBLEMAS / DRIVERS
# ============================================================

$script:_driverList    = $null
$script:devicesScanned = $false

function Get-ProblemDevices {
    try {
        $devs = @(Get-PnpDevice -EA SilentlyContinue |
            Where-Object { $_.Status -ne "OK" })
        return $devs
    } catch { return @() }
}

function Update-DeviceBadge {
    param([int]$problemCount)
    $badgeDeviceProblems.Visibility = if($problemCount -gt 0){
        [Windows.Visibility]::Visible
    } else {
        [Windows.Visibility]::Collapsed
    }
    Flush-UI
}

function Render-ProblemDevices {
    param($devices)
    $icDeviceProblems.Items.Clear()

    if(-not $devices -or @($devices).Count -eq 0){
        $icDeviceProblems.Items.Add((New-EmptyState `
            ([char]0x2713) `
            "Sin problemas detectados" `
            "Todos los dispositivos responden correctamente." `
            20)) | Out-Null
        Flush-UI
        return
    }

    foreach($dev in $devices){
        $rowBdr = New-Object Windows.Controls.Border
        $rowBdr.Padding         = New-Object Windows.Thickness(8,6,8,6)
        $rowBdr.BorderThickness = New-Object Windows.Thickness(0,0,0,1)
        $rowBdr.BorderBrush     = New-Brush "#1A1A1A"

        $g = New-Object Windows.Controls.Grid
        foreach($w in @(1, 120, 80)){
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if($w -eq 1){
                [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            } else {
                [Windows.GridLength]::new($w)
            }
            $g.ColumnDefinitions.Add($cd)
        }

        $devName   = if($dev.FriendlyName){ $dev.FriendlyName } else { "(sin nombre)" }
        $statusStr = if($dev.Status)      { "$($dev.Status)"  } else { "Desconocido"  }
        $statusColor = if($statusStr -eq "Error"){ "#EF4444" } else { "#F59E0B" }
        $bgColor     = if($statusStr -eq "Error"){ "#2A0A0A" } else { "#2A1A00" }

        $lblName = New-Object Windows.Controls.TextBlock
        $lblName.Text              = $devName
        $lblName.FontSize          = 12
        $lblName.Foreground        = New-Brush "#CCCCCC"
        $lblName.TextTrimming      = [Windows.TextTrimming]::CharacterEllipsis
        $lblName.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($lblName, 0)

        $statusBdr = New-Object Windows.Controls.Border
        $statusBdr.CornerRadius      = New-Object Windows.CornerRadius(4)
        $statusBdr.Padding           = New-Object Windows.Thickness(6,2,6,2)
        $statusBdr.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $statusBdr.Background        = New-Brush $bgColor
        $statusTxt = New-Object Windows.Controls.TextBlock
        $statusTxt.Text      = $statusStr
        $statusTxt.FontSize  = 11
        $statusTxt.Foreground= New-Brush $statusColor
        $statusBdr.Child     = $statusTxt
        [Windows.Controls.Grid]::SetColumn($statusBdr, 1)

        $codeTxt = New-Object Windows.Controls.TextBlock
        $codeTxt.Text                = "$([int]$dev.ConfigManagerErrorCode)"
        $codeTxt.FontSize            = 11
        $codeTxt.Foreground          = New-Brush "#888888"
        $codeTxt.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $codeTxt.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($codeTxt, 2)

        $g.Children.Add($lblName)   | Out-Null
        $g.Children.Add($statusBdr) | Out-Null
        $g.Children.Add($codeTxt)   | Out-Null
        $rowBdr.Child = $g
        $icDeviceProblems.Items.Add($rowBdr) | Out-Null
    }
    Flush-UI
}

function Scan-DeviceProblems {
    $btnScanDevices.IsEnabled        = $false
    $lblDeviceProblemsStatus.Text    = "Escaneando..."
    Flush-UI
    try {
        $devs = Get-ProblemDevices
        Render-ProblemDevices $devs
        $n = @($devs).Count
        Update-DeviceBadge $n
        $lblDeviceProblemsStatus.Text = if($n -eq 0){ "Sin problemas" } else { "$n dispositivo(s) con problemas" }
    } catch {
        $lblDeviceProblemsStatus.Text = "Error al escanear"
    }
    $btnScanDevices.IsEnabled = $true
    Flush-UI
}

function Render-DriverInventory {
    param($drivers)
    $icDrivers.Items.Clear()

    if(-not $drivers -or @($drivers).Count -eq 0){
        $icDrivers.Items.Add((New-EmptyState `
            ([char]0x2699) `
            "Sin drivers encontrados" `
            "Haz clic en Escanear drivers para cargar el inventario." `
            20)) | Out-Null
        Flush-UI
        return
    }

    $twoYearsAgo = (Get-Date).AddYears(-2)

    foreach($drv in $drivers){
        $rowBdr = New-Object Windows.Controls.Border
        $rowBdr.Padding         = New-Object Windows.Thickness(8,5,8,5)
        $rowBdr.BorderThickness = New-Object Windows.Thickness(0,0,0,1)
        $rowBdr.BorderBrush     = New-Brush "#1A1A1A"

        $isSigned   = $drv.IsSigned -eq $true
        $drvDate    = $null
        $drvDateStr = "--"
        try {
            if($drv.DriverDate){
                $drvDate    = [datetime]$drv.DriverDate
                $drvDateStr = $drvDate.ToString("yyyy-MM-dd")
            }
        } catch {}
        $isOld     = $drvDate -and ($drvDate -lt $twoYearsAgo)
        $rowBgHex  = if(-not $isSigned){ "#1A0000" } elseif($isOld){ "#1A1000" } else { $null }
        if($rowBgHex){ $rowBdr.Background = New-Brush $rowBgHex }

        $g = New-Object Windows.Controls.Grid
        foreach($w in @(1, 120, 110, 80)){
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if($w -eq 1){
                [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            } else {
                [Windows.GridLength]::new($w)
            }
            $g.ColumnDefinitions.Add($cd)
        }

        $lblName = New-Object Windows.Controls.TextBlock
        $lblName.Text              = if($drv.DeviceName){ $drv.DeviceName } else { "(sin nombre)" }
        $lblName.FontSize          = 11
        $lblName.Foreground        = New-Brush "#CCCCCC"
        $lblName.TextTrimming      = [Windows.TextTrimming]::CharacterEllipsis
        $lblName.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($lblName, 0)

        $lblVer = New-Object Windows.Controls.TextBlock
        $lblVer.Text              = if($drv.DriverVersion){ $drv.DriverVersion } else { "--" }
        $lblVer.FontSize          = 11
        $lblVer.Foreground        = New-Brush "#888888"
        $lblVer.TextTrimming      = [Windows.TextTrimming]::CharacterEllipsis
        $lblVer.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($lblVer, 1)

        $dateColor = if($isOld){ "#F59E0B" } else { "#888888" }
        $lblDate = New-Object Windows.Controls.TextBlock
        $lblDate.Text              = $drvDateStr
        $lblDate.FontSize          = 11
        $lblDate.Foreground        = New-Brush $dateColor
        $lblDate.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($lblDate, 2)

        $signedColor = if($isSigned){ "#22C55E" } else { "#EF4444" }
        $signedTxt   = if($isSigned){ "Si" }      else { "No" }
        $lblSigned = New-Object Windows.Controls.TextBlock
        $lblSigned.Text                = $signedTxt
        $lblSigned.FontSize            = 11
        $lblSigned.Foreground          = New-Brush $signedColor
        $lblSigned.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $lblSigned.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($lblSigned, 3)

        $g.Children.Add($lblName)   | Out-Null
        $g.Children.Add($lblVer)    | Out-Null
        $g.Children.Add($lblDate)   | Out-Null
        $g.Children.Add($lblSigned) | Out-Null
        $rowBdr.Child = $g
        $icDrivers.Items.Add($rowBdr) | Out-Null
    }
    Flush-UI
}

function Populate-DriverClassFilter {
    param($drivers)
    $cboDriverClass.Items.Clear()
    $cboDriverClass.Items.Add("Todas las clases") | Out-Null
    $classes = @($drivers |
        Where-Object { $_.DeviceClass } |
        Select-Object -ExpandProperty DeviceClass -Unique |
        Sort-Object)
    foreach($cls in $classes){
        $cboDriverClass.Items.Add($cls) | Out-Null
    }
    $cboDriverClass.SelectedIndex = 0
    $cboDriverClass.IsEnabled     = $true
}

function Scan-DriverInventory {
    $btnScanDrivers.IsEnabled = $false
    $lblDriversStatus.Text    = "Escaneando drivers..."
    Flush-UI
    try {
        $script:_driverList = @(Get-CimInstance Win32_PnPSignedDriver -EA SilentlyContinue |
            Where-Object { $_.DeviceName -ne $null } |
            Sort-Object DeviceName)
        Populate-DriverClassFilter $script:_driverList
        Render-DriverInventory $script:_driverList
        $n        = $script:_driverList.Count
        $unsigned = @($script:_driverList | Where-Object { $_.IsSigned -ne $true }).Count
        $lblDriversStatus.Text = "$n drivers"
        if($unsigned -gt 0){ $lblDriversStatus.Text += "  |  $unsigned sin firma" }
    } catch {
        $lblDriversStatus.Text = "Error al escanear"
    }
    $btnScanDrivers.IsEnabled = $true
    Flush-UI
}

# ------------------------------------------------------------
# Eventos panel Drivers
# ------------------------------------------------------------
$btnScanDevices.Add_Click({ Scan-DeviceProblems })
$btnOpenDevMgmt.Add_Click({ Start-Process devmgmt.msc })
$btnScanDrivers.Add_Click({ Scan-DriverInventory })
$cboDriverClass.Add_SelectionChanged({
    if(-not $script:_driverList){ return }
    $filterClass = $cboDriverClass.SelectedItem
    if($filterClass -and $filterClass -ne "Todas las clases"){
        $filtered = @($script:_driverList | Where-Object { $_.DeviceClass -eq $filterClass })
    } else {
        $filtered = $script:_driverList
    }
    Render-DriverInventory $filtered
})

# F2.4: handler unico para todos los tabs — evita acumulacion de handlers en WPF
$mainTabs.Add_SelectionChanged({
    param($s, $e)
    if($e.Source -ne $mainTabs){ return }
    try {
        $selected = $mainTabs.SelectedItem
        if(-not $selected){ return }
        $header = $selected.Header
        if($header -eq "Herramientas"){
            # F0.5: NO auto-arrancar el timer. Solo un fetch inicial unico.
            if(-not $script:procTimerRunning){ Refresh-ProcessList }
            # F1.7: escanear dispositivos al entrar por primera vez
            if(-not $script:devicesScanned){
                $script:devicesScanned = $true
                Scan-DeviceProblems
                Render-DriverInventory @()
            }
        } else {
            # Pausar proc timer al salir de Herramientas para no consumir CPU en background
            if($script:procTimerRunning){ Stop-ProcTimer }
            # Redibujar barras de score al entrar a Info del sistema (ActualWidth disponible solo cuando el tab es visible)
            if($header -eq "Info del sistema"){
                $window.Dispatcher.BeginInvoke(
                    [action]{ Update-ScorePanel },
                    [Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
            }
            # Redibujar historial de scores al entrar a Historial
            if($header -eq "Historial"){
                $window.Dispatcher.BeginInvoke(
                    [action]{ Render-ScoreHistory },
                    [Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
            }
        }
    } catch {}
})

# ============================================================
# SETTINGS UI
# ============================================================

$script:retentionMap = @{ 0=7; 1=14; 2=30; 3=60; 4=0 }
$script:refreshMap   = @{ 0=1; 1=3; 2=5; 3=10 }

function Render-SettingsUI {
    try {
        $cboTheme.SelectedIndex = if($script:settings.Theme -eq "auto"){ 2 } `
                               elseif($script:settings.Theme -eq "light"){ 1 } else { 0 }
        $cboCloseAction.SelectedIndex = if($script:settings.CloseAction -eq "minimize"){ 1 } else { 0 }
        $chkShowSplash.IsChecked = $script:settings.ShowSplash
        $refreshIdx = ($script:refreshMap.GetEnumerator() |
            Where-Object { $_.Value -eq $script:settings.ProcRefreshSec } |
            Select-Object -First 1).Key
        $cboProcRefresh.SelectedIndex = if($null -ne $refreshIdx){ [int]$refreshIdx } else { 1 }
        $chkRunAtStartup.IsChecked = $script:settings.RunAtStartup
        $lblBackupPath.Text = $script:settings.BackupRoot
        $retIdx = ($script:retentionMap.GetEnumerator() |
            Where-Object { $_.Value -eq $script:settings.BackupRetainDays } |
            Select-Object -First 1).Key
        $cboBackupRetention.SelectedIndex = if($null -ne $retIdx){ [int]$retIdx } else { 2 }
        # F2.20
        try { if($script:chkGameAffinity){ $script:chkGameAffinity.IsChecked = $script:settings.GameAffinityEnabled } } catch {}
        $lblVersionAbout.Text = "v$VERSION"
        try {
            $sessions = Get-BackupSessions
            $totalMB  = 0
            try {
                $totalMB = [math]::Round(
                    (Get-ChildItem $script:settings.BackupRoot -Recurse -EA SilentlyContinue |
                     Measure-Object Length -Sum).Sum / 1MB, 1)
            } catch {}
            $lblBackupCount.Text = "$($sessions.Count) sesion(es) guardada(s)  |  $totalMB MB en disco"
        } catch { $lblBackupCount.Text = "Sin sesiones guardadas" }
        try {
            $sessions    = Get-BackupSessions
            $totalSess   = $sessions.Count
            $totalLibMB  = ($sessions | Measure-Object { $_.freedMB } -Sum -EA SilentlyContinue).Sum
            $bestScore   = ($sessions | Measure-Object { $_.meta.scoreAfter } -Maximum -EA SilentlyContinue).Maximum
            $firstDate   = $sessions | Select-Object -Last 1
            $daysSince   = 0
            if($firstDate -and $firstDate.timestamp){
                try {
                    $d = [datetime]::ParseExact($firstDate.timestamp,
                         "yyyy-MM-dd HH:mm:ss", $null)
                    $daysSince = ([datetime]::Now - $d).Days
                } catch {}
            }
            $lblStatsSessions.Text = "$totalSess"
            $lblStatsMB.Text       = "$totalLibMB"
            $lblStatsScore.Text    = if($bestScore){ "$bestScore" } else { "--" }
            $lblStatsDays.Text     = "$daysSince"
        } catch {}
    } catch {}
    Flush-UI
}

$cboTheme.Add_SelectionChanged({
    $script:settings.Theme = if($cboTheme.SelectedIndex -eq 1){ "light" } `
                             elseif($cboTheme.SelectedIndex -eq 2){ "auto" } `
                             else { "dark" }
    Save-Settings
    Apply-Theme
})

$cboCloseAction.Add_SelectionChanged({
    $script:settings.CloseAction = if($cboCloseAction.SelectedIndex -eq 1){ "minimize" } else { "exit" }
    Save-Settings
})

$chkShowSplash.Add_Click({
    $script:settings.ShowSplash = [bool]$chkShowSplash.IsChecked
    Save-Settings
})

$cboProcRefresh.Add_SelectionChanged({
    $idx = $cboProcRefresh.SelectedIndex
    if($script:refreshMap.ContainsKey($idx)){
        $script:settings.ProcRefreshSec   = $script:refreshMap[$idx]
        $script:procTimerInterval          = $script:refreshMap[$idx]
        if($script:procTimer){
            $script:procTimer.Interval = [TimeSpan]::FromSeconds($script:refreshMap[$idx])
        }
        Save-Settings
    }
})

$chkRunAtStartup.Add_Click({
    $script:settings.RunAtStartup = [bool]$chkRunAtStartup.IsChecked
    Apply-Settings
    Save-Settings
})

$btnChangeBackupPath.Add_Click({
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description   = "Selecciona la carpeta para guardar los backups de WinBoost"
        $dialog.SelectedPath  = $script:settings.BackupRoot
        $dialog.ShowNewFolderButton = $true
        if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
            $script:settings.BackupRoot = $dialog.SelectedPath
            $lblBackupPath.Text         = $dialog.SelectedPath
            Save-Settings
        }
    } catch {}
})

$cboBackupRetention.Add_SelectionChanged({
    $idx = $cboBackupRetention.SelectedIndex
    if($script:retentionMap.ContainsKey($idx)){
        $script:settings.BackupRetainDays = $script:retentionMap[$idx]
        Save-Settings
    }
})

$btnOpenBackups.Add_Click({
    try {
        $path = $script:settings.BackupRoot
        if(-not (Test-Path $path)){ New-Item -ItemType Directory -Path $path -Force | Out-Null }
        Start-Process "explorer.exe" $path
    } catch {}
})

$btnCheckUpdatesSettings.Add_Click({ Check-ForUpdates })

$btnResetSettings.Add_Click({
    $confirm = [Windows.MessageBox]::Show(
        "Restablecer todos los ajustes a sus valores por defecto?",
        "WinBoost - Restablecer",
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Warning)
    if($confirm -ne [Windows.MessageBoxResult]::Yes){ return }
    $script:settings = [PSCustomObject]@{
        Theme               = "dark"
        Language            = "es"
        CloseAction         = "exit"
        ShowSplash          = $true
        ProcRefreshSec      = 3
        RunAtStartup        = $false
        BackupRoot          = $BACKUP_ROOT
        BackupRetainDays    = 30
        TechnicianName      = ""
        GameAffinityEnabled = $false
    }
    Save-Settings
    Apply-Settings
    Render-SettingsUI
})

# ============================================================
# F2.17 — Detector de optimizadores previos
# ============================================================

function Get-PreviousOptimizers {
    $knownOptimizers = @(
        @{ Pattern = "CCleaner";             Name = "CCleaner (Piriform)" },
        @{ Pattern = "IObit";                Name = "IObit Advanced SystemCare" },
        @{ Pattern = "Advanced SystemCare";  Name = "IObit Advanced SystemCare" },
        @{ Pattern = "Wise Registry Cleaner";Name = "Wise Registry Cleaner" },
        @{ Pattern = "Wise Care 365";        Name = "Wise Care 365" },
        @{ Pattern = "Wise Disk Cleaner";    Name = "Wise Disk Cleaner" },
        @{ Pattern = "AVG PC TuneUp";        Name = "AVG PC TuneUp" },
        @{ Pattern = "AVG TuneUp";           Name = "AVG TuneUp" },
        @{ Pattern = "PC SpeedUp";           Name = "PC SpeedUp" },
        @{ Pattern = "SlimCleaner";          Name = "SlimCleaner" },
        @{ Pattern = "Glary Utilities";      Name = "Glary Utilities" },
        @{ Pattern = "Auslogics";            Name = "Auslogics BoostSpeed" },
        @{ Pattern = "RegClean Pro";         Name = "RegClean Pro" },
        @{ Pattern = "System Mechanic";      Name = "System Mechanic" },
        @{ Pattern = "CleanMyPC";            Name = "CleanMyPC" }
    )
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $found = [System.Collections.Generic.List[string]]::new()
    foreach($rp in $regPaths){
        try {
            $keys = Get-ChildItem $rp -ErrorAction SilentlyContinue
            foreach($key in $keys){
                $dn = $key.GetValue("DisplayName","")
                if([string]::IsNullOrWhiteSpace($dn)){ continue }
                foreach($opt in $knownOptimizers){
                    if($dn -like "*$($opt.Pattern)*"){
                        if(-not $found.Contains($opt.Name)){ $found.Add($opt.Name) }
                    }
                }
            }
        } catch {}
    }
    return $found
}

function Show-OptimizerBanner {
    try {
        $detected = Get-PreviousOptimizers
        if($detected.Count -eq 0){ return }

        $optTab   = $mainTabs.Items[0]
        $optScrl  = $optTab.Content
        $optSp    = $optScrl.Content

        $bannerBdr = New-Object Windows.Controls.Border
        $bannerBdr.Background      = New-Brush "#1C1400"
        $bannerBdr.BorderBrush     = New-Brush "#F59E0B"
        $bannerBdr.BorderThickness = New-Object Windows.Thickness(1)
        $bannerBdr.CornerRadius    = New-Object Windows.CornerRadius(8)
        $bannerBdr.Padding         = New-Object Windows.Thickness(14,10,14,10)
        $bannerBdr.Margin          = New-Object Windows.Thickness(0,0,0,14)

        $bannerGrid = New-Object Windows.Controls.Grid
        $bcIcon = New-Object Windows.Controls.ColumnDefinition; $bcIcon.Width = [Windows.GridLength]::new(28)
        $bcText = New-Object Windows.Controls.ColumnDefinition; $bcText.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $bcDism = New-Object Windows.Controls.ColumnDefinition; $bcDism.Width = [Windows.GridLength]::new(28)
        $bannerGrid.ColumnDefinitions.Add($bcIcon) | Out-Null
        $bannerGrid.ColumnDefinitions.Add($bcText) | Out-Null
        $bannerGrid.ColumnDefinitions.Add($bcDism) | Out-Null

        $iconTxt = New-Object Windows.Controls.TextBlock
        $iconTxt.Text              = [char]0x26A0
        $iconTxt.FontSize          = 16
        $iconTxt.Foreground        = New-Brush "#F59E0B"
        $iconTxt.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($iconTxt, 0)

        $textSp = New-Object Windows.Controls.StackPanel
        $textSp.Margin = New-Object Windows.Thickness(8,0,8,0)
        [Windows.Controls.Grid]::SetColumn($textSp, 1)

        $titleTb = New-Object Windows.Controls.TextBlock
        $titleTb.Text       = "Optimizadores de terceros detectados"
        $titleTb.FontSize   = 12
        $titleTb.FontWeight = [Windows.FontWeights]::SemiBold
        $titleTb.Foreground = New-Brush "#F59E0B"
        $titleTb.Margin     = New-Object Windows.Thickness(0,0,0,3)

        $nameList = ($detected | ForEach-Object { "- $_" }) -join "  |  "
        $nameTb = New-Object Windows.Controls.TextBlock
        $nameTb.Text         = $nameList
        $nameTb.FontSize     = 11
        $nameTb.Foreground   = New-Brush "#AAAAAA"
        $nameTb.TextWrapping = [Windows.TextWrapping]::Wrap
        $nameTb.Margin       = New-Object Windows.Thickness(0,0,0,4)

        $descTb = New-Object Windows.Controls.TextBlock
        $descTb.Text         = "Estos programas pueden interferir con las optimizaciones de WinBoost o revertirlas. Se recomienda desinstalarlos antes de continuar."
        $descTb.FontSize     = 11
        $descTb.Foreground   = New-Brush "#888888"
        $descTb.TextWrapping = [Windows.TextWrapping]::Wrap

        $textSp.Children.Add($titleTb) | Out-Null
        $textSp.Children.Add($nameTb)  | Out-Null
        $textSp.Children.Add($descTb)  | Out-Null

        $dismissBtn = New-Object Windows.Controls.Button
        $dismissBtn.Content           = [char]0x2715
        $dismissBtn.FontSize          = 13
        $dismissBtn.Background        = [Windows.Media.Brushes]::Transparent
        $dismissBtn.Foreground        = New-Brush "#888888"
        $dismissBtn.BorderThickness   = New-Object Windows.Thickness(0)
        $dismissBtn.Padding           = New-Object Windows.Thickness(4)
        $dismissBtn.VerticalAlignment = [Windows.VerticalAlignment]::Top
        $dismissBtn.Cursor            = [Windows.Input.Cursors]::Hand
        [Windows.Controls.Grid]::SetColumn($dismissBtn, 2)

        $capturedBanner = $bannerBdr
        $dismissBtn.Add_Click({ $capturedBanner.Visibility = [Windows.Visibility]::Collapsed })

        $bannerGrid.Children.Add($iconTxt)    | Out-Null
        $bannerGrid.Children.Add($textSp)     | Out-Null
        $bannerGrid.Children.Add($dismissBtn) | Out-Null
        $bannerBdr.Child = $bannerGrid

        $optSp.Children.Insert(0, $bannerBdr) | Out-Null

        $countStr = if($detected.Count -eq 1){ "1 optimizador" } else { "$($detected.Count) optimizadores" }
        Write-Log "F2.17: $countStr de terceros detectados: $($detected -join ', ')" "info"
    } catch { Write-Log "Error en Show-OptimizerBanner: $_" "err" }
}

# ============================================================
# F2.18 — Tuning Avanzado — funciones helper
# ============================================================

function Get-Win32PrioritySep {
    try {
        $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name Win32PrioritySeparation -EA Stop).Win32PrioritySeparation
        return [int]$val
    } catch { return 2 }
}

function Set-Win32PrioritySep {
    param([int]$Value)
    Save-RegBackup "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySep_backup"
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" $Value "DWord"
}

function Get-HagsState {
    try {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name HwSchMode -EA Stop).HwSchMode
        return ([int]$v -eq 2)
    } catch { return $false }
}

function Set-HagsState {
    param([bool]$Enable)
    $val = if($Enable){ 2 } else { 1 }
    Save-RegBackup "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HAGS_backup"
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" $val "DWord"
}

function Get-CoolingPolicyState {
    # Lee el indice AC de la politica termica via powercfg
    try {
        $raw = & powercfg /query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f 2>$null
        $line = $raw | Where-Object { $_ -match "Current AC Power Setting Index" }
        if($line){ $val = [int]("0x" + ($line -split ":\s*0x")[1].Trim()); return $val }
    } catch {}
    return -1
}

function Set-CoolingPolicy {
    param([int]$Value)  # 0 = Passive, 1 = Active
    try {
        & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f $Value 2>$null
        & powercfg /setdcvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f $Value 2>$null
        & powercfg /setactive SCHEME_CURRENT 2>$null
        return $true
    } catch { return $false }
}

function Get-ExtendedSystemInfo {
    $info = [PSCustomObject]@{
        CpuCores   = 0; CpuThreads = 0; CpuCacheMB = 0
        RamSpeedMHz = 0; RamSlots = 0; RamUsedSlots = 0
        GpuVramMB  = 0; GpuName = ""; GpuDriver = ""
    }
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $info.CpuCores   = [int]$cpu.NumberOfCores
        $info.CpuThreads = [int]$cpu.NumberOfLogicalProcessors
        $info.CpuCacheMB = [math]::Round($cpu.L3CacheSize / 1024, 1)
    } catch {}
    try {
        $mems = @(Get-CimInstance Win32_PhysicalMemory)
        $info.RamSlots     = (Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1).MemoryDevices
        $info.RamUsedSlots = $mems.Count
        if($mems.Count -gt 0){ $info.RamSpeedMHz = [int]($mems[0].Speed) }
    } catch {}
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1
        if($gpu){
            $info.GpuVramMB = [math]::Round($gpu.AdapterRAM / 1MB, 0)
            $info.GpuName   = $gpu.Name
            $info.GpuDriver = $gpu.DriverVersion
        }
    } catch {}
    return $info
}

function Build-TuningTab {
    try {
        # ---- Crear TabItem y agregarlo a mainTabs ----
        $tuningTab = New-Object Windows.Controls.TabItem
        $tuningTab.Header     = "Tuning Avanzado"
        $tuningTab.Visibility = [Windows.Visibility]::Collapsed  # oculta de la tab bar

        $tuningScroll = New-Object Windows.Controls.ScrollViewer
        $tuningScroll.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto

        $tuningSp = New-Object Windows.Controls.StackPanel
        $tuningSp.Margin = New-Object Windows.Thickness(20,14,20,20)
        $tuningScroll.Content = $tuningSp
        $tuningTab.Content    = $tuningScroll
        $mainTabs.Items.Add($tuningTab) | Out-Null

        # ---- Funcion auxiliar para crear cards de seccion ----
        function New-TuningCard {
            param([string]$Title, [string]$Accent = "#00C8FF")
            $bdr = New-Object Windows.Controls.Border
            $bdr.Background      = $window.FindResource("BrushCard")
            $bdr.BorderBrush     = New-Brush $Accent
            $bdr.BorderThickness = New-Object Windows.Thickness(0,0,0,2)
            $bdr.CornerRadius    = New-Object Windows.CornerRadius(8)
            $bdr.Padding         = New-Object Windows.Thickness(18,14,18,16)
            $bdr.Margin          = New-Object Windows.Thickness(0,0,0,14)
            $sp = New-Object Windows.Controls.StackPanel
            $hdr = New-Object Windows.Controls.TextBlock
            $hdr.Text       = $Title
            $hdr.FontSize   = 10
            $hdr.FontWeight = [Windows.FontWeights]::SemiBold
            $hdr.Foreground = New-Brush $Accent
            $hdr.Margin     = New-Object Windows.Thickness(0,0,0,12)
            $sp.Children.Add($hdr) | Out-Null
            $bdr.Child = $sp
            return [PSCustomObject]@{ Border = $bdr; Panel = $sp }
        }

        # ----------------------------------------------------------------
        # CARD 1 — Scheduler de CPU (Win32PrioritySeparation)
        # ----------------------------------------------------------------
        $c1 = New-TuningCard "SCHEDULER DE CPU"
        $tuningSp.Children.Add($c1.Border) | Out-Null

        $prioOptions = @(
            [PSCustomObject]@{ Label = "Windows default (0x26) - sin cambio"; Value = 38;
                Desc = "Comportamiento estandar de Windows. La mayoria de usuarios no notara diferencia vs los otros valores." },
            [PSCustomObject]@{ Label = "Consistencia (0x16) - prioridad igual a todos los procesos"; Value = 22;
                Desc = "Reduce la ventaja de CPU del proceso en primer plano. Util bajo carga extrema multitarea." },
            [PSCustomObject]@{ Label = "Responsividad (0x24) - prioridad al proceso activo"; Value = 36;
                Desc = "Da mas CPU al proceso en foco. Puede mejorar la sensacion de fluidez en el escritorio." }
        )

        $prioRow = New-Object Windows.Controls.Grid
        $pcA = New-Object Windows.Controls.ColumnDefinition; $pcA.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $pcB = New-Object Windows.Controls.ColumnDefinition; $pcB.Width = [Windows.GridLength]::new(90)
        $prioRow.ColumnDefinitions.Add($pcA) | Out-Null
        $prioRow.ColumnDefinitions.Add($pcB) | Out-Null

        $script:cboPrio = New-Object Windows.Controls.ComboBox
        $script:cboPrio.FontSize  = 12
        $script:cboPrio.Margin    = New-Object Windows.Thickness(0,0,8,0)
        $script:cboPrio.Style     = $window.FindResource("ComboBoxStyle1")
        foreach($opt in $prioOptions){
            $item = New-Object Windows.Controls.ComboBoxItem
            $item.Content = $opt.Label
            $item.Tag     = $opt.Value
            $script:cboPrio.Items.Add($item) | Out-Null
        }
        [Windows.Controls.Grid]::SetColumn($script:cboPrio, 0)

        $btnApplyPrio = New-Object Windows.Controls.Button
        $btnApplyPrio.Content = "Aplicar"
        $btnApplyPrio.Style   = $window.FindResource("BtnMain")
        $btnApplyPrio.Padding = New-Object Windows.Thickness(14,7,14,7)
        [Windows.Controls.Grid]::SetColumn($btnApplyPrio, 1)

        $prioRow.Children.Add($script:cboPrio)  | Out-Null
        $prioRow.Children.Add($btnApplyPrio)    | Out-Null

        $script:lblPrioDesc = New-Object Windows.Controls.TextBlock
        $script:lblPrioDesc.FontSize    = 11
        $script:lblPrioDesc.Foreground  = $window.FindResource("BrushFgMuted")
        $script:lblPrioDesc.TextWrapping = [Windows.TextWrapping]::Wrap
        $script:lblPrioDesc.Margin      = New-Object Windows.Thickness(0,8,0,0)

        $script:lblPrioStatus = New-Object Windows.Controls.TextBlock
        $script:lblPrioStatus.FontSize  = 11
        $script:lblPrioStatus.Margin    = New-Object Windows.Thickness(0,6,0,0)

        # Seleccionar opcion actual
        $curPrio = Get-Win32PrioritySep
        $selIdx  = 0
        for($pi=0; $pi -lt $prioOptions.Count; $pi++){
            if($prioOptions[$pi].Value -eq $curPrio){ $selIdx = $pi; break }
        }
        $script:cboPrio.SelectedIndex = $selIdx
        $script:lblPrioDesc.Text      = $prioOptions[$selIdx].Desc
        $script:lblPrioStatus.Text    = "Valor actual en registro: $curPrio (0x$([Convert]::ToString($curPrio,16).ToUpper()))"
        $script:lblPrioStatus.Foreground = New-Brush "#888888"

        $script:cboPrio.Add_SelectionChanged({
            $idx2 = $script:cboPrio.SelectedIndex
            if($idx2 -ge 0){ $script:lblPrioDesc.Text = $prioOptions[$idx2].Desc }
        })

        $btnApplyPrio.Add_Click({
            $idx3 = $script:cboPrio.SelectedIndex
            if($idx3 -lt 0){ return }
            $newVal = [int]($script:cboPrio.SelectedItem.Tag)
            try {
                Set-Win32PrioritySep -Value $newVal
                $script:lblPrioStatus.Text       = "Aplicado: $newVal (0x$([Convert]::ToString($newVal,16).ToUpper())) - efectivo al reiniciar sesion."
                $script:lblPrioStatus.Foreground = New-Brush "#22C55E"
                Write-Log "Win32PrioritySeparation -> $newVal (0x$([Convert]::ToString($newVal,16).ToUpper()))" "ok"
            } catch {
                $script:lblPrioStatus.Text       = "Error al aplicar: $_"
                $script:lblPrioStatus.Foreground = New-Brush "#EF4444"
            }
            Flush-UI
        })

        $prioNote = New-Object Windows.Controls.TextBlock
        $prioNote.Text         = "Nota: el efecto medible de este parametro es minimo en hardware moderno. No es una palanca de rendimiento real para la mayoria de usuarios."
        $prioNote.FontSize     = 10
        $prioNote.Foreground   = New-Brush "#555555"
        $prioNote.TextWrapping = [Windows.TextWrapping]::Wrap
        $prioNote.Margin       = New-Object Windows.Thickness(0,10,0,0)

        $c1.Panel.Children.Add($prioRow)          | Out-Null
        $c1.Panel.Children.Add($script:lblPrioDesc)   | Out-Null
        $c1.Panel.Children.Add($script:lblPrioStatus) | Out-Null
        $c1.Panel.Children.Add($prioNote)         | Out-Null

        # ----------------------------------------------------------------
        # CARD 2 — HAGS (Hardware-Accelerated GPU Scheduling)
        # ----------------------------------------------------------------
        $c2 = New-TuningCard "ACELERACION GPU HARDWARE (HAGS)" "#A855F7"
        $tuningSp.Children.Add($c2.Border) | Out-Null

        $hagsState = Get-HagsState
        $hagsStateStr = if($hagsState){ "Activo" } else { "Inactivo" }
        $hagsColor    = if($hagsState){ "#22C55E" } else { "#888888" }

        $hagsRow = New-Object Windows.Controls.Grid
        $hcA = New-Object Windows.Controls.ColumnDefinition; $hcA.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $hcB = New-Object Windows.Controls.ColumnDefinition; $hcB.Width = [Windows.GridLength]::new([Windows.GridLength]::Auto)
        $hagsRow.ColumnDefinitions.Add($hcA) | Out-Null
        $hagsRow.ColumnDefinitions.Add($hcB) | Out-Null

        $hagsInfoSp = New-Object Windows.Controls.StackPanel
        [Windows.Controls.Grid]::SetColumn($hagsInfoSp, 0)

        $script:lblHagsState = New-Object Windows.Controls.TextBlock
        $script:lblHagsState.FontSize   = 13
        $script:lblHagsState.FontWeight = [Windows.FontWeights]::SemiBold
        $script:lblHagsState.Foreground = New-Brush $hagsColor
        $script:lblHagsState.Text       = "Estado: $hagsStateStr"
        $script:lblHagsState.Margin     = New-Object Windows.Thickness(0,0,0,4)

        $hagsDescTb = New-Object Windows.Controls.TextBlock
        $hagsDescTb.Text         = "Delega el scheduling de frames de GPU al hardware en lugar del driver de pantalla. Reduce latencia de GPU en juegos y aplicaciones graficas intensivas. Requiere Windows 10 v2004+, GPU compatible y reinicio."
        $hagsDescTb.FontSize     = 11
        $hagsDescTb.Foreground   = $window.FindResource("BrushFgMuted")
        $hagsDescTb.TextWrapping = [Windows.TextWrapping]::Wrap

        $hagsInfoSp.Children.Add($script:lblHagsState) | Out-Null
        $hagsInfoSp.Children.Add($hagsDescTb)           | Out-Null

        $hagsBtnSp = New-Object Windows.Controls.StackPanel
        $hagsBtnSp.Orientation = [Windows.Controls.Orientation]::Vertical
        $hagsBtnSp.Margin      = New-Object Windows.Thickness(16,0,0,0)
        $hagsBtnSp.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($hagsBtnSp, 1)

        $btnHagsOn = New-Object Windows.Controls.Button
        $btnHagsOn.Content = "Activar"
        $btnHagsOn.Style   = $window.FindResource("BtnMain")
        $btnHagsOn.Padding = New-Object Windows.Thickness(14,7,14,7)
        $btnHagsOn.Margin  = New-Object Windows.Thickness(0,0,0,6)
        $btnHagsOn.IsEnabled = -not $hagsState

        $btnHagsOff = New-Object Windows.Controls.Button
        $btnHagsOff.Content  = "Desactivar"
        $btnHagsOff.Style    = $window.FindResource("BtnSec")
        $btnHagsOff.Padding  = New-Object Windows.Thickness(14,7,14,7)
        $btnHagsOff.IsEnabled = $hagsState

        $script:lblHagsResult = New-Object Windows.Controls.TextBlock
        $script:lblHagsResult.FontSize  = 10
        $script:lblHagsResult.Margin    = New-Object Windows.Thickness(0,6,0,0)
        $script:lblHagsResult.TextWrapping = [Windows.TextWrapping]::Wrap

        $btnHagsOn.Add_Click({
            try {
                Set-HagsState -Enable $true
                $script:lblHagsState.Text       = "Estado: Activo"
                $script:lblHagsState.Foreground = New-Brush "#22C55E"
                $script:lblHagsResult.Text      = "Reinicia el equipo para que tenga efecto."
                $script:lblHagsResult.Foreground = New-Brush "#F59E0B"
                $btnHagsOn.IsEnabled  = $false
                $btnHagsOff.IsEnabled = $true
                Write-Log "HAGS activado - reinicio requerido" "ok"
            } catch {
                $script:lblHagsResult.Text       = "Error: $_"
                $script:lblHagsResult.Foreground = New-Brush "#EF4444"
            }
            Flush-UI
        })

        $btnHagsOff.Add_Click({
            try {
                Set-HagsState -Enable $false
                $script:lblHagsState.Text       = "Estado: Inactivo"
                $script:lblHagsState.Foreground = New-Brush "#888888"
                $script:lblHagsResult.Text      = "Reinicia el equipo para que tenga efecto."
                $script:lblHagsResult.Foreground = New-Brush "#F59E0B"
                $btnHagsOn.IsEnabled  = $true
                $btnHagsOff.IsEnabled = $false
                Write-Log "HAGS desactivado - reinicio requerido" "ok"
            } catch {
                $script:lblHagsResult.Text       = "Error: $_"
                $script:lblHagsResult.Foreground = New-Brush "#EF4444"
            }
            Flush-UI
        })

        $hagsBtnSp.Children.Add($btnHagsOn)           | Out-Null
        $hagsBtnSp.Children.Add($btnHagsOff)          | Out-Null
        $hagsBtnSp.Children.Add($script:lblHagsResult)| Out-Null

        $hagsRow.Children.Add($hagsInfoSp) | Out-Null
        $hagsRow.Children.Add($hagsBtnSp)  | Out-Null
        $c2.Panel.Children.Add($hagsRow)   | Out-Null

        # ----------------------------------------------------------------
        # CARD 3 — Politica termica (Cooling Policy)
        # ----------------------------------------------------------------
        $c3 = New-TuningCard "POLITICA TERMICA" "#F59E0B"
        $tuningSp.Children.Add($c3.Border) | Out-Null

        $coolState = Get-CoolingPolicyState
        $coolLabel = if($coolState -eq 1){ "Activa (ventiladores priorizados)" } elseif($coolState -eq 0){ "Pasiva (ahorro antes que temperatura)" } else { "No disponible / plan personalizado" }

        $script:lblCoolState = New-Object Windows.Controls.TextBlock
        $script:lblCoolState.Text       = "Modo actual: $coolLabel"
        $script:lblCoolState.FontSize   = 12
        $script:lblCoolState.FontWeight = [Windows.FontWeights]::SemiBold
        $script:lblCoolState.Foreground = if($coolState -eq 1){ New-Brush "#22C55E" } elseif($coolState -eq 0){ New-Brush "#F59E0B" } else { New-Brush "#888888" }
        $script:lblCoolState.Margin     = New-Object Windows.Thickness(0,0,0,6)

        $coolDescTb = New-Object Windows.Controls.TextBlock
        $coolDescTb.Text         = "Activa: el plan de energia permite maxima frecuencia de CPU y ventiladores para mantener temperatura. Pasiva: el sistema reduce frecuencia de CPU antes de acelerar ventiladores (mas silencioso, algo menos de rendimiento)."
        $coolDescTb.FontSize     = 11
        $coolDescTb.Foreground   = $window.FindResource("BrushFgMuted")
        $coolDescTb.TextWrapping = [Windows.TextWrapping]::Wrap
        $coolDescTb.Margin       = New-Object Windows.Thickness(0,0,0,10)

        $coolBtnRow = New-Object Windows.Controls.StackPanel
        $coolBtnRow.Orientation = [Windows.Controls.Orientation]::Horizontal

        $btnCoolActive = New-Object Windows.Controls.Button
        $btnCoolActive.Content = "Politica Activa"
        $btnCoolActive.Style   = $window.FindResource("BtnMain")
        $btnCoolActive.Padding = New-Object Windows.Thickness(14,7,14,7)
        $btnCoolActive.Margin  = New-Object Windows.Thickness(0,0,8,0)

        $btnCoolPassive = New-Object Windows.Controls.Button
        $btnCoolPassive.Content = "Politica Pasiva"
        $btnCoolPassive.Style   = $window.FindResource("BtnSec")
        $btnCoolPassive.Padding = New-Object Windows.Thickness(14,7,14,7)

        $script:lblCoolResult = New-Object Windows.Controls.TextBlock
        $script:lblCoolResult.FontSize  = 11
        $script:lblCoolResult.Margin    = New-Object Windows.Thickness(0,8,0,0)

        $btnCoolActive.Add_Click({
            $ok = Set-CoolingPolicy -Value 1
            if($ok){
                $script:lblCoolState.Text       = "Modo actual: Activa (ventiladores priorizados)"
                $script:lblCoolState.Foreground = New-Brush "#22C55E"
                $script:lblCoolResult.Text       = "Politica termica activa aplicada."
                $script:lblCoolResult.Foreground = New-Brush "#22C55E"
                Write-Log "Cooling policy -> Activa" "ok"
            } else {
                $script:lblCoolResult.Text       = "No se pudo aplicar. El plan de energia personalizado puede no soportarlo."
                $script:lblCoolResult.Foreground = New-Brush "#EF4444"
            }
            Flush-UI
        })

        $btnCoolPassive.Add_Click({
            $ok = Set-CoolingPolicy -Value 0
            if($ok){
                $script:lblCoolState.Text       = "Modo actual: Pasiva (ahorro antes que temperatura)"
                $script:lblCoolState.Foreground = New-Brush "#F59E0B"
                $script:lblCoolResult.Text       = "Politica termica pasiva aplicada."
                $script:lblCoolResult.Foreground = New-Brush "#22C55E"
                Write-Log "Cooling policy -> Pasiva" "ok"
            } else {
                $script:lblCoolResult.Text       = "No se pudo aplicar. El plan de energia personalizado puede no soportarlo."
                $script:lblCoolResult.Foreground = New-Brush "#EF4444"
            }
            Flush-UI
        })

        $coolBtnRow.Children.Add($btnCoolActive)  | Out-Null
        $coolBtnRow.Children.Add($btnCoolPassive) | Out-Null

        $c3.Panel.Children.Add($script:lblCoolState)  | Out-Null
        $c3.Panel.Children.Add($coolDescTb)           | Out-Null
        $c3.Panel.Children.Add($coolBtnRow)           | Out-Null
        $c3.Panel.Children.Add($script:lblCoolResult) | Out-Null

        # ----------------------------------------------------------------
        # CARD 4 — Info detallada de componentes
        # ----------------------------------------------------------------
        $c4 = New-TuningCard "INFORMACION DE COMPONENTES" "#22C55E"
        $tuningSp.Children.Add($c4.Border) | Out-Null

        $sysExt = Get-ExtendedSystemInfo

        function New-InfoRow {
            param([string]$Lbl, [string]$Val)
            $g = New-Object Windows.Controls.Grid
            $gA = New-Object Windows.Controls.ColumnDefinition; $gA.Width = [Windows.GridLength]::new(160)
            $gB = New-Object Windows.Controls.ColumnDefinition; $gB.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            $g.ColumnDefinitions.Add($gA) | Out-Null
            $g.ColumnDefinitions.Add($gB) | Out-Null
            $g.Margin = New-Object Windows.Thickness(0,0,0,5)
            $lTb = New-Object Windows.Controls.TextBlock
            $lTb.Text       = $Lbl
            $lTb.FontSize   = 12
            $lTb.Foreground = $window.FindResource("BrushFgMuted")
            [Windows.Controls.Grid]::SetColumn($lTb, 0)
            $vTb = New-Object Windows.Controls.TextBlock
            $vTb.Text       = $Val
            $vTb.FontSize   = 12
            $vTb.Foreground = New-Brush "#EEEEEE"
            $vTb.TextWrapping = [Windows.TextWrapping]::Wrap
            [Windows.Controls.Grid]::SetColumn($vTb, 1)
            $g.Children.Add($lTb) | Out-Null
            $g.Children.Add($vTb) | Out-Null
            return $g
        }

        $cpuCoreStr  = "$($sysExt.CpuCores) nucleos / $($sysExt.CpuThreads) hilos"
        $cpuCacheStr = if($sysExt.CpuCacheMB -gt 0){ "$($sysExt.CpuCacheMB) MB L3" } else { "N/D" }
        $ramSpdStr   = if($sysExt.RamSpeedMHz -gt 0){ "$($sysExt.RamSpeedMHz) MHz" } else { "N/D" }
        $ramSlotStr  = if($sysExt.RamSlots -gt 0){ "$($sysExt.RamUsedSlots) / $($sysExt.RamSlots) slots usados" } else { "$($sysExt.RamUsedSlots) modulos" }
        $gpuVramStr  = if($sysExt.GpuVramMB -gt 0){ "$($sysExt.GpuVramMB) MB ($([math]::Round($sysExt.GpuVramMB/1024,1)) GB)" } else { "N/D" }
        $gpuDrvStr   = if($sysExt.GpuDriver){ $sysExt.GpuDriver } else { "N/D" }
        $hagsInfoStr = if(Get-HagsState){ "Si (activo)" } else { "No (inactivo)" }

        $c4.Panel.Children.Add((New-InfoRow "CPU - Nucleos/Hilos:" $cpuCoreStr))   | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "CPU - Cache L3:"      $cpuCacheStr))  | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "RAM - Velocidad:"      $ramSpdStr))   | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "RAM - Slots:"          $ramSlotStr))  | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "GPU:"                  $sysExt.GpuName)) | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "GPU - VRAM:"           $gpuVramStr))  | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "GPU - Driver:"         $gpuDrvStr))   | Out-Null
        $c4.Panel.Children.Add((New-InfoRow "HAGS:"                 $hagsInfoStr)) | Out-Null

        # ----------------------------------------------------------------
        # CARD 5 — Limpieza del Driver Store (F2.19)
        # ----------------------------------------------------------------
        $c5 = New-TuningCard "LIMPIEZA DEL DRIVER STORE" "#06B6D4"
        $tuningSp.Children.Add($c5.Border) | Out-Null

        $drvDescTb = New-Object Windows.Controls.TextBlock
        $drvDescTb.Text         = "Detecta versiones antiguas del Driver Store de Windows (paquetes oem*.inf duplicados por el mismo driver con multiples versiones). Solo muestra duplicados - los drivers sin copia mas nueva no aparecen. Requiere hacer backup antes de eliminar."
        $drvDescTb.FontSize     = 11
        $drvDescTb.Foreground   = $window.FindResource("BrushFgMuted")
        $drvDescTb.TextWrapping = [Windows.TextWrapping]::Wrap
        $drvDescTb.Margin       = New-Object Windows.Thickness(0,0,0,10)
        $c5.Panel.Children.Add($drvDescTb) | Out-Null

        # Fila de botones de accion
        $drvBtnRow = New-Object Windows.Controls.StackPanel
        $drvBtnRow.Orientation = [Windows.Controls.Orientation]::Horizontal
        $drvBtnRow.Margin      = New-Object Windows.Thickness(0,0,0,10)

        $script:btnScanDrivers = New-Object Windows.Controls.Button
        $script:btnScanDrivers.Content = "Escanear drivers"
        $script:btnScanDrivers.Style   = $window.FindResource("BtnSec")
        $script:btnScanDrivers.Padding = New-Object Windows.Thickness(14,7,14,7)
        $script:btnScanDrivers.Margin  = New-Object Windows.Thickness(0,0,8,0)

        $script:btnDriverBackup = New-Object Windows.Controls.Button
        $script:btnDriverBackup.Content   = "Exportar backup de drivers"
        $script:btnDriverBackup.Style     = $window.FindResource("BtnSec")
        $script:btnDriverBackup.Padding   = New-Object Windows.Thickness(14,7,14,7)
        $script:btnDriverBackup.Margin    = New-Object Windows.Thickness(0,0,8,0)
        $script:btnDriverBackup.IsEnabled = $false

        $script:btnDriverDelete = New-Object Windows.Controls.Button
        $script:btnDriverDelete.Content   = "Eliminar seleccionados"
        $script:btnDriverDelete.Style     = $window.FindResource("BtnDanger")
        $script:btnDriverDelete.Padding   = New-Object Windows.Thickness(14,7,14,7)
        $script:btnDriverDelete.IsEnabled = $false

        $drvBtnRow.Children.Add($script:btnScanDrivers)  | Out-Null
        $drvBtnRow.Children.Add($script:btnDriverBackup) | Out-Null
        $drvBtnRow.Children.Add($script:btnDriverDelete) | Out-Null
        $c5.Panel.Children.Add($drvBtnRow) | Out-Null

        $script:lblDriverStatus = New-Object Windows.Controls.TextBlock
        $script:lblDriverStatus.FontSize  = 11
        $script:lblDriverStatus.Margin    = New-Object Windows.Thickness(0,0,0,8)
        $c5.Panel.Children.Add($script:lblDriverStatus) | Out-Null

        # Lista de drivers obsoletos
        $drvListScroll = New-Object Windows.Controls.ScrollViewer
        $drvListScroll.MaxHeight = 240
        $drvListScroll.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
        $drvListScroll.Visibility = [Windows.Visibility]::Collapsed

        $script:icDrivers = New-Object Windows.Controls.ItemsControl
        $script:icDrivers.Margin = New-Object Windows.Thickness(0)
        $drvListScroll.Content   = $script:icDrivers
        $c5.Panel.Children.Add($drvListScroll) | Out-Null

        $script:driverPackages   = @()
        $script:driverBackupDone = $false

        # Funcion de parseo de pnputil
        function Parse-PnpUtilOutput {
            param([string[]]$Lines)
            $packages = [System.Collections.Generic.List[object]]::new()
            $current  = $null
            foreach($line in $Lines){
                $line = $line.Trim()
                if([string]::IsNullOrWhiteSpace($line)){
                    if($current -ne $null){ $packages.Add($current); $current = $null }
                    continue
                }
                if($line -match '^Published Name\s*:\s*(.+)$'){
                    $current = [PSCustomObject]@{
                        PublishedName   = $Matches[1].Trim()
                        OriginalName    = ""
                        ProviderName    = ""
                        ClassName       = ""
                        DriverDate      = ""
                        DriverVersion   = ""
                        SignerName      = ""
                    }
                } elseif($current -ne $null) {
                    if   ($line -match '^Original Name\s*:\s*(.+)$')  { $current.OriginalName  = $Matches[1].Trim() }
                    elseif($line -match '^Provider Name\s*:\s*(.+)$') { $current.ProviderName  = $Matches[1].Trim() }
                    elseif($line -match '^Class Name\s*:\s*(.+)$')    { $current.ClassName     = $Matches[1].Trim() }
                    elseif($line -match '^Driver Date\s*:\s*(.+)$')   { $current.DriverDate    = $Matches[1].Trim() }
                    elseif($line -match '^Driver Version\s*:\s*(.+)$'){ $current.DriverVersion = $Matches[1].Trim() }
                    elseif($line -match '^Signer Name\s*:\s*(.+)$')   { $current.SignerName    = $Matches[1].Trim() }
                }
            }
            if($current -ne $null){ $packages.Add($current) }
            return $packages
        }

        function Get-ObsoleteDriverPackages {
            param([object[]]$Packages)
            $grouped  = $Packages | Group-Object OriginalName
            $obsolete = [System.Collections.Generic.List[object]]::new()
            foreach($grp in $grouped){
                if($grp.Count -lt 2){ continue }
                $sorted = $grp.Group | Sort-Object DriverVersion -Descending
                for($oi=1; $oi -lt $sorted.Count; $oi++){ $obsolete.Add($sorted[$oi]) }
            }
            return $obsolete
        }

        $script:btnScanDrivers.Add_Click({
            $script:btnScanDrivers.IsEnabled    = $false
            $script:btnScanDrivers.Content      = "Escaneando..."
            $script:lblDriverStatus.Text        = "Ejecutando pnputil /enum-drivers..."
            $script:lblDriverStatus.Foreground  = New-Brush "#888888"
            $script:icDrivers.Items.Clear()
            $drvListScroll.Visibility           = [Windows.Visibility]::Collapsed
            Flush-UI

            $script:drvScanJob = Start-Job -ScriptBlock {
                $out = & pnputil /enum-drivers 2>$null
                return $out
            }

            $script:drvScanTimer = New-Object Windows.Threading.DispatcherTimer
            $script:drvScanTimer.Interval = [TimeSpan]::FromSeconds(2)
            $script:drvScanTimer.Add_Tick({
                if($script:drvScanJob.State -notin @("Completed","Failed","Stopped")){ return }
                $this.Stop()
                try {
                    $rawOut = Receive-Job $script:drvScanJob -ErrorAction SilentlyContinue
                    Remove-Job $script:drvScanJob -Force -ErrorAction SilentlyContinue
                    $script:drvScanJob = $null

                    $allPkgs = Parse-PnpUtilOutput -Lines $rawOut
                    $script:driverPackages = @(Get-ObsoleteDriverPackages -Packages $allPkgs)

                    $script:icDrivers.Items.Clear()
                    if($script:driverPackages.Count -eq 0){
                        $script:lblDriverStatus.Text       = "No se encontraron drivers obsoletos en el Driver Store."
                        $script:lblDriverStatus.Foreground = New-Brush "#22C55E"
                        $script:btnDriverBackup.IsEnabled  = $false
                        $drvListScroll.Visibility          = [Windows.Visibility]::Collapsed
                    } else {
                        foreach($pkg in $script:driverPackages){
                            $rowBdr = New-Object Windows.Controls.Border
                            $rowBdr.Padding         = New-Object Windows.Thickness(8,5,8,5)
                            $rowBdr.Margin          = New-Object Windows.Thickness(0,0,0,2)
                            $rowBdr.Background      = New-Brush "#111111"
                            $rowBdr.CornerRadius    = New-Object Windows.CornerRadius(4)

                            $rowGrid = New-Object Windows.Controls.Grid
                            $rgA = New-Object Windows.Controls.ColumnDefinition; $rgA.Width = [Windows.GridLength]::new([Windows.GridLength]::Auto)
                            $rgB = New-Object Windows.Controls.ColumnDefinition; $rgB.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
                            $rgC = New-Object Windows.Controls.ColumnDefinition; $rgC.Width = [Windows.GridLength]::new(100)
                            $rgD = New-Object Windows.Controls.ColumnDefinition; $rgD.Width = [Windows.GridLength]::new(90)
                            $rowGrid.ColumnDefinitions.Add($rgA) | Out-Null
                            $rowGrid.ColumnDefinitions.Add($rgB) | Out-Null
                            $rowGrid.ColumnDefinitions.Add($rgC) | Out-Null
                            $rowGrid.ColumnDefinitions.Add($rgD) | Out-Null

                            $chk = New-Object Windows.Controls.CheckBox
                            $chk.IsChecked = $false
                            $chk.Margin    = New-Object Windows.Thickness(0,0,8,0)
                            $chk.VerticalAlignment = [Windows.VerticalAlignment]::Center
                            [Windows.Controls.Grid]::SetColumn($chk, 0)

                            $nameTb = New-Object Windows.Controls.TextBlock
                            $nameTb.Text      = "$($pkg.PublishedName)  $($pkg.OriginalName)"
                            $nameTb.FontSize  = 11
                            $nameTb.Foreground = New-Brush "#DDDDDD"
                            $nameTb.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
                            $nameTb.VerticalAlignment = [Windows.VerticalAlignment]::Center
                            [Windows.Controls.Grid]::SetColumn($nameTb, 1)

                            $verTb = New-Object Windows.Controls.TextBlock
                            $verTb.Text      = $pkg.DriverVersion
                            $verTb.FontSize  = 10
                            $verTb.Foreground = New-Brush "#888888"
                            $verTb.VerticalAlignment = [Windows.VerticalAlignment]::Center
                            [Windows.Controls.Grid]::SetColumn($verTb, 2)

                            $dateTb = New-Object Windows.Controls.TextBlock
                            $dateTb.Text      = $pkg.DriverDate
                            $dateTb.FontSize  = 10
                            $dateTb.Foreground = New-Brush "#666666"
                            $dateTb.VerticalAlignment = [Windows.VerticalAlignment]::Center
                            [Windows.Controls.Grid]::SetColumn($dateTb, 3)

                            $rowGrid.Children.Add($chk)    | Out-Null
                            $rowGrid.Children.Add($nameTb) | Out-Null
                            $rowGrid.Children.Add($verTb)  | Out-Null
                            $rowGrid.Children.Add($dateTb) | Out-Null
                            $rowBdr.Child = $rowGrid
                            $script:icDrivers.Items.Add($rowBdr) | Out-Null
                        }
                        $script:lblDriverStatus.Text       = "$($script:driverPackages.Count) driver(s) obsoleto(s) encontrado(s). Haz backup antes de eliminar."
                        $script:lblDriverStatus.Foreground = New-Brush "#F59E0B"
                        $script:btnDriverBackup.IsEnabled  = $true
                        $drvListScroll.Visibility          = [Windows.Visibility]::Visible
                    }
                } catch {
                    $script:lblDriverStatus.Text       = "Error al escanear: $_"
                    $script:lblDriverStatus.Foreground = New-Brush "#EF4444"
                }
                $script:btnScanDrivers.IsEnabled = $true
                $script:btnScanDrivers.Content   = "Escanear drivers"
                Flush-UI
            })
            $script:drvScanTimer.Start()
        })

        $script:btnDriverBackup.Add_Click({
            $script:btnDriverBackup.IsEnabled = $false
            $script:btnDriverBackup.Content   = "Exportando..."
            $script:lblDriverStatus.Text      = "Exportando backup de drivers..."
            $script:lblDriverStatus.Foreground = New-Brush "#888888"
            Flush-UI
            try {
                $drvBackupDir = Join-Path $BACKUP_ROOT ("DriverStore_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
                New-Item -ItemType Directory -Path $drvBackupDir -Force | Out-Null
                Export-WindowsDriver -Online -Destination $drvBackupDir | Out-Null
                $script:driverBackupDone      = $true
                $script:btnDriverDelete.IsEnabled = $true
                $script:lblDriverStatus.Text       = "Backup exportado a: $drvBackupDir"
                $script:lblDriverStatus.Foreground = New-Brush "#22C55E"
                Write-Log "Driver backup exportado: $drvBackupDir" "ok"
            } catch {
                $script:lblDriverStatus.Text       = "Error al exportar backup: $_"
                $script:lblDriverStatus.Foreground = New-Brush "#EF4444"
                $script:btnDriverBackup.IsEnabled  = $true
            }
            $script:btnDriverBackup.Content = "Exportar backup de drivers"
            Flush-UI
        })

        $script:btnDriverDelete.Add_Click({
            if(-not $script:driverBackupDone){ return }
            $toDelete = @()
            for($di=0; $di -lt $script:icDrivers.Items.Count; $di++){
                $rowBdr2  = $script:icDrivers.Items[$di]
                $rowGrid2 = $rowBdr2.Child
                $chk2     = $rowGrid2.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] } | Select-Object -First 1
                if($chk2 -and $chk2.IsChecked){ $toDelete += $script:driverPackages[$di] }
            }
            if($toDelete.Count -eq 0){
                $script:lblDriverStatus.Text       = "Selecciona al menos un driver para eliminar."
                $script:lblDriverStatus.Foreground = New-Brush "#F59E0B"
                Flush-UI; return
            }
            $ok = 0; $fail = 0
            foreach($dpkg in $toDelete){
                try {
                    $result = & pnputil /delete-driver $dpkg.PublishedName /uninstall 2>&1
                    if($LASTEXITCODE -eq 0){
                        $ok++
                        Write-Log "Driver eliminado: $($dpkg.PublishedName) ($($dpkg.OriginalName))" "ok"
                    } else {
                        $fail++
                        Write-Log "No se pudo eliminar $($dpkg.PublishedName): $result" "err"
                    }
                } catch { $fail++; Write-Log "Error eliminando $($dpkg.PublishedName): $_" "err" }
            }
            $script:lblDriverStatus.Text = "$ok eliminado(s) correctamente. $fail error(es). Ejecuta 'Escanear' para actualizar la lista."
            $script:lblDriverStatus.Foreground = if($fail -eq 0){ New-Brush "#22C55E" } else { New-Brush "#F59E0B" }
            $script:btnDriverDelete.IsEnabled = $false
            $script:driverBackupDone = $false
            Flush-UI
        })

        # ---- Agregar nav button al sidebar ----
        $script:navTuning = New-Object Windows.Controls.Button
        $script:navTuning.Style = $window.FindResource("BtnNav")
        $script:navTuning.Margin = New-Object Windows.Thickness(0)

        $navTuningSp = New-Object Windows.Controls.StackPanel
        $navTuningSp.Orientation = [Windows.Controls.Orientation]::Horizontal
        $navTuningSp.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $navTuningIcon = New-Object Windows.Controls.TextBlock
        $navTuningIcon.Text              = [char]0x26A1
        $navTuningIcon.FontFamily        = New-Object Windows.Media.FontFamily("Segoe UI Symbol")
        $navTuningIcon.FontSize          = 15
        $navTuningIcon.Width             = 22
        $navTuningIcon.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $navTuningLabel = New-Object Windows.Controls.TextBlock
        $navTuningLabel.Text              = "Tuning Avanzado"
        $navTuningLabel.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $navTuningSp.Children.Add($navTuningIcon)  | Out-Null
        $navTuningSp.Children.Add($navTuningLabel) | Out-Null
        $script:navTuning.Content = $navTuningSp

        # Insertar en el StackPanel de nav buttons (Parent de navAjustes)
        $navParentSp = $navAjustes.Parent
        $navParentSp.Children.Add($script:navTuning) | Out-Null

        $script:navTuning.Add_Click({ Set-ActiveNav 9 })

        Write-Log "F2.18: Tab Tuning Avanzado cargado (tab indice 9)" "ok"
    } catch { Write-Log "Error al construir tab Tuning Avanzado: $_" "err" }
}

# ============================================================
# Cargar datos al mostrar la ventana
$window.Add_ContentRendered({
    try { Load-Settings    } catch {}
    try { Apply-Settings   } catch {}
    try { Test-TrialStatus } catch {}
    try { Update-TrialBanner   } catch {}
    try { Update-LicenseBadge  } catch {}
    try { Load-StartupItems    } catch {}
    try { Render-StartupItems  } catch {}
    try { Update-RAMDisplay    } catch {}
    try { Render-HistoryItems  } catch {}
    try { Set-ActiveNav 0      } catch {}
    $window.Dispatcher.BeginInvoke(
        [action]{ try { Update-ScoreWidget } catch {} },
        [Windows.Threading.DispatcherPriority]::Background) | Out-Null
    $window.Dispatcher.BeginInvoke(
        [action]{ try { Start-BloatScan } catch {} },
        [Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    # Modulo 15A: primer uso -> lanzar onboarding si corresponde
    $script:isFirstRun = Test-FirstRun
    if ($script:isFirstRun) {
        try { Show-OnboardingDialog } catch {}
    }
    # F2.17 — Detectar optimizadores de terceros y mostrar banner si los hay
    $window.Dispatcher.BeginInvoke(
        [action]{ try { Show-OptimizerBanner } catch {} },
        [Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    # F2.18 — Construir tab Tuning Avanzado
    try { Build-TuningTab } catch { Write-Log "Error Build-TuningTab: $_" "err" }
    $window.Dispatcher.BeginInvoke(
        [action]{ try { Render-SettingsUI } catch {} },
        [Windows.Threading.DispatcherPriority]::Background) | Out-Null
    Cleanup-OldBackups -keepDays $script:settings.BackupRetainDays
    # Redibujar chart con el ancho real del canvas (disponible post-layout)
    $window.Dispatcher.BeginInvoke(
        [action]{ try { Render-ScoreHistory } catch {} },
        [Windows.Threading.DispatcherPriority]::Loaded) | Out-Null

    # F2.14 — Construir card de analisis de espacio en disco programaticamente
    try {
        $htab  = $mainTabs.Items[3]
        $hscrl = $htab.Content
        $hgrid = $hscrl.Content

        $newRowDef        = New-Object Windows.Controls.RowDefinition
        $newRowDef.Height = [Windows.GridLength]::Auto
        $hgrid.RowDefinitions.Add($newRowDef)
        $diskRow = $hgrid.RowDefinitions.Count - 1

        # --- Card outer border ---
        $diskCard = New-Object Windows.Controls.Border
        $diskCard.Background      = $window.FindResource("BrushCard")
        $diskCard.CornerRadius    = New-Object Windows.CornerRadius(8)
        $diskCard.BorderBrush     = $window.FindResource("BrushBorder")
        $diskCard.BorderThickness = New-Object Windows.Thickness(1)
        $diskCard.Margin          = New-Object Windows.Thickness(0,0,0,10)
        $diskCard.Padding         = New-Object Windows.Thickness(0)
        [Windows.Controls.Grid]::SetRow($diskCard, $diskRow)
        [Windows.Controls.Grid]::SetColumnSpan($diskCard, 2)

        # Inner layout: accent strip + content
        $inGrid = New-Object Windows.Controls.Grid
        $inC0   = New-Object Windows.Controls.ColumnDefinition; $inC0.Width = [Windows.GridLength]::new(3)
        $inC1   = New-Object Windows.Controls.ColumnDefinition; $inC1.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $inGrid.ColumnDefinitions.Add($inC0) | Out-Null
        $inGrid.ColumnDefinitions.Add($inC1) | Out-Null

        $accent = New-Object Windows.Controls.Border
        $accent.Background   = New-Brush "#F97316"
        $accent.CornerRadius = New-Object Windows.CornerRadius(8,0,0,8)
        [Windows.Controls.Grid]::SetColumn($accent, 0)

        $contentSp = New-Object Windows.Controls.StackPanel
        $contentSp.Margin = New-Object Windows.Thickness(14,12,14,12)
        [Windows.Controls.Grid]::SetColumn($contentSp, 1)

        # Title
        $titleTxt = New-Object Windows.Controls.TextBlock
        $titleTxt.Text       = "ESPACIO EN DISCO"
        $titleTxt.FontSize   = 11
        $titleTxt.FontWeight = [Windows.FontWeights]::SemiBold
        $titleTxt.Foreground = New-Brush "#F97316"
        $titleTxt.Margin     = New-Object Windows.Thickness(0,0,0,8)

        # Description
        $descTxt = New-Object Windows.Controls.TextBlock
        $descTxt.Text        = "Muestra las 10 carpetas mas pesadas en $SYSDRIVE (excluye Windows). Util para identificar donde se esta consumiendo el espacio."
        $descTxt.FontSize    = 12
        $descTxt.Foreground  = $window.FindResource("BrushFgMuted")
        $descTxt.TextWrapping = [Windows.TextWrapping]::Wrap
        $descTxt.Margin      = New-Object Windows.Thickness(0,0,0,10)

        # Button row
        $btnRow = New-Object Windows.Controls.StackPanel
        $btnRow.Orientation = [Windows.Controls.Orientation]::Horizontal
        $btnRow.Margin      = New-Object Windows.Thickness(0,0,0,12)

        $script:btnDiskSpace = New-Object Windows.Controls.Button
        $script:btnDiskSpace.Content = "Analizar espacio"
        $script:btnDiskSpace.Padding = New-Object Windows.Thickness(18,8,18,8)
        $mainStyle = $window.FindResource("BtnMain")
        $script:btnDiskSpace.Style = $mainStyle

        $statusBdr = New-Object Windows.Controls.Border
        $statusBdr.Background   = $window.FindResource("BrushElev")
        $statusBdr.CornerRadius = New-Object Windows.CornerRadius(4)
        $statusBdr.Padding      = New-Object Windows.Thickness(10,5,10,5)
        $statusBdr.Margin       = New-Object Windows.Thickness(12,0,0,0)
        $statusBdr.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $script:lblDiskSpaceStatus = New-Object Windows.Controls.TextBlock
        $script:lblDiskSpaceStatus.Text       = "Listo"
        $script:lblDiskSpaceStatus.FontSize   = 11
        $script:lblDiskSpaceStatus.Foreground = $window.FindResource("BrushFgDim")
        $statusBdr.Child = $script:lblDiskSpaceStatus

        $btnRow.Children.Add($script:btnDiskSpace) | Out-Null
        $btnRow.Children.Add($statusBdr)           | Out-Null

        # List area
        $listBdr = New-Object Windows.Controls.Border
        $listBdr.Background      = $window.FindResource("BrushDeep")
        $listBdr.CornerRadius    = New-Object Windows.CornerRadius(0,0,8,8)
        $listBdr.BorderBrush     = $window.FindResource("BrushBorder")
        $listBdr.BorderThickness = New-Object Windows.Thickness(0)
        $listBdr.Padding         = New-Object Windows.Thickness(12,8,12,8)
        $listBdr.MinHeight       = 60

        $listScroll = New-Object Windows.Controls.ScrollViewer
        $listScroll.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
        $listScroll.MaxHeight = 300

        $script:icDiskFolders = New-Object Windows.Controls.ItemsControl
        $script:icDiskFolders.Padding = New-Object Windows.Thickness(0)

        # Placeholder text
        $placeholderTxt = New-Object Windows.Controls.TextBlock
        $placeholderTxt.Text              = "Pulsa 'Analizar espacio' para escanear el disco."
        $placeholderTxt.FontSize          = 12
        $placeholderTxt.Foreground        = New-Brush "#444444"
        $placeholderTxt.Margin            = New-Object Windows.Thickness(0,8,0,8)
        $placeholderTxt.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $script:icDiskFolders.Items.Add($placeholderTxt) | Out-Null

        $listScroll.Content = $script:icDiskFolders
        $listBdr.Child      = $listScroll

        $contentSp.Children.Add($titleTxt)  | Out-Null
        $contentSp.Children.Add($descTxt)   | Out-Null
        $contentSp.Children.Add($btnRow)    | Out-Null
        $contentSp.Children.Add($listBdr)   | Out-Null

        $inGrid.Children.Add($accent)    | Out-Null
        $inGrid.Children.Add($contentSp) | Out-Null
        $diskCard.Child = $inGrid
        $hgrid.Children.Add($diskCard) | Out-Null

        # --- Evento del boton ---
        $script:btnDiskSpace.Add_Click({
            if($script:diskJob -ne $null){ return }
            $script:btnDiskSpace.IsEnabled         = $false
            $script:btnDiskSpace.Content           = "Escaneando..."
            $script:lblDiskSpaceStatus.Text        = "Iniciando escaneo..."
            $script:icDiskFolders.Items.Clear()
            Flush-UI

            $sdCapture = $SYSDRIVE
            $winCapture = [System.IO.Path]::Combine($env:SystemRoot, "")
            $script:diskJob = Start-Job -ScriptBlock {
                param($sd, $win)
                $excludePaths = @(
                    [System.IO.Path]::Combine($win, "WinSxS"),
                    [System.IO.Path]::Combine($win, "Installer"),
                    "$sd\System Volume Information",
                    "$sd\`$Recycle.Bin"
                )
                $results = [System.Collections.Generic.List[object]]::new()
                try { $dirs = [System.IO.Directory]::GetDirectories($sd) } catch { $dirs = @() }
                foreach($dir in $dirs){
                    if($dir -ieq $win.TrimEnd('\')){ continue }
                    $skip = $false
                    foreach($ex in $excludePaths){
                        if($dir.StartsWith($ex, [System.StringComparison]::OrdinalIgnoreCase)){
                            $skip = $true; break
                        }
                    }
                    if($skip){ continue }
                    try {
                        $sz = 0L
                        $enum = [System.IO.Directory]::EnumerateFiles($dir,"*",[System.IO.SearchOption]::AllDirectories)
                        foreach($f in $enum){
                            try { $sz += (New-Object System.IO.FileInfo $f).Length } catch {}
                        }
                        if($sz -gt 0){
                            $results.Add([PSCustomObject]@{
                                Name      = [System.IO.Path]::GetFileName($dir)
                                SizeBytes = $sz
                                SizeGB    = [math]::Round($sz / 1GB, 2)
                                SizeMB    = [math]::Round($sz / 1MB, 0)
                            })
                        }
                    } catch {}
                }
                $results | Sort-Object SizeBytes -Descending | Select-Object -First 10
            } -ArgumentList $sdCapture, $winCapture

            $script:diskTimer = New-Object Windows.Threading.DispatcherTimer
            $script:diskTimer.Interval = [TimeSpan]::FromSeconds(3)
            $script:diskTimer.Add_Tick({
                if($script:diskJob -and $script:diskJob.State -eq "Running"){
                    $elapsed = [math]::Round(([DateTime]::Now - $script:diskJob.PSBeginTime).TotalSeconds, 0)
                    $script:lblDiskSpaceStatus.Text = "Escaneando... ${elapsed}s"
                    Flush-UI
                    return
                }
                $script:diskTimer.Stop()
                $folders = $null
                try { $folders = @(Receive-Job $script:diskJob -EA SilentlyContinue) } catch {}
                Remove-Job $script:diskJob -Force -EA SilentlyContinue
                $script:diskJob = $null
                $script:btnDiskSpace.IsEnabled = $true
                $script:btnDiskSpace.Content   = "Analizar espacio"

                $script:icDiskFolders.Items.Clear()
                if(-not $folders -or $folders.Count -eq 0){
                    $emptyTxt = New-Object Windows.Controls.TextBlock
                    $emptyTxt.Text              = "No se encontraron carpetas con datos."
                    $emptyTxt.FontSize          = 12
                    $emptyTxt.Foreground        = New-Brush "#555555"
                    $emptyTxt.Margin            = New-Object Windows.Thickness(0,8,0,8)
                    $emptyTxt.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
                    $script:icDiskFolders.Items.Add($emptyTxt) | Out-Null
                    $script:lblDiskSpaceStatus.Text = "Sin resultados"
                    Flush-UI
                    return
                }

                $maxBytes = ($folders | Measure-Object SizeBytes -Maximum).Maximum
                if($maxBytes -le 0){ $maxBytes = 1 }

                $barColors = @("#EF4444","#F97316","#F59E0B","#EAB308","#84CC16",
                               "#22C55E","#10B981","#14B8A6","#06B6D4","#38BDF8")
                $idx = 0
                foreach($f in $folders){
                    $pct     = [math]::Max(2, [math]::Round($f.SizeBytes / $maxBytes * 100, 0))
                    $barCol  = $barColors[[math]::Min($idx, $barColors.Count - 1)]
                    $sizeStr = if($f.SizeGB -ge 1){ "$($f.SizeGB) GB" } else { "$($f.SizeMB) MB" }

                    $rowBdr = New-Object Windows.Controls.Border
                    $rowBdr.Padding      = New-Object Windows.Thickness(10,7,10,7)
                    $rowBdr.Margin       = New-Object Windows.Thickness(0,1,0,0)
                    $rowBdr.Background   = New-Brush "#161616"
                    $rowBdr.CornerRadius = New-Object Windows.CornerRadius(4)

                    $rowSp = New-Object Windows.Controls.StackPanel

                    # Fila: nombre + tamano
                    $topGrid = New-Object Windows.Controls.Grid
                    $tcN = New-Object Windows.Controls.ColumnDefinition
                    $tcN.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
                    $tcS = New-Object Windows.Controls.ColumnDefinition
                    $tcS.Width = [Windows.GridLength]::new(80)
                    $topGrid.ColumnDefinitions.Add($tcN) | Out-Null
                    $topGrid.ColumnDefinitions.Add($tcS) | Out-Null

                    $lblName = New-Object Windows.Controls.TextBlock
                    $lblName.Text             = $f.Name
                    $lblName.FontSize         = 12
                    $lblName.Foreground       = New-Brush "#CCCCCC"
                    $lblName.VerticalAlignment = [Windows.VerticalAlignment]::Center
                    [Windows.Controls.Grid]::SetColumn($lblName, 0)

                    $lblSz = New-Object Windows.Controls.TextBlock
                    $lblSz.Text                = $sizeStr
                    $lblSz.FontSize            = 11
                    $lblSz.FontWeight          = [Windows.FontWeights]::SemiBold
                    $lblSz.Foreground          = New-Brush $barCol
                    $lblSz.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
                    $lblSz.VerticalAlignment   = [Windows.VerticalAlignment]::Center
                    [Windows.Controls.Grid]::SetColumn($lblSz, 1)

                    $topGrid.Children.Add($lblName) | Out-Null
                    $topGrid.Children.Add($lblSz)   | Out-Null

                    # Barra proporcional usando Grid con columnas Star
                    $barGrid = New-Object Windows.Controls.Grid
                    $barGrid.Margin = New-Object Windows.Thickness(0,5,0,0)
                    $bcFill = New-Object Windows.Controls.ColumnDefinition
                    $bcFill.Width = [Windows.GridLength]::new($pct, [Windows.GridUnitType]::Star)
                    $bcRest = New-Object Windows.Controls.ColumnDefinition
                    $bcRest.Width = [Windows.GridLength]::new(100 - $pct, [Windows.GridUnitType]::Star)
                    $barGrid.ColumnDefinitions.Add($bcFill) | Out-Null
                    $barGrid.ColumnDefinitions.Add($bcRest) | Out-Null

                    $barFill = New-Object Windows.Controls.Border
                    $barFill.Background   = New-Brush $barCol
                    $barFill.CornerRadius = New-Object Windows.CornerRadius(2)
                    $barFill.Height       = 4
                    [Windows.Controls.Grid]::SetColumn($barFill, 0)
                    $barGrid.Children.Add($barFill) | Out-Null

                    $rowSp.Children.Add($topGrid) | Out-Null
                    $rowSp.Children.Add($barGrid) | Out-Null
                    $rowBdr.Child = $rowSp
                    $script:icDiskFolders.Items.Add($rowBdr) | Out-Null
                    $idx++
                }

                $totalGB   = [math]::Round(($folders | Measure-Object SizeBytes -Sum).Sum / 1GB, 1)
                $script:lblDiskSpaceStatus.Text = "$($folders.Count) carpetas  |  $totalGB GB escaneados"
                Flush-UI
            })
            $script:diskTimer.Start()
            Flush-UI
        })
    } catch { Write-Log "Error al construir card de espacio en disco: $_" "err" }

    # F2.16 — Agregar campo "Nombre del Tecnico" en tab Ajustes (visible solo en tier Tecnico)
    try {
        $script:techNameRow = $null
        $ajustesItem  = $mainTabs.Items[7]
        $ajustesScrl  = $ajustesItem.Content
        $ajustesSp    = $ajustesScrl.Content

        $techBdr = New-Object Windows.Controls.Border
        $techBdr.Background      = $window.FindResource("BrushCard")
        $techBdr.BorderBrush     = New-Brush "#1A3A3A"
        $techBdr.BorderThickness = New-Object Windows.Thickness(1)
        $techBdr.CornerRadius    = New-Object Windows.CornerRadius(8)
        $techBdr.Padding         = New-Object Windows.Thickness(18,14,18,14)
        $techBdr.Margin          = New-Object Windows.Thickness(0,0,0,14)
        $techBdr.Visibility      = if($script:IS_TECH){ "Visible" } else { "Collapsed" }

        $techInner = New-Object Windows.Controls.StackPanel

        $techHdr = New-Object Windows.Controls.TextBlock
        $techHdr.Text       = "PERFIL DE TECNICO"
        $techHdr.FontSize   = 11
        $techHdr.FontWeight = [Windows.FontWeights]::SemiBold
        $techHdr.Foreground = New-Brush "#00C8FF"
        $techHdr.Margin     = New-Object Windows.Thickness(0,0,0,10)

        $techDesc = New-Object Windows.Controls.TextBlock
        $techDesc.Text        = "Nombre o empresa que aparece en los reportes HTML exportados."
        $techDesc.FontSize    = 12
        $techDesc.Foreground  = $window.FindResource("BrushFgMuted")
        $techDesc.TextWrapping = [Windows.TextWrapping]::Wrap
        $techDesc.Margin      = New-Object Windows.Thickness(0,0,0,10)

        $techRow = New-Object Windows.Controls.Grid
        $tcA = New-Object Windows.Controls.ColumnDefinition; $tcA.Width = [Windows.GridLength]::new(160)
        $tcB = New-Object Windows.Controls.ColumnDefinition; $tcB.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $tcC = New-Object Windows.Controls.ColumnDefinition; $tcC.Width = [Windows.GridLength]::new(80)
        $techRow.ColumnDefinitions.Add($tcA) | Out-Null
        $techRow.ColumnDefinitions.Add($tcB) | Out-Null
        $techRow.ColumnDefinitions.Add($tcC) | Out-Null

        $techLbl = New-Object Windows.Controls.TextBlock
        $techLbl.Text             = "Nombre del Tecnico:"
        $techLbl.FontSize         = 12
        $techLbl.Foreground       = $window.FindResource("BrushFgMuted")
        $techLbl.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($techLbl, 0)

        $script:txtTechName = New-Object Windows.Controls.TextBox
        $script:txtTechName.Text             = $script:settings.TechnicianName
        $script:txtTechName.FontSize         = 12
        $script:txtTechName.Background       = New-Brush "#1E1E1E"
        $script:txtTechName.Foreground       = New-Brush "#EEEEEE"
        $script:txtTechName.BorderBrush      = New-Brush "#333333"
        $script:txtTechName.BorderThickness  = New-Object Windows.Thickness(1)
        $script:txtTechName.Padding          = New-Object Windows.Thickness(8,5,8,5)
        $script:txtTechName.Margin           = New-Object Windows.Thickness(8,0,8,0)
        $script:txtTechName.VerticalContentAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($script:txtTechName, 1)

        $techSaveBtn = New-Object Windows.Controls.Button
        $techSaveBtn.Content = "Guardar"
        $techSaveBtn.Padding = New-Object Windows.Thickness(10,5,10,5)
        $techSaveBtn.Style   = $window.FindResource("BtnSec")
        [Windows.Controls.Grid]::SetColumn($techSaveBtn, 2)

        $techSaveBtn.Add_Click({
            $script:settings.TechnicianName = $script:txtTechName.Text.Trim()
            Save-Settings
            Write-Log "Nombre de tecnico guardado: $($script:settings.TechnicianName)" "ok"
        })

        $techRow.Children.Add($techLbl)            | Out-Null
        $techRow.Children.Add($script:txtTechName) | Out-Null
        $techRow.Children.Add($techSaveBtn)        | Out-Null

        $techInner.Children.Add($techHdr)  | Out-Null
        $techInner.Children.Add($techDesc) | Out-Null
        $techInner.Children.Add($techRow)  | Out-Null
        $techBdr.Child = $techInner

        # Insertar al principio del StackPanel de Ajustes (antes del primer hijo)
        $ajustesSp.Children.Insert(0, $techBdr) | Out-Null
        $script:techNameRow = $techBdr
    } catch { Write-Log "Error al construir campo tecnico en Ajustes: $_" "err" }

    # F2.20 — Card "Game Focus Mode" en tab Ajustes con toggle de afinidad CPU
    try {
        $ajustesItem2 = $mainTabs.Items[7]
        $ajustesSp2   = $ajustesItem2.Content.Content

        $gameBdr = New-Object Windows.Controls.Border
        $gameBdr.Background      = $window.FindResource("BrushCard")
        $gameBdr.BorderBrush     = New-Brush "#1A2A1A"
        $gameBdr.BorderThickness = New-Object Windows.Thickness(1)
        $gameBdr.CornerRadius    = New-Object Windows.CornerRadius(8)
        $gameBdr.Padding         = New-Object Windows.Thickness(18,14,18,14)
        $gameBdr.Margin          = New-Object Windows.Thickness(0,0,0,14)

        $gameInner = New-Object Windows.Controls.StackPanel

        $gameHdr = New-Object Windows.Controls.TextBlock
        $gameHdr.Text       = "GAME FOCUS MODE"
        $gameHdr.FontSize   = 11
        $gameHdr.FontWeight = [Windows.FontWeights]::SemiBold
        $gameHdr.Foreground = New-Brush "#22C55E"
        $gameHdr.Margin     = New-Object Windows.Thickness(0,0,0,10)

        # Fila checkbox + descripcion
        $gameChkRow = New-Object Windows.Controls.Grid
        $gcA = New-Object Windows.Controls.ColumnDefinition; $gcA.Width = [Windows.GridLength]::new([Windows.GridLength]::Auto)
        $gcB = New-Object Windows.Controls.ColumnDefinition; $gcB.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $gameChkRow.ColumnDefinitions.Add($gcA) | Out-Null
        $gameChkRow.ColumnDefinitions.Add($gcB) | Out-Null
        $gameChkRow.Margin = New-Object Windows.Thickness(0,0,0,8)

        $script:chkGameAffinity = New-Object Windows.Controls.CheckBox
        $script:chkGameAffinity.IsChecked        = $script:settings.GameAffinityEnabled
        $script:chkGameAffinity.VerticalAlignment = [Windows.VerticalAlignment]::Top
        $script:chkGameAffinity.Margin           = New-Object Windows.Thickness(0,2,10,0)
        [Windows.Controls.Grid]::SetColumn($script:chkGameAffinity, 0)

        $gameChkLabel = New-Object Windows.Controls.StackPanel
        [Windows.Controls.Grid]::SetColumn($gameChkLabel, 1)

        $gameChkTitle = New-Object Windows.Controls.TextBlock
        $gameChkTitle.Text       = "Limitar afinidad CPU a nucleos fisicos en Game Focus Mode"
        $gameChkTitle.FontSize   = 12
        $gameChkTitle.FontWeight = [Windows.FontWeights]::SemiBold
        $gameChkTitle.Foreground = $window.FindResource("BrushFg1")
        $gameChkTitle.TextWrapping = [Windows.TextWrapping]::Wrap
        $gameChkTitle.Margin     = New-Object Windows.Thickness(0,0,0,3)

        $gameChkDesc = New-Object Windows.Controls.TextBlock
        $gameChkDesc.Text        = "Al detectar un juego en pantalla completa, restringe su afinidad de CPU a los nucleos fisicos (sin hilos logicos SMT/HT). Reduce interferencia entre hilos fisicos y logicos en cargas de juego intensas. Solo tiene efecto en CPUs con Hyper-Threading o SMT activado. La afinidad se restaura al salir del juego."
        $gameChkDesc.FontSize    = 11
        $gameChkDesc.Foreground  = $window.FindResource("BrushFgMuted")
        $gameChkDesc.TextWrapping = [Windows.TextWrapping]::Wrap

        $gameChkLabel.Children.Add($gameChkTitle) | Out-Null
        $gameChkLabel.Children.Add($gameChkDesc)  | Out-Null
        $gameChkRow.Children.Add($script:chkGameAffinity) | Out-Null
        $gameChkRow.Children.Add($gameChkLabel)           | Out-Null

        # Info de cores detectados
        $script:lblGameAffinityInfo = New-Object Windows.Controls.TextBlock
        $script:lblGameAffinityInfo.FontSize   = 11
        $script:lblGameAffinityInfo.Foreground = New-Brush "#888888"
        $script:lblGameAffinityInfo.Margin     = New-Object Windows.Thickness(0,4,0,0)
        try {
            $cpu2 = Get-CimInstance Win32_Processor | Select-Object -First 1
            $ph2  = [int]$cpu2.NumberOfCores
            $lg2  = [int]$cpu2.NumberOfLogicalProcessors
            if($lg2 -gt $ph2){
                $mask2 = [long]([math]::Pow(2, $ph2) - 1)
                $script:lblGameAffinityInfo.Text = "Detectado: $ph2 nucleos fisicos / $lg2 hilos logicos. Mascara a aplicar: 0x$([Convert]::ToString($mask2,16).ToUpper())"
            } else {
                $script:lblGameAffinityInfo.Text = "Detectado: $ph2 nucleos (sin SMT/HT). Esta opcion no tendra efecto en este equipo."
                $script:chkGameAffinity.IsEnabled = $false
            }
        } catch { $script:lblGameAffinityInfo.Text = "No se pudo detectar la configuracion de CPU." }

        $script:chkGameAffinity.Add_Click({
            $script:settings.GameAffinityEnabled = [bool]$script:chkGameAffinity.IsChecked
            Save-Settings
            $state2 = if($script:settings.GameAffinityEnabled){ "activada" } else { "desactivada" }
            Write-Log "Afinidad CPU Game Focus Mode $state2" "ok"
        })

        $gameInner.Children.Add($gameHdr)      | Out-Null
        $gameInner.Children.Add($gameChkRow)   | Out-Null
        $gameInner.Children.Add($script:lblGameAffinityInfo) | Out-Null
        $gameBdr.Child = $gameInner

        # Insertar despues del card de tecnico (indice 1, ya que el tech es indice 0)
        $insertIdx = if($script:IS_TECH){ 1 } else { 0 }
        $ajustesSp2.Children.Insert($insertIdx, $gameBdr) | Out-Null
    } catch { Write-Log "Error al construir card Game Focus Mode en Ajustes: $_" "err" }
})

# Resize debounce: redibujar score history al cambiar el ancho de la ventana
$script:_resizeTimer = New-Object Windows.Threading.DispatcherTimer
$script:_resizeTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:_resizeTimer.Add_Tick({
    $this.Stop()
    try { if ($mainTabs.SelectedItem -and $mainTabs.SelectedItem.Header -eq "Historial") { Render-ScoreHistory } } catch {}
})
$window.Add_SizeChanged({
    $script:_resizeTimer.Stop()
    $script:_resizeTimer.Start()
})

# (SelectionChanged fusionado en F2.4 — ver handler unico mas arriba)

# ============================================================
# MODULO 4A - MOTOR DE DETECCION DE BLOATWARE
# ============================================================
#
# Cada entrada de la lista define:
#   Name        - nombre visible para el usuario
#   PackageId   - AppxPackage PackageFamilyName o fragmento (para UWP)
#   WingetId    - ID de winget para apps Win32 (puede ser $null)
#   Category    - Juegos / Comunicacion / Telemetria / OEM / Utilidades
#   Method      - "appx" | "winget" | "appx+winget"
#   Risk        - "safe" | "caution"
#                 safe    = se puede quitar sin romper nada del sistema
#                 caution = revisar antes (puede afectar funciones de Windows)
#   EstimateMB  - espacio estimado liberado en MB (referencia, no exacto)
# ---------------------------------------------------------------

$script:bloatwareDb = @(

    # ---- JUEGOS PREINSTALADOS ----
    [PSCustomObject]@{ Name="Candy Crush Saga";          PackageId="king.com.CandyCrushSaga";              WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=120 }
    [PSCustomObject]@{ Name="Candy Crush Friends";       PackageId="king.com.CandyCrushFriendsSaga";       WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=110 }
    [PSCustomObject]@{ Name="Candy Crush Soda Saga";     PackageId="king.com.CandyCrushSodaSaga";          WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=100 }
    [PSCustomObject]@{ Name="Farm Heroes Saga";          PackageId="king.com.FarmHeroesSaga";              WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=90  }
    [PSCustomObject]@{ Name="Bubble Witch 3 Saga";       PackageId="king.com.BubbleWitch3Saga";            WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=85  }
    [PSCustomObject]@{ Name="Microsoft Solitaire";       PackageId="Microsoft.MicrosoftSolitaireCollection"; WingetId=$null;                        Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=95  }
    [PSCustomObject]@{ Name="Xbox Game Bar";             PackageId="Microsoft.XboxGamingOverlay";          WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="caution"; EstimateMB=50  }
    [PSCustomObject]@{ Name="Xbox App";                  PackageId="Microsoft.GamingApp";                  WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="caution"; EstimateMB=150 }
    [PSCustomObject]@{ Name="Xbox Identity Provider";    PackageId="Microsoft.XboxIdentityProvider";       WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="caution"; EstimateMB=20  }
    [PSCustomObject]@{ Name="Xbox TCUI";                 PackageId="Microsoft.Xbox.TCUI";                  WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="caution"; EstimateMB=15  }
    [PSCustomObject]@{ Name="Xbox Speech To Text";       PackageId="Microsoft.XboxSpeechToTextOverlay";    WingetId=$null;                          Category="Juegos";        Method="appx";         Risk="safe";    EstimateMB=10  }

    # ---- COMUNICACION / REDES SOCIALES ----
    [PSCustomObject]@{ Name="Skype";                     PackageId="Microsoft.SkypeApp";                   WingetId="Microsoft.Skype";              Category="Comunicacion";  Method="appx+winget";  Risk="safe";    EstimateMB=180 }
    [PSCustomObject]@{ Name="Microsoft Teams (personal)";PackageId="MicrosoftTeams";                       WingetId="Microsoft.Teams";              Category="Comunicacion";  Method="appx+winget";  Risk="caution"; EstimateMB=350 }
    [PSCustomObject]@{ Name="WhatsApp";                  PackageId="5319275A.WhatsAppDesktop";             WingetId=$null;                          Category="Comunicacion";  Method="appx";         Risk="safe";    EstimateMB=200 }
    [PSCustomObject]@{ Name="Facebook";                  PackageId="Facebook.Facebook";                    WingetId=$null;                          Category="Comunicacion";  Method="appx";         Risk="safe";    EstimateMB=90  }
    [PSCustomObject]@{ Name="Instagram";                 PackageId="Facebook.Instagram";                   WingetId=$null;                          Category="Comunicacion";  Method="appx";         Risk="safe";    EstimateMB=80  }
    [PSCustomObject]@{ Name="Twitter / X";               PackageId="Twitter.Twitter";                      WingetId=$null;                          Category="Comunicacion";  Method="appx";         Risk="safe";    EstimateMB=70  }
    [PSCustomObject]@{ Name="TikTok";                    PackageId="BytedancePte.Ltd.TikTok";              WingetId=$null;                          Category="Comunicacion";  Method="appx";         Risk="safe";    EstimateMB=150 }
    [PSCustomObject]@{ Name="Spotify (preinstalado)";    PackageId="SpotifyAB.SpotifyMusic";               WingetId=$null;                          Category="Comunicacion";  Method="appx";         Risk="safe";    EstimateMB=130 }

    # ---- TELEMETRIA / DIAGNOSTICO ----
    [PSCustomObject]@{ Name="Bing Search (barra tareas)"; PackageId="Microsoft.BingSearch";               WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=15  }
    [PSCustomObject]@{ Name="Bing News";                 PackageId="Microsoft.BingNews";                   WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=40  }
    [PSCustomObject]@{ Name="Bing Weather";              PackageId="Microsoft.BingWeather";                WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=35  }
    [PSCustomObject]@{ Name="Bing Finance";              PackageId="Microsoft.BingFinance";                WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=30  }
    [PSCustomObject]@{ Name="Bing Sports";               PackageId="Microsoft.BingSports";                 WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=30  }
    [PSCustomObject]@{ Name="Microsoft Advertising SDK"; PackageId="Microsoft.Advertising.Xaml";          WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=20  }
    [PSCustomObject]@{ Name="Feedback Hub";              PackageId="Microsoft.WindowsFeedbackHub";         WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=25  }
    [PSCustomObject]@{ Name="Get Help";                  PackageId="Microsoft.GetHelp";                    WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=20  }
    [PSCustomObject]@{ Name="Microsoft Tips";            PackageId="Microsoft.Getstarted";                 WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=15  }
    [PSCustomObject]@{ Name="Mixed Reality Portal";      PackageId="Microsoft.MixedReality.Portal";        WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=200 }
    [PSCustomObject]@{ Name="3D Viewer";                 PackageId="Microsoft.Microsoft3DViewer";          WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=45  }
    [PSCustomObject]@{ Name="Paint 3D";                  PackageId="Microsoft.MSPaint";                    WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=55  }
    [PSCustomObject]@{ Name="Microsoft To Do";           PackageId="Microsoft.Todos";                      WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=60  }
    [PSCustomObject]@{ Name="Clipchamp";                 PackageId="Clipchamp.Clipchamp";                  WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=80  }
    [PSCustomObject]@{ Name="Power Automate";            PackageId="Microsoft.PowerAutomateDesktop";       WingetId=$null;                          Category="Telemetria";    Method="appx";         Risk="safe";    EstimateMB=300 }

    # ---- OEM / FABRICANTE ----
    [PSCustomObject]@{ Name="HP Support Assistant";      PackageId=$null;                                  WingetId="HP.HPSupportAssistant";        Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=400 }
    [PSCustomObject]@{ Name="HP Sure Connect";           PackageId=$null;                                  WingetId="HP.HPSureConnect";             Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=60  }
    [PSCustomObject]@{ Name="Dell SupportAssist";        PackageId=$null;                                  WingetId="Dell.DellSupportAssistforPCs"; Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=500 }
    [PSCustomObject]@{ Name="Dell Digital Delivery";     PackageId=$null;                                  WingetId="Dell.DellDigitalDelivery";     Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=80  }
    [PSCustomObject]@{ Name="Lenovo Vantage";            PackageId=$null;                                  WingetId="Lenovo.LenovoVantage";         Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=250 }
    [PSCustomObject]@{ Name="Lenovo Smart Noise Cancel"; PackageId="E046963F.LenovoCompanion";             WingetId=$null;                          Category="OEM";           Method="appx";         Risk="safe";    EstimateMB=120 }
    [PSCustomObject]@{ Name="ASUS Armoury Crate";        PackageId=$null;                                  WingetId="ASUS.ArmouryCrate";            Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=350 }
    [PSCustomObject]@{ Name="Acer Care Center";          PackageId=$null;                                  WingetId="Acer.AcerCareCenter";          Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=200 }
    [PSCustomObject]@{ Name="McAfee (trial)";            PackageId=$null;                                  WingetId="McAfee.McAfeeSecurity";        Category="OEM";           Method="winget";       Risk="safe";    EstimateMB=600 }
    [PSCustomObject]@{ Name="Norton (trial)";            PackageId=$null;                                  WingetId="NortonLifeLock.NortonSecurity"; Category="OEM";          Method="winget";       Risk="safe";    EstimateMB=550 }

    # ---- UTILIDADES INNECESARIAS ----
    [PSCustomObject]@{ Name="Microsoft Sway";            PackageId="Microsoft.Office.Sway";                WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=30  }
    [PSCustomObject]@{ Name="OneNote (preinstalado)";    PackageId="Microsoft.Office.OneNote";             WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=120 }
    [PSCustomObject]@{ Name="People";                    PackageId="Microsoft.People";                     WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=25  }
    [PSCustomObject]@{ Name="Maps";                      PackageId="Microsoft.WindowsMaps";                WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=80  }
    [PSCustomObject]@{ Name="Groove Music";              PackageId="Microsoft.ZuneMusic";                  WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=75  }
    [PSCustomObject]@{ Name="Movies & TV";               PackageId="Microsoft.ZuneVideo";                  WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=65  }
    [PSCustomObject]@{ Name="Money";                     PackageId="Microsoft.BingFinance";                WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=30  }
    [PSCustomObject]@{ Name="Microsoft Print to PDF";    PackageId="Microsoft.Print.to.PDF";               WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="caution"; EstimateMB=5   }
    [PSCustomObject]@{ Name="Your Phone / Phone Link";   PackageId="Microsoft.YourPhone";                  WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=90  }
    [PSCustomObject]@{ Name="Microsoft Family Safety";   PackageId="MicrosoftCorporationII.MicrosoftFamily"; WingetId=$null;                        Category="Utilidades";    Method="appx";         Risk="safe";    EstimateMB=40  }
    [PSCustomObject]@{ Name="Quick Assist";              PackageId="MicrosoftCorporationII.QuickAssist";   WingetId=$null;                          Category="Utilidades";    Method="appx";         Risk="caution"; EstimateMB=15  }
)

# ------------------------------------------------------------
# Get-InstalledAppxMap
# Carga TODOS los AppxPackages instalados para el usuario
# actual y para todos los usuarios, indexados por fragmento
# de PackageFamilyName. Llamar una sola vez por sesion.
# ------------------------------------------------------------
function Get-InstalledAppxMap {
    $map = @{}
    try {
        Get-AppxPackage -EA SilentlyContinue | ForEach-Object {
            $key = $_.PackageFamilyName.ToLower()
            if(-not $map.ContainsKey($key)){ $map[$key] = $_ }
        }
    } catch {}
    try {
        Get-AppxPackage -AllUsers -EA SilentlyContinue | ForEach-Object {
            $key = $_.PackageFamilyName.ToLower()
            if(-not $map.ContainsKey($key)){ $map[$key] = $_ }
        }
    } catch {}
    return $map
}

# ------------------------------------------------------------
# Test-WingetAvailable
# Comprueba si winget esta disponible en el sistema.
# ------------------------------------------------------------
function Test-WingetAvailable {
    try {
        $r = winget --version 2>$null
        return ($LASTEXITCODE -eq 0 -or $r -ne $null)
    } catch { return $false }
}

# ------------------------------------------------------------
# Get-WingetInstalledMap
# Carga la lista de paquetes instalados via winget, indexada
# por Id normalizado. Solo se llama si winget esta disponible.
# ------------------------------------------------------------
function Get-WingetInstalledMap {
    $map = @{}
    try {
        if(-not (Test-WingetAvailable)){ return $map }

        # Correr winget en Job separado con timeout de 8 segundos
        $job = Start-Job -ScriptBlock {
            $raw = winget list --accept-source-agreements 2>$null
            return $raw
        }

        # Esperar maximo 8 segundos
        $completed = Wait-Job $job -Timeout 8
        if(-not $completed){
            Stop-Job  $job -EA SilentlyContinue
            Remove-Job $job -EA SilentlyContinue
            Write-Log "winget: timeout de 8s, continuando sin datos de winget" "info"
            return $map
        }

        $raw = Receive-Job $job -EA SilentlyContinue
        Remove-Job $job -EA SilentlyContinue

        if(-not $raw){ return $map }

        foreach($line in $raw){
            if($line -match '\s{2,}([A-Za-z0-9][\w\.\-]+)\s{2,}'){
                $id = $Matches[1].ToLower()
                $map[$id] = $line.Trim()
            }
        }
    } catch {}
    return $map
}

# ------------------------------------------------------------
# Get-BloatwareList
# Funcion principal del modulo 4A.
# Cruza $script:bloatwareDb con los paquetes instalados y
# devuelve solo los que realmente estan presentes en el equipo.
#
# Cada objeto del resultado:
#   Name        - nombre legible
#   Category    - categoria del bloatware
#   Method      - metodo de desinstalacion
#   Risk        - safe | caution
#   EstimateMB  - espacio estimado
#   IsPresent   - $true (siempre true en el resultado)
#   PackageFN   - PackageFamilyName real encontrado (appx)
#   WingetId    - ID de winget si aplica
#   PackageObj  - objeto AppxPackage completo (puede ser $null para winget)
# ------------------------------------------------------------
function Get-BloatwareList {
    $result = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Cargar mapas de instalacion
    $appxMap   = Get-InstalledAppxMap
    $wingetMap = @{}
    $wingetOk  = Test-WingetAvailable
    if($wingetOk){ $wingetMap = Get-WingetInstalledMap }

    foreach($item in $script:bloatwareDb){

        $found      = $false
        $packageFN  = $null
        $packageObj = $null

        # --- Busqueda AppX ---
        if($item.PackageId -and ($item.Method -eq "appx" -or $item.Method -eq "appx+winget")){
            $needle = $item.PackageId.ToLower()
            # Busqueda exacta primero, luego por fragmento
            foreach($key in $appxMap.Keys){
                if($key -like "*$needle*" -or $needle -like "*$key*"){
                    $found      = $true
                    $packageFN  = $appxMap[$key].PackageFamilyName
                    $packageObj = $appxMap[$key]
                    break
                }
            }
        }

        # --- Busqueda Winget ---
        if(-not $found -and $item.WingetId -and
           ($item.Method -eq "winget" -or $item.Method -eq "appx+winget")){
            if($wingetOk){
                $needle = $item.WingetId.ToLower()
                foreach($key in $wingetMap.Keys){
                    if($key -like "*$needle*" -or $needle -like "*$key*"){
                        $found = $true
                        break
                    }
                }
            }
        }

        if($found){
            $result.Add([PSCustomObject]@{
                Name       = $item.Name
                Category   = $item.Category
                Method     = $item.Method
                Risk       = $item.Risk
                EstimateMB = $item.EstimateMB
                IsPresent  = $true
                PackageFN  = $packageFN
                WingetId   = $item.WingetId
                PackageObj = $packageObj
            })
        }
    }

    # Ordenar por categoria y luego nombre
    return ($result | Sort-Object Category, Name)
}

# ------------------------------------------------------------
# Get-BloatwareSummary
# Devuelve un resumen rapido del bloatware encontrado.
# Util para mostrar en la UI antes de la lista completa.
# ------------------------------------------------------------
function Get-BloatwareSummary {
    param([System.Collections.Generic.List[PSCustomObject]]$list = $null)
    if($null -eq $list){ $list = Get-BloatwareList }

    $totalMB   = ($list | Measure-Object EstimateMB -Sum).Sum
    $byCategory = $list | Group-Object Category |
        ForEach-Object { "$($_.Name): $($_.Count)" }

    return [PSCustomObject]@{
        Count      = $list.Count
        TotalMB    = $totalMB
        ByCategory = $byCategory
        SafeCount  = ($list | Where-Object { $_.Risk -eq "safe" }).Count
        CautionCount=($list | Where-Object { $_.Risk -eq "caution"}).Count
    }
}

# ============================================================
# MODULO 5A - MOTOR DE PROCESOS PESADOS
# ============================================================

# ------------------------------------------------------------
# Lista de exclusion de procesos del sistema.
# Estos procesos NUNCA se muestran como terminables.
# Incluye kernel, drivers, seguridad, .NET runtime y shell.
# ------------------------------------------------------------
$script:systemProcessNames = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
@(
    # Kernel y subsistemas Windows
    "System","Registry","smss","csrss","wininit","winlogon","lsass",
    "lsaiso","services","svchost","dwm","fontdrvhost","LogonUI",
    "ntoskrnl","hal",
    # Session / seguridad
    "SecurityHealthService","SecurityHealthSystray","MsMpEng",
    "NisSrv","WinDefend","SgrmBroker","wscsvc",
    # Shell y explorer
    "explorer","ShellExperienceHost","StartMenuExperienceHost",
    "SearchIndexer","SearchHost","SearchProtocolHost","SearchFilterHost",
    "RuntimeBroker","ctfmon","TextInputHost",
    # Runtime y frameworks
    "conhost","condrv","dllhost","taskhost","taskhostw",
    "sihost","ApplicationFrameHost","WWAHost","WUDFHost",
    # Hardware / drivers
    "audiodg","WmiPrvSE","WmiApSrv","spoolsv","msdtc",
    "LsaIso","Idle","MemCompression","vmmem",
    # Update y store
    "TiWorker","TrustedInstaller","WaaSMedicAgent","UsoClient",
    "WaasMedic","wuauclt","msiexec","MoUsoCoreWorker",
    # Optimizador mismo (nunca terminar el propio proceso)
    "powershell","pwsh","cmd","OptimizarPC"
) | ForEach-Object { $script:systemProcessNames.Add($_) | Out-Null }

# ------------------------------------------------------------
# Test-SystemProcess
# Devuelve $true si el proceso es del sistema y no debe
# ser terminado por el usuario.
# Criterios: nombre en lista de exclusion, o path en
# System32/SysWOW64/Windows, o sin path (kernel/driver).
# ------------------------------------------------------------
function Test-SystemProcess {
    param([System.Diagnostics.Process]$proc)
    try {
        # Por nombre
        if($script:systemProcessNames.Contains($proc.ProcessName)){ return $true }

        # Por PID del sistema
        if($proc.Id -le 4){ return $true }

        # Por ruta del ejecutable
        $path = $null
        try { $path = $proc.MainModule.FileName } catch {}
        if(-not $path){
            # Intentar via CIM (no lanza si es proceso protegido)
            try {
                $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" `
                           -EA SilentlyContinue
                $path = $cim.ExecutablePath
            } catch {}
        }
        if($path){
            $pathLower = $path.ToLower()
            if($pathLower -like "*\windows\system32\*"  -or
               $pathLower -like "*\windows\syswow64\*"  -or
               $pathLower -like "*\windows\systemapps\*"){
                return $true
            }
        } else {
            # Sin path = proceso del kernel o driver
            return $true
        }
        return $false
    } catch {
        # Si no se puede leer, asumir que es del sistema (conservador)
        return $true
    }
}

# ------------------------------------------------------------
# Get-ProcessDetails
# Devuelve info extendida de un proceso:
# Path, Description, Company via FileVersionInfo.
# Usa CIM como fallback si MainModule no es accesible.
# ------------------------------------------------------------
function Get-ProcessDetails {
    param([System.Diagnostics.Process]$proc)

    $path    = ""
    $desc    = ""
    $company = ""

    try { $path = $proc.MainModule.FileName } catch {}

    if(-not $path){
        try {
            $cim  = Get-CimInstance Win32_Process `
                        -Filter "ProcessId=$($proc.Id)" -EA SilentlyContinue
            $path = $cim.ExecutablePath
        } catch {}
    }

    if($path -and (Test-Path $path -EA SilentlyContinue)){
        try {
            $fvi     = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $desc    = if($fvi.FileDescription){ $fvi.FileDescription } else { "" }
            $company = if($fvi.CompanyName)    { $fvi.CompanyName     } else { "" }
        } catch {}
    }

    return [PSCustomObject]@{
        Path    = $path
        Desc    = $desc
        Company = $company
    }
}

# ------------------------------------------------------------
# Get-HeavyProcesses
# Funcion principal del modulo 5A.
# Devuelve los procesos mas pesados del sistema, combinando
# top por CPU y top por RAM, sin duplicados.
#
# CPU%: delta entre la snapshot actual y la anterior cacheada en
# $script:_procSample1. Primera llamada: CPU=0 (sin baseline).
# Llamadas siguientes: CPU basado en el intervalo real del timer.
# Esto elimina el Start-Sleep que bloqueaba el hilo UI (F2.8).
# ------------------------------------------------------------
function Get-HeavyProcesses {
    param(
        [int]$TopN           = 12,
        [bool]$IncludeSystem = $false
    )

    # --- Snapshot actual: una sola llamada a Get-Process ---
    $rawProcs = @()
    $sample2  = @{}
    $time2    = [DateTime]::Now
    try {
        Get-Process -EA SilentlyContinue | ForEach-Object {
            try { $sample2[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds; $rawProcs += $_ } catch {}
        }
    } catch {}

    # --- Delta con snapshot anterior (primera llamada: elapsed=1ms, delta=0 => CPU%=0) ---
    $sample1  = if($script:_procSample1)   { $script:_procSample1    } else { $sample2 }
    $elapsed  = if($script:_procSampleTime1){ ($time2 - $script:_procSampleTime1).TotalMilliseconds } else { 1 }
    $cpuCount = [Environment]::ProcessorCount

    # Guardar snapshot para la proxima llamada
    $script:_procSample1    = $sample2
    $script:_procSampleTime1 = $time2

    # --- Calcular CPU% y armar lista ---
    $procs = @()
    foreach($proc in $rawProcs) {
        try {
            $cpu2   = $sample2[$proc.Id]
            $cpu1   = if($sample1.ContainsKey($proc.Id)){ $sample1[$proc.Id] } else { $cpu2 }
            $delta  = $cpu2 - $cpu1
            $cpuPct = [math]::Min(100, [math]::Round($delta / [math]::Max($elapsed,1) / $cpuCount * 100, 1))
            $cpuPct = [math]::Max(0, $cpuPct)
            $ramMB  = [math]::Round($proc.WorkingSet64 / 1MB, 1)
            $procs += [PSCustomObject]@{
                Name    = $proc.ProcessName
                PID     = $proc.Id
                CpuPct  = $cpuPct
                RamMB   = $ramMB
                ProcObj = $proc
            }
        } catch {}
    }

    # --- Filtrar y enriquecer ---
    $result = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen   = [System.Collections.Generic.HashSet[int]]::new()

    $byCPU = $procs | Sort-Object CpuPct -Descending | Select-Object -First $TopN
    $byRAM = $procs | Sort-Object RamMB  -Descending | Select-Object -First $TopN

    $combined = @($byCPU) + @($byRAM) | Sort-Object {
        $_.CpuPct * 1.5 + $_.RamMB / 100
    } -Descending

    foreach($p in $combined){
        if($seen.Contains($p.PID)){ continue }
        $seen.Add($p.PID) | Out-Null

        $isSys = Test-SystemProcess -proc $p.ProcObj
        if(-not $IncludeSystem -and $isSys){ continue }

        $det = Get-ProcessDetails -proc $p.ProcObj

        $result.Add([PSCustomObject]@{
            Name        = $p.Name
            PID         = $p.PID
            CpuPct      = $p.CpuPct
            RamMB       = $p.RamMB
            IsSystem    = $isSys
            Path        = $det.Path
            Description = $det.Desc
            Company     = $det.Company
            SortScore   = [math]::Round($p.CpuPct * 1.5 + $p.RamMB / 100, 1)
        })

        if($result.Count -ge $TopN * 2){ break }
    }

    return $result
}

# ------------------------------------------------------------
# Stop-ManagedProcess
# Termina un proceso por PID con validacion de seguridad.
# Rechaza procesos del sistema aunque se los pida.
# Devuelve [PSCustomObject]@{ Ok; Message }
# ------------------------------------------------------------
function Stop-ManagedProcess {
    param([int]$pid_)

    $result = [PSCustomObject]@{ Ok=$false; Message="" }

    try {
        $proc = Get-Process -Id $pid_ -EA SilentlyContinue
        if(-not $proc){
            $result.Message = "Proceso no encontrado (ya cerro)"
            return $result
        }

        # Doble validacion de seguridad — nunca terminar procesos del sistema
        if(Test-SystemProcess -proc $proc){
            $result.Message = "Operacion bloqueada: proceso del sistema"
            return $result
        }

        $name = $proc.ProcessName
        Stop-Process -Id $pid_ -Force -EA Stop
        $result.Ok      = $true
        $result.Message = "Proceso '$name' (PID $pid_) terminado"
    } catch {
        $result.Message = "Error: $($_.Exception.Message)"
    }
    return $result
}

# ============================================================
# MODULO 6A - MOTOR DE TEMPERATURA
# ============================================================

# ------------------------------------------------------------
# Get-CPUTemperature
# Lee MSAcpi_ThermalZoneTemperature via CIM (root/wmi).
# Maneja multiples zonas termicas, calcula promedio y maximo.
# Conversion: decimos de Kelvin -> Celsius = (raw - 2732) / 10
# Devuelve: TempC, TempMax, ZoneCount, Status
# ------------------------------------------------------------
function Get-CPUTemperature {
    $result = [PSCustomObject]@{
        Available = $false
        TempC     = -1
        TempMax   = -1
        ZoneCount = 0
        Status    = "unavailable"
    }
    try {
        $zones = Get-CimInstance -Namespace "root/wmi" `
                     -ClassName "MSAcpi_ThermalZoneTemperature" `
                     -EA SilentlyContinue
        if (-not $zones) { return $result }

        $temps = @()
        foreach ($z in $zones) {
            $raw = $z.CurrentTemperature
            if ($raw -gt 0) {
                $celsius = [math]::Round(($raw - 2732) / 10.0, 1)
                if ($celsius -ge 0 -and $celsius -le 120) {
                    $temps += $celsius
                }
            }
        }

        if ($temps.Count -eq 0) { return $result }

        $avg = [math]::Round(($temps | Measure-Object -Sum).Sum / $temps.Count, 1)
        $max = ($temps | Measure-Object -Maximum).Maximum

        $status = if ($max -ge 85) { "critical" }
                  elseif ($max -ge 70) { "warning" }
                  else { "normal" }

        $result.Available = $true
        $result.TempC     = $avg
        $result.TempMax   = $max
        $result.ZoneCount = $temps.Count
        $result.Status    = $status
    } catch {}
    return $result
}

# ------------------------------------------------------------
# Get-GPUTemperature
# Intenta leer temperatura GPU por multiples metodos:
#   1. Win32_PerfFormattedData_GPUPerformanceCounters (nativo WDDM)
#   2. LibreHardwareMonitor via WMI namespace (si esta instalado)
#   3. OpenHardwareMonitor via WMI namespace (alternativa a LHM)
# Devuelve: TempC, Source, Status
# ------------------------------------------------------------
function Get-GPUTemperature {
    $result = [PSCustomObject]@{
        Available = $false
        TempC     = -1
        Source    = "unavailable"
        Status    = "unavailable"
    }

    # Intento 2: LibreHardwareMonitor WMI namespace
    try {
        $lhmSensor = Get-CimInstance -Namespace "root/LibreHardwareMonitor" `
                         -ClassName "Sensor" -EA SilentlyContinue |
                     Where-Object { $_.SensorType -eq "Temperature" -and
                                    $_.Name -match "GPU" } |
                     Select-Object -First 1
        if ($lhmSensor) {
            $celsius = [math]::Round([double]$lhmSensor.Value, 1)
            $status  = if ($celsius -ge 85) { "critical" }
                       elseif ($celsius -ge 70) { "warning" }
                       else { "normal" }
            $result.Available = $true
            $result.TempC     = $celsius
            $result.Source    = "lhm"
            $result.Status    = $status
            return $result
        }
    } catch {}

    # Intento 3: OpenHardwareMonitor WMI namespace
    try {
        $ohmSensor = Get-CimInstance -Namespace "root/OpenHardwareMonitor" `
                         -ClassName "Sensor" -EA SilentlyContinue |
                     Where-Object { $_.SensorType -eq "Temperature" -and
                                    $_.Name -match "GPU" } |
                     Select-Object -First 1
        if ($ohmSensor) {
            $celsius = [math]::Round([double]$ohmSensor.Value, 1)
            $status  = if ($celsius -ge 85) { "critical" }
                       elseif ($celsius -ge 70) { "warning" }
                       else { "normal" }
            $result.Available = $true
            $result.TempC     = $celsius
            $result.Source    = "lhm"
            $result.Status    = $status
            return $result
        }
    } catch {}

    return $result
}

# ------------------------------------------------------------
# Get-ThermalStatus
# Funcion principal del modulo 6A.
# Llama Get-CPUTemperature y Get-GPUTemperature y devuelve
# un objeto unificado con estado global del sistema termico.
# Thresholds: normal <70 | warning 70-85 | critical >85
# Devuelve: CPU, GPU, OverallStatus
# ------------------------------------------------------------
function Get-ThermalStatus {
    $cpu = Get-CPUTemperature
    $gpu = Get-GPUTemperature

    $overallStatus = "normal"
    if ($cpu.Status -eq "critical" -or $gpu.Status -eq "critical") {
        $overallStatus = "critical"
    } elseif ($cpu.Status -eq "warning" -or $gpu.Status -eq "warning") {
        $overallStatus = "warning"
    } elseif ($cpu.Status -eq "unavailable" -and $gpu.Status -eq "unavailable") {
        $overallStatus = "unavailable"
    }

    return [PSCustomObject]@{
        CPU           = $cpu
        GPU           = $gpu
        OverallStatus = $overallStatus
    }
}

# ============================================================
# MODULO 7A - MOTOR DE TAREAS PROGRAMADAS
# ============================================================

$script:MAINTENANCE_TASK_NAME = "OptimizarPC_Maintenance"
$script:MAINTENANCE_LOG_PATH  = "$env:USERPROFILE\.OptimizarPC\maintenance_log.json"
$script:MAINTENANCE_SCRIPT    = "$env:USERPROFILE\.OptimizarPC\maintenance.ps1"

# ------------------------------------------------------------
# Invoke-MaintenanceCycle
# Ejecuta el ciclo de mantenimiento: temp, recycle, DNS flush,
# TRIM si SSD. Registra resultado en maintenance_log.json.
# Callable desde la UI (7B) y desde el script standalone.
# Devuelve el objeto log con las acciones ejecutadas.
# ------------------------------------------------------------
function Invoke-MaintenanceCycle {
    $log = [PSCustomObject]@{
        version   = $VERSION
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        actions   = @()
        freedMB   = 0
        errors    = @()
    }

    # Temp usuario
    try {
        $sz = (Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue |
               Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum
        if (-not $sz) { $sz = 0 }
        Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue |
            Remove-Item -Recurse -Force -EA SilentlyContinue
        $mb = [math]::Round($sz / 1MB, 1)
        $log.freedMB += $mb
        $log.actions += "Temp usuario limpiado ($mb MB)"
    } catch { $log.errors += "Temp: $($_.Exception.Message)" }

    # Papelera
    try {
        Clear-RecycleBin -Force -EA SilentlyContinue
        $log.actions += "Papelera vaciada"
    } catch { $log.errors += "Recycle: $($_.Exception.Message)" }

    # DNS flush
    try {
        ipconfig /flushdns 2>$null | Out-Null
        $log.actions += "DNS flush"
    } catch { $log.errors += "DNS: $($_.Exception.Message)" }

    # TRIM si SSD
    if ($HAS_SSD) {
        try {
            $drvLetter = $SYSDRIVE.TrimEnd(":")
            Optimize-Volume -DriveLetter $drvLetter -ReTrim -NormalPriority -EA SilentlyContinue
            $log.actions += "TRIM ejecutado en ${drvLetter}:"
        } catch { $log.errors += "TRIM: $($_.Exception.Message)" }
    }

    # Guardar log JSON (max 30 entradas)
    try {
        $logDir = Split-Path $script:MAINTENANCE_LOG_PATH
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $history = @()
        if (Test-Path $script:MAINTENANCE_LOG_PATH) {
            try {
                $raw = Get-Content $script:MAINTENANCE_LOG_PATH -Raw -EA SilentlyContinue |
                       ConvertFrom-Json
                if ($raw -is [System.Array]) { $history = $raw }
                else { $history = @($raw) }
            } catch {}
        }
        $history += $log
        if ($history.Count -gt 30) { $history = $history[-30..-1] }
        @($history) | ConvertTo-Json -Depth 4 | Out-File $script:MAINTENANCE_LOG_PATH -Encoding UTF8
    } catch {}

    # F1.1: Toast al completar mantenimiento
    try {
        $mbTotal = [math]::Round($log.freedMB, 1)
        Show-ToastNotification -Title "WinBoost" `
            -Message "Mantenimiento completado. $mbTotal MB liberados."
    } catch {}

    return $log
}

# ------------------------------------------------------------
# New-MaintenanceTask
# Escribe el script standalone de mantenimiento y registra la
# tarea en el Programador de tareas de Windows.
# Parametros:
#   Frequency - "Daily" | "Weekly"   (default Weekly)
#   Hour      - hora de ejecucion 0-23 (default 10)
# Devuelve $true si la tarea se registro correctamente.
# ------------------------------------------------------------
function New-MaintenanceTask {
    param(
        [ValidateSet("Daily","Weekly","AtStartup")]
        [string]$Frequency = "Weekly",
        [ValidateRange(0,23)]
        [int]$Hour = 10
    )

    # Escribir script standalone de mantenimiento (sin WPF)
    try {
        $scriptDir = Split-Path $script:MAINTENANCE_SCRIPT
        if (-not (Test-Path $scriptDir)) {
            New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        }

        # Contenido del script — here-string literal para evitar expansion
        # El cierre '@ debe estar en columna 0
$maintContent = @'
#Requires -RunAsAdministrator
$HAS_SSD  = $false
$SYSDRIVE = $env:SystemDrive
try {
    if (Get-PhysicalDisk -EA SilentlyContinue |
        Where-Object { $_.MediaType -eq "SSD" }) { $HAS_SSD = $true }
} catch {}

$logPath = "$env:USERPROFILE\.OptimizarPC\maintenance_log.json"
$log = @{ timestamp=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
          actions=@(); freedMB=0; errors=@() }

try {
    $sz = (Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue |
           Measure-Object -Property Length -Sum).Sum
    if (-not $sz) { $sz = 0 }
    Get-ChildItem $env:TEMP -Recurse -Force -EA SilentlyContinue |
        Remove-Item -Recurse -Force -EA SilentlyContinue
    $mb = [math]::Round($sz/1MB,1)
    $log.freedMB += $mb; $log.actions += "Temp ($mb MB)"
} catch { $log.errors += "Temp: $_" }

try { Clear-RecycleBin -Force -EA SilentlyContinue; $log.actions += "Recycle" } catch { $log.errors += "Recycle: $_" }
try { ipconfig /flushdns 2>$null | Out-Null; $log.actions += "DNS flush"     } catch { $log.errors += "DNS: $_"     }

if ($HAS_SSD) {
    try {
        $d = $SYSDRIVE.TrimEnd(":")
        Optimize-Volume -DriveLetter $d -ReTrim -NormalPriority -EA SilentlyContinue
        $log.actions += "TRIM $d"
    } catch { $log.errors += "TRIM: $_" }
}

try {
    $hist = @()
    if (Test-Path $logPath) {
        try {
            $raw = Get-Content $logPath -Raw | ConvertFrom-Json
            if ($raw -is [System.Array]) { $hist = $raw } else { $hist = @($raw) }
        } catch {}
    }
    $hist += [PSCustomObject]$log
    if ($hist.Count -gt 30) { $hist = $hist[-30..-1] }
    @($hist) | ConvertTo-Json -Depth 4 | Out-File $logPath -Encoding UTF8
} catch {}

try {
    if (Get-Command New-BurntToastNotification -EA SilentlyContinue) {
        New-BurntToastNotification -Text "WinBoost", "Mantenimiento completado"
    }
} catch {}
'@
        $maintContent | Out-File $script:MAINTENANCE_SCRIPT -Encoding UTF8
    } catch {
        return $false
    }

    # Registrar la tarea en Task Scheduler
    try {
        $hourStr = "{0:D2}:00" -f $Hour

        if ($Frequency -eq "Daily") {
            $trigger = New-ScheduledTaskTrigger -Daily -At $hourStr
        } elseif ($Frequency -eq "AtStartup") {
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        } else {
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $hourStr
        }

        $action = New-ScheduledTaskAction `
            -Execute  "powershell.exe" `
            -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$($script:MAINTENANCE_SCRIPT)`""

        $principal = New-ScheduledTaskPrincipal `
            -UserId    $env:USERNAME `
            -LogonType Interactive `
            -RunLevel  Highest

        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit  (New-TimeSpan -Hours 1) `
            -StartWhenAvailable `
            -MultipleInstances   IgnoreNew

        Register-ScheduledTask `
            -TaskName    $script:MAINTENANCE_TASK_NAME `
            -Action      $action `
            -Trigger     $trigger `
            -Principal   $principal `
            -Settings    $settings `
            -Description "WinBoost - Mantenimiento automatico" `
            -Force `
            -EA Stop | Out-Null

        return $true
    } catch {
        return $false
    }
}

# ------------------------------------------------------------
# Get-MaintenanceTask
# Lee el estado de la tarea de mantenimiento desde el
# Programador de tareas de Windows.
# Devuelve: Exists, Enabled, State, LastRun, NextRun
# ------------------------------------------------------------
function Get-MaintenanceTask {
    $result = [PSCustomObject]@{
        Exists  = $false
        Enabled = $false
        State   = "NotFound"
        LastRun = $null
        NextRun = $null
    }
    try {
        $task = Get-ScheduledTask -TaskName $script:MAINTENANCE_TASK_NAME -EA SilentlyContinue
        if ($task) {
            $info = Get-ScheduledTaskInfo -TaskName $script:MAINTENANCE_TASK_NAME -EA SilentlyContinue
            $result.Exists  = $true
            $result.Enabled = ($task.State -ne "Disabled")
            $result.State   = $task.State.ToString()
            $result.LastRun = if ($info -and $info.LastRunTime.Year -gt 2000) {
                                  $info.LastRunTime
                              } else { $null }
            $result.NextRun = if ($info -and $info.NextRunTime.Year -gt 2000) {
                                  $info.NextRunTime
                              } else { $null }
        }
    } catch {}
    return $result
}

# ------------------------------------------------------------
# Remove-MaintenanceTask
# Elimina la tarea del Programador de tareas y el script
# de mantenimiento generado del disco.
# Devuelve $true si se elimino correctamente.
# ------------------------------------------------------------
function Remove-MaintenanceTask {
    $ok = $true
    try {
        Unregister-ScheduledTask -TaskName $script:MAINTENANCE_TASK_NAME `
            -Confirm:$false -EA Stop
    } catch { $ok = $false }
    try {
        if (Test-Path $script:MAINTENANCE_SCRIPT) {
            Remove-Item $script:MAINTENANCE_SCRIPT -Force -EA SilentlyContinue
        }
    } catch {}
    return $ok
}

# ============================================================
# MODULO 6B - UI DE TEMPERATURA
# ============================================================

# Controles Temperatura
$barCPUTempFill   = Get-Ctrl "barCPUTempFill"
$lblCPUTemp       = Get-Ctrl "lblCPUTemp"
$barGPUTempFill   = Get-Ctrl "barGPUTempFill"
$lblGPUTemp       = Get-Ctrl "lblGPUTemp"
$lblGPUTempSource = Get-Ctrl "lblGPUTempSource"

# Brush gris para estado N/D — congelado para evitar allocations en el timer
$script:brGray = New-Brush "#555555"

# Simbolo de grado generado en runtime para mantener el fuente ASCII-limpio
$script:degSymbol = [char]0x00B0

# ------------------------------------------------------------
# Update-ThermalDisplay
# Actualiza las filas CPU Temp y GPU Temp en el monitor.
# Colores reactivos: verde <70 | amarillo 70-85 | rojo >85
# Manejo graceful si el sensor no esta disponible (N/D + barra gris).
# ------------------------------------------------------------
function Update-ThermalDisplay {
    try {
        $thermal = Get-ThermalStatus

        # --- CPU (F0.8: verificacion explicita de Available) ---
        if ($thermal.CPU.Available -eq $true) {
            $cpuC = $thermal.CPU.TempC
            $barCPUTempFill.Height = [math]::Max(2, [math]::Round(110 * [math]::Min(100, $cpuC) / 100, 0))
            $lblCPUTemp.Text = "$cpuC$($script:degSymbol)C"
            $col = if ($cpuC -ge 85) { $brMon.Red }
                   elseif ($cpuC -ge 70) { $brMon.Yellow }
                   else { $brMon.Green }
            $barCPUTempFill.Background = $col
            $lblCPUTemp.Foreground     = $col
        } else {
            $barCPUTempFill.Height     = 0
            $lblCPUTemp.Text           = "N/D"
            $barCPUTempFill.Background = $script:brGray
            $lblCPUTemp.Foreground     = $script:brGray
        }

        # --- GPU (F0.8: verificacion explicita de Available) ---
        if ($thermal.GPU.Available -eq $true) {
            $gpuC = $thermal.GPU.TempC
            $barGPUTempFill.Height = [math]::Max(2, [math]::Round(110 * [math]::Min(100, $gpuC) / 100, 0))
            $lblGPUTemp.Text = "$gpuC$($script:degSymbol)C"
            $col = if ($gpuC -ge 85) { $brMon.Red }
                   elseif ($gpuC -ge 70) { $brMon.Yellow }
                   else { $brMon.Green }
            $barGPUTempFill.Background   = $col
            $lblGPUTemp.Foreground       = $col
            $lblGPUTempSource.Visibility = "Visible"
        } else {
            $barGPUTempFill.Height       = 0
            $lblGPUTemp.Text             = "N/D"
            $barGPUTempFill.Background   = $script:brGray
            $lblGPUTemp.Foreground       = $script:brGray
            $lblGPUTempSource.Visibility = "Collapsed"
        }
    } catch {}
}

# Extender monitorTimer: leer temperatura cada 5 ticks (= ~5 s)
# La consulta CIM es mas lenta que PerformanceCounter — no leer en cada tick de 1 s.
$script:thermalTick = 0
$script:monitorTimer.Add_Tick({
    if ($script:shuttingDown) { return }
    $script:thermalTick++
    if ($script:thermalTick -ge 5) {
        $script:thermalTick = 0
        try { Update-ThermalDisplay } catch {}
    }
})

# ============================================================
# MODULO 7B - UI DE MANTENIMIENTO AUTOMATICO
# ============================================================

# Controles Mantenimiento
$tglMaintenance  = Get-Ctrl "tglMaintenance"
$cboMaintFreq    = Get-Ctrl "cboMaintFreq"
$cboMaintHour    = Get-Ctrl "cboMaintHour"
$chkMaintTemp    = Get-Ctrl "chkMaintTemp"
$chkMaintRecycle = Get-Ctrl "chkMaintRecycle"
$chkMaintDNS     = Get-Ctrl "chkMaintDNS"
$chkMaintTRIM    = Get-Ctrl "chkMaintTRIM"
$lblLastMaint    = Get-Ctrl "lblLastMaint"
$lblNextMaint    = Get-Ctrl "lblNextMaint"
$btnRunMaintNow  = Get-Ctrl "btnRunMaintNow"
$lblMaintStatus  = Get-Ctrl "lblMaintStatus"

# Poblar hora (00:00 - 23:00) y deshabilitar TRIM si no hay SSD
for ($h_ = 0; $h_ -le 23; $h_++) {
    $itm = New-Object Windows.Controls.ComboBoxItem
    $itm.Content = "{0:D2}:00" -f $h_
    $cboMaintHour.Items.Add($itm) | Out-Null
}
$cboMaintHour.SelectedIndex = 10
if (-not $HAS_SSD) {
    $chkMaintTRIM.IsChecked  = $false
    $chkMaintTRIM.IsEnabled  = $false
}

# Brushes reutilizables para el toggle — creados una sola vez
$script:brMaintOn   = New-Brush "#122A12"
$script:brMaintOnFg = New-Brush "#22C55E"
$script:brMaintOff  = New-Brush "#1E1E1E"
$script:brMaintOffFg= New-Brush "#CCCCCC"
$script:brMaintErr  = New-Brush "#555555"

# ------------------------------------------------------------
# Update-MaintUI
# Lee el estado de la tarea desde Task Scheduler y sincroniza
# todos los controles de la seccion de mantenimiento.
# ------------------------------------------------------------
function Update-MaintUI {
    try {
        $taskInfo = Get-MaintenanceTask

        if ($taskInfo.Exists -and $taskInfo.Enabled) {
            $tglMaintenance.Content    = "Desactivar"
            $tglMaintenance.Background = $script:brMaintOn
            $tglMaintenance.Foreground = $script:brMaintOnFg
            $lblMaintStatus.Text       = "Activo"
            $lblMaintStatus.Foreground = $script:brMaintOnFg
            $btnRunMaintNow.IsEnabled  = $true
        } else {
            $tglMaintenance.Content    = "Activar"
            $tglMaintenance.Background = $script:brMaintOff
            $tglMaintenance.Foreground = $script:brMaintOffFg
            $lblMaintStatus.Text       = if ($taskInfo.Exists) { "Desactivado" } else { "No configurado" }
            $lblMaintStatus.Foreground = $script:brMaintErr
            $btnRunMaintNow.IsEnabled  = $false
        }

        if ($taskInfo.LastRun) {
            $lblLastMaint.Text = "Ultimo mantenimiento: $($taskInfo.LastRun.ToString('dd/MM/yyyy HH:mm'))"
        } else {
            $lblLastMaint.Text = "Ultimo mantenimiento: Nunca"
        }

        if ($taskInfo.NextRun) {
            $lblNextMaint.Text = "Proximo: $($taskInfo.NextRun.ToString('dd/MM/yyyy HH:mm'))"
        } else {
            $lblNextMaint.Text = "Proximo: --"
        }

        # Deshabilitar selector de hora si la frecuencia es AtStartup
        $cboMaintHour.IsEnabled = ($cboMaintFreq.SelectedIndex -ne 2)
    } catch {}
}

# Deshabilitar hora cuando se selecciona "Al iniciar Windows"
$cboMaintFreq.Add_SelectionChanged({
    $cboMaintHour.IsEnabled = ($cboMaintFreq.SelectedIndex -ne 2)
})

# Toggle ON/OFF
$tglMaintenance.Add_Click({
    # --- Gate Pro: mantenimiento automatico ---
    if (Lock-ProFeature "Mantenimiento automatico") { return }

    $tglMaintenance.IsEnabled = $false
    Flush-UI

    try {
        $taskInfo = Get-MaintenanceTask

        if ($taskInfo.Exists -and $taskInfo.Enabled) {
            # Desactivar: eliminar tarea
            Remove-MaintenanceTask | Out-Null
        } else {
            # Activar: crear tarea con configuracion actual
            $freqIdx = $cboMaintFreq.SelectedIndex
            $freq = if ($freqIdx -eq 0) { "Daily" }
                    elseif ($freqIdx -eq 2) { "AtStartup" }
                    else { "Weekly" }

            $hourIdx = $cboMaintHour.SelectedIndex
            if ($hourIdx -lt 0) { $hourIdx = 10 }

            New-MaintenanceTask -Frequency $freq -Hour $hourIdx | Out-Null
        }
    } catch {}

    Update-MaintUI
    $tglMaintenance.IsEnabled = $true
    Flush-UI
})

# Ejecutar ahora
$btnRunMaintNow.Add_Click({
    # --- Gate Pro: mantenimiento automatico ---
    if (Lock-ProFeature "Mantenimiento automatico") { return }

    $btnRunMaintNow.IsEnabled = $false
    $lblMaintStatus.Text      = "Ejecutando..."
    $lblMaintStatus.Foreground = $script:brMaintErr
    Flush-UI

    try {
        $result  = Invoke-MaintenanceCycle
        $mbTotal = [math]::Round($result.freedMB, 1)
        $lblMaintStatus.Text       = "Completado  $mbTotal MB liberados"
        $lblMaintStatus.Foreground = $script:brMaintOnFg
        $lblLastMaint.Text         = "Ultimo mantenimiento: $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
    } catch {
        $lblMaintStatus.Text       = "Error en mantenimiento"
        $lblMaintStatus.Foreground = New-Brush "#EF4444"
    }

    $btnRunMaintNow.IsEnabled = $true
    Flush-UI
})

# Leer estado inicial de la tarea al arrancar
Update-MaintUI

# ============================================================
# MODULO 8A - MOTOR DE HISTORIAL ENRIQUECIDO
# ============================================================

# ------------------------------------------------------------
# Get-SessionHistory
# Construye sobre Get-BackupSessions agregando campos calculados:
# scoreBefore, scoreAfter, scoreImprovement, date (DateTime).
# Solo incluye sesiones con session.json completo (hasMeta).
# Retorna array ordenado por fecha descendente.
# ------------------------------------------------------------
function Get-SessionHistory {
    $raw    = Get-BackupSessions
    $result = @()

    foreach ($s in $raw) {
        if (-not $s.hasMeta) { continue }
        $m = $s.meta

        $scoreBefore = 0
        $scoreAfter  = 0
        try { $scoreBefore = [int]$m.scoreBefore } catch {}
        try { $scoreAfter  = [int]$m.scoreAfter  } catch {}

        $parsedDate = $null
        try {
            $parsedDate = [datetime]::ParseExact(
                $m.timestamp, "yyyy-MM-dd HH:mm:ss",
                [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {}
        if ($null -eq $parsedDate) {
            try { $parsedDate = [datetime]$m.timestamp } catch {}
        }

        $freedMB_     = 0
        $actionCount_ = 0
        try { $freedMB_     = [int]$m.freedMB     } catch {}
        try { $actionCount_ = [int]$m.actionCount } catch {}

        $result += [PSCustomObject]@{
            timestamp        = $m.timestamp
            date             = $parsedDate
            preset           = if ($m.preset) { [string]$m.preset } else { "Manual" }
            freedMB          = $freedMB_
            actionCount      = $actionCount_
            scoreBefore      = $scoreBefore
            scoreAfter       = $scoreAfter
            scoreImprovement = $scoreAfter - $scoreBefore
            sessionPath      = $s.path
        }
    }

    return $result
}

# ------------------------------------------------------------
# Get-HistoryStats
# Estadisticas agregadas de todas las sesiones con metadata.
# Retorna: TotalSessions, TotalFreedMB, AvgImprovement,
#          TotalImprovement, FirstSession (DateTime), DaysSince.
# Devuelve $null si no hay sesiones registradas.
# ------------------------------------------------------------
function Get-HistoryStats {
    $history = Get-SessionHistory
    if ($history.Count -eq 0) { return $null }

    $szSum  = ($history | Measure-Object -Property freedMB          -Sum).Sum
    $impSum = ($history | Measure-Object -Property scoreImprovement -Sum).Sum

    $totalMB  = if ($null -ne $szSum)  { [math]::Round($szSum, 0) } else { 0 }
    $totalImp = if ($null -ne $impSum) { $impSum                  } else { 0 }
    $avgImp   = [math]::Round($totalImp / $history.Count, 1)

    # Primera sesion: ultimo elemento del array (ya ordenado descendente)
    $firstDate = $null
    $oldest    = $history[$history.Count - 1]
    if ($null -ne $oldest -and $null -ne $oldest.date) {
        $firstDate = $oldest.date
    }

    $daysSince = 0
    if ($null -ne $firstDate) {
        $daysSince = [int]([datetime]::Now - $firstDate).TotalDays
    }

    return [PSCustomObject]@{
        TotalSessions    = $history.Count
        TotalFreedMB     = $totalMB
        AvgImprovement   = $avgImp
        TotalImprovement = $totalImp
        FirstSession     = $firstDate
        DaysSince        = $daysSince
    }
}

# ============================================================
# MODULO 8B - UI DE HISTORIAL ENRIQUECIDO
# ============================================================

$lblHistTotalSessions  = Get-Ctrl "lblHistTotalSessions"
$lblHistTotalMB        = Get-Ctrl "lblHistTotalMB"
$lblHistAvgImprovement = Get-Ctrl "lblHistAvgImprovement"
$lblHistDaysSince      = Get-Ctrl "lblHistDaysSince"
$icScoreHistory        = Get-Ctrl "icScoreHistory"

# ------------------------------------------------------------
# Update-HistoryStats
# Carga Get-HistoryStats y rellena los 4 cards de estadisticas.
# ------------------------------------------------------------
function Update-HistoryStats {
    try {
        $stats = Get-HistoryStats
        if ($null -eq $stats) {
            $lblHistTotalSessions.Text  = "0"
            $lblHistTotalMB.Text        = "0"
            $lblHistAvgImprovement.Text = "--"
            $lblHistDaysSince.Text      = "--"
        } else {
            $lblHistTotalSessions.Text  = "$($stats.TotalSessions)"
            $lblHistTotalMB.Text        = "$($stats.TotalFreedMB)"
            $sign = if ($stats.AvgImprovement -ge 0) { "+" } else { "" }
            $lblHistAvgImprovement.Text = "${sign}$($stats.AvgImprovement)"
            $lblHistDaysSince.Text      = "$($stats.DaysSince)"
        }
    } catch {}
}

# ------------------------------------------------------------
# Render-ScoreHistory
# Dibuja el mini grafico de barras de scoreAfter en el Canvas
# icScoreHistory (ultimas 8 sesiones, de mas antigua a reciente).
# ------------------------------------------------------------
function Render-ScoreHistory {
    try {
        $icScoreHistory.Children.Clear()
        $history = Get-SessionHistory

        if ($history.Count -eq 0) {
            $ph            = New-Object Windows.Controls.TextBlock
            $ph.Text       = "Sin datos de sesiones aun"
            $ph.FontSize   = 11
            $ph.Foreground = New-Brush "#3A3A3A"
            $ph.VerticalAlignment = [Windows.VerticalAlignment]::Center
            $icScoreHistory.Children.Add($ph) | Out-Null
            return
        }

        $maxH    = 56
        $take    = [math]::Min(8, $history.Count)
        $sessions = @($history[0..($take - 1)])
        [array]::Reverse($sessions)

        # Calcular barWidth segun el ancho real del canvas; fallback antes del layout
        $canvasW  = $icScoreHistory.ActualWidth
        if ($canvasW -lt 10) { $canvasW = 320 }
        $gap      = 6
        $barWidth = [math]::Min(28, [math]::Max(8, [int](($canvasW - ($take - 1) * $gap) / $take)))
        $totalW   = $take * $barWidth + ($take - 1) * $gap
        $xOffset  = [math]::Max(0, [int](($canvasW - $totalW) / 2))

        for ($i = 0; $i -lt $sessions.Count; $i++) {
            $s     = $sessions[$i]
            $score = [math]::Max(0, [math]::Min(100, [int]$s.scoreAfter))
            $barH  = [math]::Max(2, [int]($score * $maxH / 100))
            $barX  = $xOffset + $i * ($barWidth + $gap)

            $track            = New-Object Windows.Controls.Border
            $track.Width      = $barWidth
            $track.Height     = $maxH
            $track.CornerRadius = New-Object Windows.CornerRadius(2)
            $track.Background = New-Brush "#1A1A1A"
            [Windows.Controls.Canvas]::SetLeft($track,   $barX)
            [Windows.Controls.Canvas]::SetBottom($track, 0)
            $icScoreHistory.Children.Add($track) | Out-Null

            $barCol = if ($score -ge 75) { "#22C55E" }
                      elseif ($score -ge 45) { "#F59E0B" }
                      else { "#EF4444" }
            $bar            = New-Object Windows.Controls.Border
            $bar.Width      = $barWidth
            $bar.Height     = $barH
            $bar.CornerRadius = New-Object Windows.CornerRadius(2,2,0,0)
            $bar.Background = New-Brush $barCol
            [Windows.Controls.Canvas]::SetLeft($bar,   $barX)
            [Windows.Controls.Canvas]::SetBottom($bar, 0)
            $icScoreHistory.Children.Add($bar) | Out-Null
        }
    } catch {}
}

# Enganchar en el boton Actualizar para refrescar stats + chart junto con la lista
$btnRefreshHistory.Add_Click({
    Update-HistoryStats
    Render-ScoreHistory
    Flush-UI
})

# Poblar al arrancar
Update-HistoryStats
Render-ScoreHistory

# ============================================================
# MODULO 9A - MOTOR DE DETECCION FULLSCREEN
# ============================================================

# Tipos Win32 para P/Invoke (compilacion idempotente)
if (-not ('Win32FS' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct FSRect {
    public int Left, Top, Right, Bottom;
}

[StructLayout(LayoutKind.Sequential)]
public struct FSMonitorInfo {
    public int    cbSize;
    public FSRect rcMonitor;
    public FSRect rcWork;
    public uint   dwFlags;
}

public class Win32FS {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out FSRect lpRect);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint dwFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref FSMonitorInfo lpmi);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDesktopWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetShellWindow();
}
'@ -EA Stop
    } catch {
        Write-Log "Modulo 9A: no se pudo compilar Win32FS - deteccion fullscreen no disponible" "err"
    }
}

# Lista de juegos conocidos (nombre de proceso sin .exe, minusculas)
$script:knownGames = @(
    "csgo", "cs2", "valorant", "fortnite", "minecraft", "javaw",
    "steam", "epicgameslauncher", "leagueclient", "leagueclientux",
    "dota2", "overwatch", "overwatch2", "gta5", "gtav",
    "rocketleague", "apexlegends", "apex", "battlefield1", "bf4",
    "rainbow6", "r6", "pubg", "tslgame", "warzone",
    "modernwarfare", "eldenring", "cyberpunk2077", "witcher3",
    "destiny2", "hogwartslegacy", "baldursgate3", "bg3",
    "starfield", "fallout4", "skyrimse", "sekiro", "thunderstore"
)

# ------------------------------------------------------------
# Test-FullscreenProcess
# Detecta si la ventana en primer plano ocupa exactamente el
# area del monitor (fullscreen o borderless fullscreen).
# Devuelve el objeto Process si hay aplicacion fullscreen,
# o $null si no hay ninguna.
# ------------------------------------------------------------
function Test-FullscreenProcess {
    try {
        if (-not ('Win32FS' -as [type])) { return $null }

        $hwnd = [Win32FS]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return $null }

        # Excluir escritorio y shell de Windows
        $desktop = [Win32FS]::GetDesktopWindow()
        $shell   = [Win32FS]::GetShellWindow()
        if ($hwnd -eq $desktop -or $hwnd -eq $shell) { return $null }

        # Rect de la ventana activa
        $winRect = New-Object FSRect
        if (-not [Win32FS]::GetWindowRect($hwnd, [ref]$winRect)) { return $null }

        # Monitor que contiene la ventana
        $hMon = [Win32FS]::MonitorFromWindow($hwnd, 2)   # MONITOR_DEFAULTTONEAREST=2
        if ($hMon -eq [IntPtr]::Zero) { return $null }

        # Info del monitor (cbSize requerido antes de llamar a GetMonitorInfo)
        $monInfo        = New-Object FSMonitorInfo
        $monInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([FSMonitorInfo])
        if (-not [Win32FS]::GetMonitorInfo($hMon, [ref]$monInfo)) { return $null }

        $mon = $monInfo.rcMonitor

        # Fullscreen = rect de ventana identico al rect del monitor fisico
        $isFullscreen = ($winRect.Left   -eq $mon.Left)  -and
                        ($winRect.Top    -eq $mon.Top)    -and
                        ($winRect.Right  -eq $mon.Right)  -and
                        ($winRect.Bottom -eq $mon.Bottom)

        if (-not $isFullscreen) { return $null }

        # Obtener proceso propietario de la ventana
        $wndPid = [uint32]0
        [Win32FS]::GetWindowThreadProcessId($hwnd, [ref]$wndPid) | Out-Null
        if ($wndPid -eq 0) { return $null }

        $proc = Get-Process -Id ([int]$wndPid) -EA SilentlyContinue
        return $proc
    } catch { return $null }
}

# ------------------------------------------------------------
# Test-KnownGame
# Devuelve $true si el proceso pertenece a la lista de juegos
# conocidos ($script:knownGames). Comparacion case-insensitive.
# ------------------------------------------------------------
function Test-KnownGame {
    param([System.Diagnostics.Process]$proc)
    if (-not $proc) { return $false }
    $name = $proc.Name.ToLower()
    foreach ($game in $script:knownGames) {
        if ($name -like "*$game*") { return $true }
    }
    return $false
}

# ============================================================
# MODULO 9B - MOTOR DE OPTIMIZACION EN FOCO (GAME MODE)
# ============================================================

# F2.20 — Calcula la mascara de afinidad de nucleos fisicos.
# Retorna mascara con los primeros N bits (N = nucleos fisicos).
# Si SMT no esta activo (logicos == fisicos), retorna -1 (sin cambio util).
function Get-PhysicalCoreMask {
    try {
        $cpu      = Get-CimInstance Win32_Processor | Select-Object -First 1
        $physical = [int]$cpu.NumberOfCores
        $logical  = [int]$cpu.NumberOfLogicalProcessors
        if($logical -le $physical -or $physical -lt 1){ return -1 }
        # Mascara = primeros $physical bits: 2^N - 1
        $mask = [long]([math]::Pow(2, $physical) - 1)
        return $mask
    } catch { return -1 }
}

# Estado global de focus mode (null = inactivo)
$script:gameFocusState = $null

# Ruta de registro para suprimir notificaciones toast
$script:toastRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"

# ------------------------------------------------------------
# Apply-GameFocusMode
# Eleva la prioridad del proceso al nivel High y suprime las
# notificaciones toast. Guarda el estado previo para restaurar.
# Parametro: proceso fullscreen detectado por Test-FullscreenProcess.
# ------------------------------------------------------------
function Apply-GameFocusMode {
    param([System.Diagnostics.Process]$proc)
    if (-not $proc) { return }

    # Leer estado previo de prioridad
    $prevPriority = $null
    try { $prevPriority = $proc.PriorityClass } catch {}

    # Leer estado previo de notificaciones toast
    $prevToast = 1
    try {
        $val = (Get-ItemProperty -Path $script:toastRegPath -Name "ToastEnabled" -EA SilentlyContinue).ToastEnabled
        if ($null -ne $val) { $prevToast = [int]$val }
    } catch {}

    # Persistir estado para restaurar al salir
    $script:gameFocusState = [PSCustomObject]@{
        Active           = $true
        Process          = $proc
        PreviousPriority = $prevPriority
        PreviousToast    = $prevToast
        PreviousAffinity = [long]-1
    }

    # Elevar prioridad del proceso
    try {
        $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
    } catch {}

    # Suprimir notificaciones toast
    try {
        if (-not (Test-Path $script:toastRegPath)) {
            New-Item -Path $script:toastRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $script:toastRegPath -Name "ToastEnabled" -Value 0 -Type DWord -EA SilentlyContinue
    } catch {}

    # F2.20 — Afinidad de CPU a nucleos fisicos (si el ajuste esta activado)
    if($script:settings.GameAffinityEnabled){
        $affinityMask = Get-PhysicalCoreMask
        if($affinityMask -gt 0){
            try {
                $script:gameFocusState.PreviousAffinity = $proc.ProcessorAffinity.ToInt64()
                $proc.ProcessorAffinity = [IntPtr][long]$affinityMask
                Write-Log "Gaming Mode ON - $($proc.Name) (PID $($proc.Id)) prioridad High, notificaciones OFF, afinidad CPU fisica (mascara 0x$([Convert]::ToString($affinityMask,16).ToUpper()))" "ok"
            } catch {
                Write-Log "Gaming Mode ON - $($proc.Name) (PID $($proc.Id)) prioridad High, notificaciones OFF (afinidad CPU no disponible)" "ok"
            }
        } else {
            Write-Log "Gaming Mode ON - $($proc.Name) (PID $($proc.Id)) prioridad High, notificaciones OFF (sin SMT/HT, afinidad sin cambio)" "ok"
        }
    } else {
        Write-Log "Gaming Mode ON - $($proc.Name) (PID $($proc.Id)) prioridad High, notificaciones OFF" "ok"
    }
}

# ------------------------------------------------------------
# Restore-GameFocusMode
# Restaura la prioridad del proceso y el estado de notificaciones
# al valor guardado por Apply-GameFocusMode.
# ------------------------------------------------------------
function Restore-GameFocusMode {
    if (-not $script:gameFocusState -or -not $script:gameFocusState.Active) { return }

    $state = $script:gameFocusState

    # Restaurar prioridad del proceso (si sigue corriendo)
    try {
        $proc = $state.Process
        if ($null -ne $proc -and -not $proc.HasExited -and $null -ne $state.PreviousPriority) {
            $proc.PriorityClass = $state.PreviousPriority
        }
    } catch {}

    # Restaurar notificaciones toast
    try {
        if (Test-Path $script:toastRegPath) {
            Set-ItemProperty -Path $script:toastRegPath -Name "ToastEnabled" `
                -Value $state.PreviousToast -Type DWord -EA SilentlyContinue
        }
    } catch {}

    # F2.20 — Restaurar afinidad de CPU si fue modificada
    if($state.PreviousAffinity -ge 0){
        try {
            $proc2 = $state.Process
            if($null -ne $proc2 -and -not $proc2.HasExited){
                $proc2.ProcessorAffinity = [IntPtr][long]$state.PreviousAffinity
            }
        } catch {}
    }

    $script:gameFocusState.Active = $false
    Write-Log "Gaming Mode OFF - prioridad, notificaciones y afinidad CPU restauradas" "info"
}

# ============================================================
# MODULO 9C - DISPATCHER TIMER DE DETECCION FULLSCREEN
# ============================================================

$badgeGamingMode = Get-Ctrl "badgeGamingMode"

# DispatcherTimer independiente — tick cada 5 segundos
$script:gamingTimer          = New-Object Windows.Threading.DispatcherTimer
$script:gamingTimer.Interval = [TimeSpan]::FromSeconds(5)

$script:gamingTimer.Add_Tick({
    try {
        $proc        = Test-FullscreenProcess
        $isGame      = Test-KnownGame $proc
        $focusActive = ($null -ne $script:gameFocusState) -and $script:gameFocusState.Active

        # Si el proceso en foco ya no existe, marcar como inactivo sin restaurar
        if ($focusActive) {
            try {
                if ($script:gameFocusState.Process.HasExited) {
                    $script:gameFocusState.Active = $false
                    $focusActive = $false
                    $badgeGamingMode.Visibility = "Collapsed"
                }
            } catch { $focusActive = $false }
        }

        if ($isGame -and -not $focusActive) {
            # Juego detectado en fullscreen — activar focus mode (solo una vez)
            Apply-GameFocusMode $proc
            $badgeGamingMode.Visibility = "Visible"

        } elseif (-not $isGame -and $focusActive) {
            # Juego ya no esta en fullscreen — restaurar estado
            Restore-GameFocusMode
            $badgeGamingMode.Visibility = "Collapsed"
        }
    } catch {}
})

$script:gamingTimer.Start()

# Detener el timer cuando se cierra la ventana
$window.Add_Closing({
    try { $script:gamingTimer.Stop() } catch {}
    # Restaurar focus mode si la app se cierra con un juego activo
    try { if ($script:gameFocusState -and $script:gameFocusState.Active) { Restore-GameFocusMode } } catch {}
})

# ============================================================
# MODULO 10 - EXPORTAR REPORTE HTML
# ============================================================

# ------------------------------------------------------------
# Build-HTMLReport
# Genera el HTML completo (standalone, CSS inline) con:
# info del sistema, score antes/despues, resumen de sesion
# y lista de acciones aplicadas.
# Devuelve el HTML como string.
# ------------------------------------------------------------
function Build-HTMLReport {
    # --- Datos del sistema ---
    $rptDate   = Get-Date -Format "yyyy-MM-dd"
    $rptTS     = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $rptCPU    = if ($cpuName)    { [System.Net.WebUtility]::HtmlEncode([string]$cpuName) } else { "N/D" }
    $rptGPU    = if ($gpuName)    { [System.Net.WebUtility]::HtmlEncode([string]$gpuName) } else { "N/D" }
    $rptRAM    = "$totalRAM GB"
    $rptSSD    = if ($HAS_SSD)    { "Si (SSD)" } else { "No (HDD)" }
    $rptLaptop = if ($IS_LAPTOP)  { "Portatil" } else { "Escritorio" }
    $rptDrive  = [string]$SYSDRIVE

    # --- Score ---
    $rptSB  = if ($null -ne $script:scoreBefore) { [int]$script:scoreBefore } else { 0 }
    $rptSA  = if ($null -ne $script:scoreAfter  ) { [int]$script:scoreAfter  } else { 0 }
    $rptDelta = $rptSA - $rptSB
    $rptSign  = if ($rptDelta -gt 0) { "+" } else { "" }
    $rptDeltaClass = if ($rptDelta -gt 0) { "delta-pos" } elseif ($rptDelta -lt 0) { "delta-neg" } else { "delta-neu" }
    $rptColorSB = if ($rptSB -ge 75) { "#22C55E" } elseif ($rptSB -ge 45) { "#F59E0B" } else { "#EF4444" }
    $rptColorSA = if ($rptSA -ge 75) { "#22C55E" } elseif ($rptSA -ge 45) { "#F59E0B" } else { "#EF4444" }

    # --- Metricas medibles (F0.3) ---
    $rptBootB  = if ($script:snapshotBefore -and $script:snapshotBefore.BootTimeSec -ge 0) { "$($script:snapshotBefore.BootTimeSec) s" } else { "N/D" }
    $rptBootA  = if ($script:snapshotAfter  -and $script:snapshotAfter.BootTimeSec  -ge 0) { "$($script:snapshotAfter.BootTimeSec) s"  } else { "N/D" }
    $rptRAMB   = if ($script:snapshotBefore) { "$($script:snapshotBefore.RAMFreeMB) MB" } else { "N/D" }
    $rptRAMA   = if ($script:snapshotAfter ) { "$($script:snapshotAfter.RAMFreeMB) MB"  } else { "N/D" }
    $rptProcB  = if ($script:snapshotBefore) { [string]$script:snapshotBefore.ProcCount } else { "N/D" }
    $rptProcA  = if ($script:snapshotAfter ) { [string]$script:snapshotAfter.ProcCount  } else { "N/D" }

    $rptRAMDelta  = ""
    $rptRAMClass  = "delta-neu"
    if ($script:snapshotBefore -and $script:snapshotAfter) {
        $d = $script:snapshotAfter.RAMFreeMB - $script:snapshotBefore.RAMFreeMB
        if ($d -gt 0) { $rptRAMDelta = "+$d MB"; $rptRAMClass = "delta-pos" }
        elseif ($d -lt 0) { $rptRAMDelta = "$d MB"; $rptRAMClass = "delta-neg" }
        else { $rptRAMDelta = "sin cambio"; $rptRAMClass = "delta-neu" }
    }
    $rptProcDelta = ""
    $rptProcClass = "delta-neu"
    if ($script:snapshotBefore -and $script:snapshotAfter) {
        $d = $script:snapshotAfter.ProcCount - $script:snapshotBefore.ProcCount
        if ($d -lt 0) { $rptProcDelta = "$d proc"; $rptProcClass = "delta-pos" }
        elseif ($d -gt 0) { $rptProcDelta = "+$d proc"; $rptProcClass = "delta-neg" }
        else { $rptProcDelta = "sin cambio"; $rptProcClass = "delta-neu" }
    }
    $rptBootNote = "El tiempo de arranque refleja el ultimo inicio. Reinicia para ver la mejora real."

    # --- Sesion ---
    $rptFreed = if ($null -ne $script:freed) { [math]::Round($script:freed, 0) } else { 0 }
    $rptCount = if ($script:sessionActions)  { $script:sessionActions.Count    } else { 0 }

    # --- Lista de acciones como HTML ---
    $rptActions = ""
    if ($script:sessionActions -and $script:sessionActions.Count -gt 0) {
        foreach ($a in $script:sessionActions) {
            $enc = [System.Net.WebUtility]::HtmlEncode([string]$a)
            $rptActions += "        <li>$enc</li>`n"
        }
    } else {
        $rptActions = "        <li>Sin acciones registradas en esta sesion.</li>`n"
    }

    # --- Color helpers para la seccion hero ---
    $rptRAMColor   = if ($rptRAMClass  -eq "delta-pos") { "#22C55E" } elseif ($rptRAMClass  -eq "delta-neg") { "#EF4444" } else { "#888888" }
    $rptProcColor  = if ($rptProcClass -eq "delta-pos") { "#22C55E" } elseif ($rptProcClass -eq "delta-neg") { "#EF4444" } else { "#888888" }
    $rptDeltaColor = if ($rptDelta -gt 0) { "#22C55E" } elseif ($rptDelta -lt 0) { "#EF4444" } else { "#888888" }
    $rptRAMDeltaDisp  = if ($rptRAMDelta  -ne "") { $rptRAMDelta  } else { "N/D" }
    $rptProcDeltaDisp = if ($rptProcDelta -ne "") { $rptProcDelta } else { "N/D" }

    # --- Tecnico field (F2.16) ---
    $rptTechRow = ""
    if ($script:IS_TECH -and -not [string]::IsNullOrWhiteSpace($script:settings.TechnicianName)) {
        $rptTechEnc = [System.Net.WebUtility]::HtmlEncode([string]$script:settings.TechnicianName)
        $rptTechRow = "<div class=`"row`"><span class=`"lbl`">Tecnico</span><span class=`"val`" style=`"color:#00C8FF`">$rptTechEnc</span></div>"
    }

    # --- Generar HTML (double-quoted here-string, variables expandidas) ---
    return @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>WinBoost v$VERSION - Reporte $rptDate</title>
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
  <div class="hdr-t">WinBoost <span>v$VERSION</span> &mdash; Reporte</div>
  <div class="hdr-m">$rptTS<br/>$rptLaptop &bull; $rptDrive</div>
</div>

<!-- RESULTADOS MEDIBLES -->
<div style="background:#0D1A0D;border:1px solid #1E3A1E;border-radius:10px;padding:22px 24px;margin-bottom:14px">
  <div style="font-size:10px;font-weight:600;color:#22C55E;letter-spacing:1.5px;text-transform:uppercase;margin-bottom:16px">Resultados medibles</div>
  <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:12px">

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">Score de salud</div>
      <div style="display:flex;justify-content:center;align-items:center;gap:8px;margin-bottom:8px">
        <div>
          <div style="font-size:26px;font-weight:700;color:#666666">$rptSB</div>
          <div style="font-size:9px;color:#444444;margin-top:2px">ANTES</div>
        </div>
        <div style="font-size:14px;color:#3A3A3A">&#x2192;</div>
        <div>
          <div style="font-size:26px;font-weight:700;color:$rptColorSA">$rptSA</div>
          <div style="font-size:9px;color:#444444;margin-top:2px">AHORA</div>
        </div>
      </div>
      <div style="font-size:22px;font-weight:700;color:$rptDeltaColor">${rptSign}${rptDelta} pts</div>
    </div>

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">RAM disponible</div>
      <div style="font-size:12px;color:#555555;margin-bottom:10px">$rptRAMB &rarr; <span style="color:#CCCCCC">$rptRAMA</span></div>
      <div style="font-size:26px;font-weight:700;color:$rptRAMColor">$rptRAMDeltaDisp</div>
    </div>

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">Procesos activos</div>
      <div style="font-size:12px;color:#555555;margin-bottom:10px">$rptProcB &rarr; <span style="color:#CCCCCC">$rptProcA</span></div>
      <div style="font-size:26px;font-weight:700;color:$rptProcColor">$rptProcDeltaDisp</div>
    </div>

    <div style="background:#111111;border-radius:8px;padding:16px;text-align:center">
      <div style="font-size:10px;color:#555555;text-transform:uppercase;letter-spacing:.5px;margin-bottom:10px">Tiempo de arranque</div>
      <div style="font-size:24px;font-weight:700;color:#CCCCCC;margin-bottom:10px">$rptBootB</div>
      <div style="font-size:10px;color:#444444;font-style:italic">reiniciar para ver mejora</div>
    </div>

  </div>
</div>

<div class="sec">
  <div class="sec-hd">Informacion del sistema</div>
$rptTechRow
  <div class="row"><span class="lbl">CPU</span><span class="val">$rptCPU</span></div>
  <div class="row"><span class="lbl">GPU</span><span class="val">$rptGPU</span></div>
  <div class="row"><span class="lbl">RAM total</span><span class="val">$rptRAM</span></div>
  <div class="row"><span class="lbl">Almacenamiento</span><span class="val">$rptSSD</span></div>
</div>

<div class="sec">
  <div class="sec-hd">Resumen de sesion</div>
  <div class="cards">
    <div class="card"><div class="cv">$rptFreed</div><div class="cl">MB liberados</div></div>
    <div class="card"><div class="cv">$rptCount</div><div class="cl">Acciones aplicadas</div></div>
    <div class="card"><div class="cv">${rptSign}${rptDelta}</div><div class="cl">Pts de mejora</div></div>
  </div>
</div>

<div class="sec">
  <div class="sec-hd">Acciones aplicadas</div>
  <ul class="al">
$rptActions  </ul>
</div>

<div class="ft">Generado por WinBoost v$VERSION &mdash; $rptTS</div>
</body>
</html>
"@
}

# ------------------------------------------------------------
# Export-HTMLReport
# Llama Build-HTMLReport, guarda el archivo en Documentos y
# lo abre en el navegador por defecto.
# Devuelve la ruta del archivo generado, o $null si fallo.
# ------------------------------------------------------------
function Export-HTMLReport {
    try {
        $html    = Build-HTMLReport
        $date_   = Get-Date -Format "yyyy-MM-dd"
        $outPath = "$([Environment]::GetFolderPath('MyDocuments'))\OptimizarPC_Reporte_$date_.html"
        $html | Out-File $outPath -Encoding UTF8 -Force
        Start-Process $outPath
        return $outPath
    } catch {
        return $null
    }
}

# Registrar control y evento
$btnExportHTML = Get-Ctrl "btnExportHTML"

$btnExportHTML.Add_Click({
    # --- Gate Pro: exportar reporte HTML ---
    if (Lock-ProFeature "Exportar reporte HTML") { return }

    $btnExportHTML.IsEnabled = $false
    Flush-UI
    try {
        $path = Export-HTMLReport
        if ($path) {
            Write-Log "Reporte HTML exportado: $path" "ok"
        } else {
            Write-Log "Error al exportar reporte HTML" "err"
        }
    } catch {
        Write-Log "Error al exportar reporte HTML: $_" "err"
    }
    $btnExportHTML.IsEnabled = $true
    Flush-UI
})

# ============================================================
# MODULO 11B - MODAL DE COMPARATIVA ANTES/DESPUES
# ============================================================

# ------------------------------------------------------------
# Show-CompareDialog
# Muestra ventana secundaria con la comparativa del sistema
# antes y despues de la optimizacion.
# Retorna: "restart" | "later" | "log"
# ------------------------------------------------------------
function Show-CompareDialog {
    $compare = $script:snapshotCompare
    $freed   = if ($null -ne $script:freed) { [math]::Round($script:freed, 1) } else { 0 }

    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinBoost - Resultado de la optimizacion"
        Width="580" Height="500" MinWidth="460" MinHeight="380"
        WindowStartupLocation="CenterOwner"
        Background="#0D0D0D" FontFamily="Segoe UI"
        ResizeMode="CanResize" ShowInTaskbar="False">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#161616" BorderBrush="#2A2A2A"
            BorderThickness="0,0,0,1" Padding="20,14">
      <StackPanel>
        <TextBlock Text="Resultado de la optimizacion"
                   FontSize="15" FontWeight="SemiBold" Foreground="#EEEEEE"/>
        <TextBlock Text="Comparativa del sistema antes y despues de aplicar los cambios."
                   FontSize="11" Foreground="#888888" Margin="0,3,0,0"/>
      </StackPanel>
    </Border>

    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="spRows" Margin="12,8,12,8"/>
    </ScrollViewer>

    <Border Grid.Row="2" Background="#111111" BorderBrush="#2A2A2A"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="btnViewLog" Content="Ver log" Width="90" Height="32"
                Margin="0,0,8,0" Background="#1E1E1E" Foreground="#CCCCCC"
                BorderBrush="#2A2A2A" BorderThickness="1" Cursor="Hand" FontSize="12">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}"
                      BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter Property="Background" Value="#2A2A2A"/>
                  <Setter Property="BorderBrush" Value="#00C8FF"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
        <Button x:Name="btnLater" Content="Reiniciar despues" Height="32"
                Padding="14,0" Margin="0,0,8,0"
                Background="#1E1E1E" Foreground="#CCCCCC"
                BorderBrush="#2A2A2A" BorderThickness="1" Cursor="Hand" FontSize="12">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}"
                      BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter Property="Background" Value="#2A2A2A"/>
                  <Setter Property="BorderBrush" Value="#555555"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
        <Button x:Name="btnRestart" Content="Reiniciar ahora" Height="32"
                Padding="14,0" Background="#00C8FF" Foreground="#0D0D0D"
                BorderThickness="0" Cursor="Hand" FontSize="12" FontWeight="SemiBold">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}" CornerRadius="6"
                      Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter Property="Background" Value="#33D6FF"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

    $dialog = $null
    try {
        $xmlReader = [System.Xml.XmlReader]::Create(
            [System.IO.StringReader]::new($dialogXaml))
        $dialog = [Windows.Markup.XamlReader]::Load($xmlReader)
        $xmlReader.Close()
    } catch {
        Write-Log "Modal de comparativa no disponible: $_" "skip"
        return "later"
    }

    $spRows     = $dialog.FindName("spRows")
    $btnRestart = $dialog.FindName("btnRestart")
    $btnLater   = $dialog.FindName("btnLater")
    $btnViewLog = $dialog.FindName("btnViewLog")

    # Colores
    $colBetter  = "#22C55E"
    $colNeutral = "#555555"
    $colWorse   = "#EF4444"
    $colValue   = "#CCCCCC"
    $colLabel   = "#777777"
    $colBg      = "#161616"
    $colBgAlt   = "#111111"

    # Scriptblock reutilizable para construir una fila de la tabla
    $mkRow = {
        param($rowLabel, $valBefore, $valAfter, $rowDelta, $rowStatus, $alt)

        $sColor = switch ($rowStatus) {
            "better"  { $colBetter  }
            "worse"   { $colWorse   }
            default   { $colNeutral }
        }
        $sign      = if ($rowDelta -gt 0) { "+" } else { "" }
        $deltaText = if ($rowDelta -eq 0) { "Sin cambio" } else { "$sign$rowDelta" }
        $bgHex     = if ($alt) { $colBgAlt } else { $colBg }

        $bdr = New-Object Windows.Controls.Border
        $bdr.Background  = New-Brush $bgHex
        $bdr.CornerRadius = New-Object Windows.CornerRadius(5)
        $bdr.Padding      = New-Object Windows.Thickness(12, 7, 12, 7)
        $bdr.Margin       = New-Object Windows.Thickness(0, 2, 0, 0)

        $g = New-Object Windows.Controls.Grid
        foreach ($colW in @("16", "1*", "90", "90", "80")) {
            $cd = New-Object Windows.Controls.ColumnDefinition
            if ($colW -eq "1*") {
                $cd.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
            } else {
                $cd.Width = [Windows.GridLength]::new([double]$colW)
            }
            $g.ColumnDefinitions.Add($cd)
        }

        # Dot indicador de estado
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width  = 8; $dot.Height = 8
        $dot.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        $dot.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $dot.Fill = New-Brush $sColor
        [Windows.Controls.Grid]::SetColumn($dot, 0)

        $tLabel = New-Object Windows.Controls.TextBlock
        $tLabel.Text      = $rowLabel
        $tLabel.FontSize  = 12
        $tLabel.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $tLabel.Foreground = New-Brush $colValue
        [Windows.Controls.Grid]::SetColumn($tLabel, 1)

        $tBef = New-Object Windows.Controls.TextBlock
        $tBef.Text      = [string]$valBefore
        $tBef.FontSize  = 12
        $tBef.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $tBef.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        $tBef.Foreground = New-Brush $colLabel
        [Windows.Controls.Grid]::SetColumn($tBef, 2)

        $tAft = New-Object Windows.Controls.TextBlock
        $tAft.Text      = [string]$valAfter
        $tAft.FontSize  = 12
        $tAft.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $tAft.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        $tAft.Foreground = New-Brush $colValue
        [Windows.Controls.Grid]::SetColumn($tAft, 3)

        $tDelta = New-Object Windows.Controls.TextBlock
        $tDelta.Text       = $deltaText
        $tDelta.FontSize   = 11
        $tDelta.FontWeight = [Windows.FontWeights]::SemiBold
        $tDelta.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $tDelta.VerticalAlignment   = [Windows.VerticalAlignment]::Center
        $tDelta.Foreground = New-Brush $sColor
        [Windows.Controls.Grid]::SetColumn($tDelta, 4)

        $g.Children.Add($dot)    | Out-Null
        $g.Children.Add($tLabel) | Out-Null
        $g.Children.Add($tBef)   | Out-Null
        $g.Children.Add($tAft)   | Out-Null
        $g.Children.Add($tDelta) | Out-Null
        $bdr.Child = $g
        return $bdr
    }

    # Header de columnas
    $hdrBdr = New-Object Windows.Controls.Border
    $hdrBdr.Padding = New-Object Windows.Thickness(12, 4, 12, 6)
    $hdrBdr.Margin  = New-Object Windows.Thickness(0, 0, 0, 2)
    $hg = New-Object Windows.Controls.Grid
    foreach ($colW in @("16", "1*", "90", "90", "80")) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        if ($colW -eq "1*") {
            $cd.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
        } else {
            $cd.Width = [Windows.GridLength]::new([double]$colW)
        }
        $hg.ColumnDefinitions.Add($cd)
    }
    $hdrLabels = @("", "Metrica", "Antes", "Despues", "Delta")
    for ($ci = 0; $ci -lt $hdrLabels.Count; $ci++) {
        $ht = New-Object Windows.Controls.TextBlock
        $ht.Text       = $hdrLabels[$ci]
        $ht.FontSize   = 10
        $ht.FontWeight = [Windows.FontWeights]::SemiBold
        $ht.Foreground = New-Brush "#555555"
        $ht.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $ht.HorizontalAlignment = if ($ci -ge 2) {
            [Windows.HorizontalAlignment]::Center
        } else {
            [Windows.HorizontalAlignment]::Left
        }
        [Windows.Controls.Grid]::SetColumn($ht, $ci)
        $hg.Children.Add($ht) | Out-Null
    }
    $hdrBdr.Child = $hg
    $spRows.Children.Add($hdrBdr) | Out-Null

    # Filas de metricas del snapshot
    $rowIdx = 0
    if ($null -ne $compare -and $compare.Count -gt 0) {
        foreach ($r in $compare) {
            $bef = $r.Before
            $aft = $r.After
            if ($r.Label -match "MB") {
                $bef = "$($r.Before) MB"; $aft = "$($r.After) MB"
            } elseif ($r.Label -match "\(%)") {
                $bef = "$($r.Before)%"; $aft = "$($r.After)%"
            }
            $ctrl = & $mkRow $r.Label $bef $aft $r.Delta $r.Status ($rowIdx % 2 -eq 1)
            $spRows.Children.Add($ctrl) | Out-Null
            $rowIdx++
        }
    }

    # Fila extra: MB liberados (de $script:freed, no del snapshot)
    $freedStatus = if ($freed -gt 0) { "better" } else { "neutral" }
    $freedCtrl   = & $mkRow "MB liberados" "0 MB" "$freed MB" $freed $freedStatus ($rowIdx % 2 -eq 1)
    $spRows.Children.Add($freedCtrl) | Out-Null

    # Eventos de botones
    $script:compareResult = "later"
    $btnRestart.Add_Click({ $script:compareResult = "restart"; $dialog.Close() })
    $btnLater.Add_Click(  { $script:compareResult = "later";   $dialog.Close() })
    $btnViewLog.Add_Click({ $script:compareResult = "log";     $dialog.Close() })

    $dialog.Owner = $window
    $dialog.ShowDialog() | Out-Null

    return $script:compareResult
}

# ============================================================
# MODULO 11A - CAPTURA DE ESTADO DEL SISTEMA
# ============================================================

# ------------------------------------------------------------
# Get-BootTimeSec  (F0.3)
# Lee el ultimo evento ID 100 del log de rendimiento de arranque
# y devuelve el tiempo de arranque en segundos.
# Devuelve -1 si el log no esta disponible o el evento no existe.
# ------------------------------------------------------------
function Get-BootTimeSec {
    try {
        $ev = Get-WinEvent -LogName "Microsoft-Windows-Diagnostics-Performance/Operational" `
                           -FilterXPath "Event[System[EventID=100]]" `
                           -MaxEvents 1 -EA Stop
        if ($ev) {
            $xml  = [xml]$ev.ToXml()
            $node = $xml.Event.EventData.Data | Where-Object { $_.Name -eq "BootTime" }
            if ($node) { return [int]([int]$node.'#text' / 1000) }
        }
    } catch {}
    return -1
}

# ------------------------------------------------------------
# Get-IdleRAMMB  (F0.3)
# Devuelve la RAM libre actual en MB.
# ------------------------------------------------------------
function Get-IdleRAMMB {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -EA Stop
        return [Math]::Round($os.FreePhysicalMemory / 1024, 0)
    } catch {}
    return 0
}

# ------------------------------------------------------------
# Get-ProcessCount  (F0.3)
# Devuelve el numero de procesos activos.
# ------------------------------------------------------------
function Get-ProcessCount {
    try { return (Get-Process).Count } catch {}
    return 0
}

# ------------------------------------------------------------
# Get-SystemSnapshot
# Captura el estado actual del sistema en un objeto.
# Retorna: Timestamp, CPUIdle (%), RAMFreeMB, SvcCount,
#          Score, ProcCount, DiskFreeMB, BootTimeSec.
# El parametro Score permite reusar el valor ya calculado;
# si se omite (o es -1) lo calcula internamente.
# ------------------------------------------------------------
function Get-SystemSnapshot {
    param([int]$Score = -1)

    $cpuIdle    = 0
    $ramFreeMB  = 0
    $svcCount   = 0
    $procCount  = 0
    $diskFreeMB = 0
    $bootSec    = -1

    try {
        $load    = [Math]::Round(
            (Get-CimInstance -ClassName Win32_Processor |
             Measure-Object -Property LoadPercentage -Average).Average, 0)
        $cpuIdle = 100 - $load
    } catch {}

    try {
        $os        = Get-CimInstance -ClassName Win32_OperatingSystem -EA Stop
        $ramFreeMB = [Math]::Round($os.FreePhysicalMemory / 1024, 0)
    } catch {}

    try { $svcCount  = (Get-Service | Where-Object { $_.Status -eq 'Running' }).Count } catch {}
    try { $procCount = Get-ProcessCount } catch {}
    try { $bootSec   = Get-BootTimeSec  } catch {}

    try {
        $dl      = $SYSDRIVE -replace ':', ''
        $drv     = Get-PSDrive -Name $dl -EA Stop
        $diskFreeMB = [Math]::Round($drv.Free / 1MB, 0)
    } catch {
        try {
            $vol     = Get-CimInstance -ClassName Win32_LogicalDisk `
                           -Filter "DeviceID='$SYSDRIVE'" -EA Stop
            $diskFreeMB = [Math]::Round($vol.FreeSpace / 1MB, 0)
        } catch {}
    }

    if ($Score -lt 0) {
        try { $Score = (Get-SystemScore).Score } catch { $Score = 0 }
    }

    return [PSCustomObject]@{
        Timestamp   = Get-Date
        CPUIdle     = $cpuIdle
        RAMFreeMB   = $ramFreeMB
        SvcCount    = $svcCount
        Score       = $Score
        ProcCount   = $procCount
        DiskFreeMB  = $diskFreeMB
        BootTimeSec = $bootSec
    }
}

# ------------------------------------------------------------
# Compare-Snapshots
# Recibe dos snapshots (Before/After) y devuelve un array de
# objetos con Label, Before, After, Delta, HigherBetter, Status.
# Status: "better" / "neutral" / "worse"
# ------------------------------------------------------------
function Compare-Snapshots {
    param(
        [PSCustomObject]$Before,
        [PSCustomObject]$After
    )

    if (-not $Before -or -not $After) { return @() }

    $rows = @(
        [PSCustomObject]@{ Label = "Score de salud";          Before = $Before.Score;       After = $After.Score;       HigherBetter = $true  },
        [PSCustomObject]@{ Label = "CPU libre (%)";           Before = $Before.CPUIdle;     After = $After.CPUIdle;     HigherBetter = $true  },
        [PSCustomObject]@{ Label = "RAM disponible (MB)";     Before = $Before.RAMFreeMB;   After = $After.RAMFreeMB;   HigherBetter = $true  },
        [PSCustomObject]@{ Label = "Disco libre (MB)";        Before = $Before.DiskFreeMB;  After = $After.DiskFreeMB;  HigherBetter = $true  },
        [PSCustomObject]@{ Label = "Servicios activos";       Before = $Before.SvcCount;    After = $After.SvcCount;    HigherBetter = $false },
        [PSCustomObject]@{ Label = "Procesos activos";        Before = $Before.ProcCount;   After = $After.ProcCount;   HigherBetter = $false },
        [PSCustomObject]@{ Label = "Tiempo de arranque (s)";  Before = $Before.BootTimeSec; After = $After.BootTimeSec; HigherBetter = $false }
    )

    foreach ($row in $rows) {
        $delta  = $row.After - $row.Before
        $status = "neutral"
        if ($delta -ne 0) {
            $improved = ($row.HigherBetter -and $delta -gt 0) -or
                        (-not $row.HigherBetter -and $delta -lt 0)
            $status   = if ($improved) { "better" } else { "worse" }
        }
        $row | Add-Member -NotePropertyName Delta  -NotePropertyValue $delta  -Force
        $row | Add-Member -NotePropertyName Status -NotePropertyValue $status -Force
    }

    return $rows
}

# ============================================================
# MODULO 12A - MOTOR DE HARDWARE ID Y LICENCIA
# ============================================================

# Clave publica RSA-2048. La privada la tiene solo el emisor (Gen-License.ps1).
$script:LICENSE_PUBLIC_KEY_XML = '<RSAKeyValue><Modulus>1i89Gsv9L78TshLJGAhCSlvzoCKa2t5zk18kpC4gvzENP0yn6K8TLhCCRTaLAIO/ivRIpPX6UBPvkx1DAft+CqOXBc7L+hycDNIp7NYvebBoVCIFhwfLvjQloAniRIRe4bonEJffJul1y5jKUeErjSP3+PUgnPBO4mA2OfLcqFRyuLKllAuLsAdNE8j9ZyRJUFhQFnGnaANN8vVow9zA8AK+dWTO2s2k8WG32v3idxjlIqksnOZeqqGkXldyGA4z9UnLEr1PfEzItZoaic2xqPYEPB390ynfYXvaHHy2sV0U88rfarh4K2mRsBlQP/kjtXG7uxPH2wvYj0paslBE5Q==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
$script:LICENSE_PATH      = "$env:USERPROFILE\.OptimizarPC\license.key"
$script:TECH_LICENSE_PATH = "$env:USERPROFILE\.OptimizarPC\tech_license.key"

# ------------------------------------------------------------
# Get-HardwareID
# Combina ProcessorId + BIOS SerialNumber, aplica SHA256
# y retorna los primeros 16 caracteres hex en mayusculas.
# Fallback: MachineName + OS SerialNumber si los valores CIM
# estan vacios (maquinas virtuales, hardware sin serial).
# ------------------------------------------------------------
function Get-HardwareID {
    $procId     = ""
    $biosSerial = ""
    try { $procId     = [string](Get-CimInstance -ClassName Win32_Processor `
                            | Select-Object -First 1).ProcessorId } catch {}
    try { $biosSerial = [string](Get-CimInstance -ClassName Win32_BIOS `
                            -EA Stop).SerialNumber }                 catch {}

    $raw = ($procId + $biosSerial).Trim()
    if ($raw.Length -lt 4) {
        try {
            $osSerial = [string](Get-CimInstance -ClassName Win32_OperatingSystem `
                            -EA Stop).SerialNumber
            $raw = [System.Environment]::MachineName + $osSerial
        } catch {}
    }

    $sha  = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($raw))
    $sha.Dispose()
    $hex  = [System.BitConverter]::ToString($hash).Replace("-", "")
    return $hex.Substring(0, 16).ToUpper()
}

# ------------------------------------------------------------
# Test-LicenseSignature (F2.3)
# Verifica que SignatureBase64 sea una firma RSA-2048/SHA256
# valida sobre Message usando la clave publica embebida.
# Retorna $true si la firma es correcta.
# ------------------------------------------------------------
function Test-LicenseSignature {
    param([string]$Message, [string]$SignatureBase64)
    try {
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.FromXmlString($script:LICENSE_PUBLIC_KEY_XML)
        $sha    = [System.Security.Cryptography.SHA256]::Create()
        $hash   = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Message))
        $sha.Dispose()
        $sig    = [System.Convert]::FromBase64String($SignatureBase64)
        $result = $rsa.VerifyHash($hash, "SHA256", $sig)
        $rsa.Dispose()
        return $result
    } catch { return $false }
}

# ------------------------------------------------------------
# Test-LicenseKey (F2.3)
# Valida que Key sea una firma RSA Base64 sobre
# "WINBOOST-PRO-<HWID>" con la clave publica embebida.
# Retorna $true si la firma es correcta para este hardware.
# ------------------------------------------------------------
function Test-LicenseKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    try { [System.Convert]::FromBase64String($Key) | Out-Null } catch { return $false }
    try {
        $hwid = Get-HardwareID
        return (Test-LicenseSignature -Message "WINBOOST-PRO-$hwid" -SignatureBase64 $Key)
    } catch { return $false }
}

# ------------------------------------------------------------
# Test-TechLicenseKey (F2.3)
# Valida que Key empiece con TECH- y que la parte Base64
# sea una firma RSA sobre "WINBOOST-TECH" (sin hardware ID).
# Retorna $true si la firma es correcta.
# ------------------------------------------------------------
function Test-TechLicenseKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    if ($Key -notmatch '^TECH-') { return $false }
    $sig = $Key.Substring(5)
    try { [System.Convert]::FromBase64String($sig) | Out-Null } catch { return $false }
    try {
        return (Test-LicenseSignature -Message "WINBOOST-TECH" -SignatureBase64 $sig)
    } catch { return $false }
}

# ------------------------------------------------------------
# Get-LicenseStatus
# Lee license.key (Pro) y tech_license.key (Tech) y valida.
# Retorna: IsActivated (bool), HardwareID (string),
#          Tier (string: "free"/"pro"/"tech"), ExpiryDate.
# ------------------------------------------------------------
function Get-LicenseStatus {
    $hwid = ""
    try { $hwid = Get-HardwareID } catch {}

    $status = [PSCustomObject]@{
        IsActivated = $false
        HardwareID  = $hwid
        Tier        = "free"
        ExpiryDate  = $null
    }

    # Comprobar Tech primero (mas permisivo)
    if (Test-Path $script:TECH_LICENSE_PATH) {
        try {
            $stored = (Get-Content $script:TECH_LICENSE_PATH -Raw -EA Stop).Trim()
            if (Test-TechLicenseKey -Key "TECH-$stored") {
                $status.IsActivated = $true
                $status.Tier        = "tech"
                return $status
            }
        } catch {}
    }

    # Comprobar Pro (hardware-bound)
    if (Test-Path $script:LICENSE_PATH) {
        try {
            $stored = (Get-Content $script:LICENSE_PATH -Raw -EA Stop).Trim()
            if (Test-LicenseKey -Key $stored) {
                $status.IsActivated = $true
                $status.Tier        = "pro"
                return $status
            }
        } catch {}
    }

    return $status
}

# ============================================================
# MODULO 12B - MODO FREE VS PRO
# ============================================================

# Setear al arrancar basandose en la licencia guardada
$script:_initLic        = Get-LicenseStatus
$script:IS_PRO          = $script:_initLic.IsActivated
$script:IS_TECH         = ($script:_initLic.Tier -eq "tech")  # F2.16: tier Tecnico multi-PC
$script:IS_TRIAL        = $false
$script:TRIAL_DAYS_LEFT = 0

# ------------------------------------------------------------
# Test-TrialStatus (F0.2)
# Evalua el estado del trial y ajusta $script:IS_PRO,
# $script:IS_TRIAL y $script:TRIAL_DAYS_LEFT.
# Llaman a Save-Settings si el estado cambia.
# Debe llamarse despues de Load-Settings.
# ------------------------------------------------------------
function Test-TrialStatus {
    if ((Get-LicenseStatus).IsActivated) {
        $script:IS_PRO          = $true
        $script:IS_TRIAL        = $false
        $script:TRIAL_DAYS_LEFT = 0
        return
    }

    $today = Get-Date

    if ([string]::IsNullOrEmpty($script:settings.TrialStartDate)) {
        $script:settings.TrialStartDate = $today.ToString("yyyy-MM-dd")
        $script:settings.TrialExpired   = $false
        Save-Settings
        $script:IS_PRO          = $true
        $script:IS_TRIAL        = $true
        $script:TRIAL_DAYS_LEFT = 14
    } else {
        try {
            $startDate = [DateTime]::ParseExact(
                $script:settings.TrialStartDate, "yyyy-MM-dd",
                [System.Globalization.CultureInfo]::InvariantCulture)
            $elapsed  = [int]($today - $startDate).TotalDays
            $daysLeft = 14 - $elapsed
            if ($elapsed -gt 14) {
                $script:IS_PRO          = $false
                $script:IS_TRIAL        = $false
                $script:TRIAL_DAYS_LEFT = 0
                if (-not $script:settings.TrialExpired) {
                    $script:settings.TrialExpired = $true
                    Save-Settings
                }
            } else {
                $script:IS_PRO          = $true
                $script:IS_TRIAL        = $true
                $script:TRIAL_DAYS_LEFT = [math]::Max(1, $daysLeft)
            }
        } catch {
            $script:settings.TrialStartDate = $today.ToString("yyyy-MM-dd")
            $script:settings.TrialExpired   = $false
            Save-Settings
            $script:IS_PRO          = $true
            $script:IS_TRIAL        = $true
            $script:TRIAL_DAYS_LEFT = 14
        }
    }
}

# ------------------------------------------------------------
# Update-TrialBanner (F0.2)
# Muestra u oculta el banner de trial en el footer de Optimizar.
# ------------------------------------------------------------
function Update-TrialBanner {
    try {
        if ($script:IS_PRO -and $script:IS_TRIAL) {
            $d = $script:TRIAL_DAYS_LEFT
            $lblTrialText.Text = if ($d -eq 1) {
                "Periodo de prueba: queda 1 dia. Activa Pro para no perder el acceso."
            } else {
                "Periodo de prueba activo. Quedan $d dias."
            }
            $lblTrialText.Foreground    = New-Brush "#F59E0B"
            $bannerTrial.Background     = New-Brush "#1A1200"
            $bannerTrial.BorderBrush    = New-Brush "#3A2800"
            $btnTrialUpgrade.Foreground = New-Brush "#F59E0B"
            $btnTrialUpgrade.BorderBrush = New-Brush "#F59E0B"
            $bannerTrial.Visibility = "Visible"
        } elseif (-not $script:IS_PRO -and $script:settings.TrialExpired -eq $true) {
            $lblTrialText.Text = "El periodo de prueba vencio. Activa Pro para seguir usando las funciones avanzadas."
            $lblTrialText.Foreground    = New-Brush "#EF4444"
            $bannerTrial.Background     = New-Brush "#1A0A0A"
            $bannerTrial.BorderBrush    = New-Brush "#3A1515"
            $btnTrialUpgrade.Foreground = New-Brush "#EF4444"
            $btnTrialUpgrade.BorderBrush = New-Brush "#EF4444"
            $bannerTrial.Visibility = "Visible"
        } else {
            $bannerTrial.Visibility = "Collapsed"
        }
        Flush-UI
    } catch {}
}

# ------------------------------------------------------------
# Lock-ProFeature
# Verifica si el usuario tiene licencia Pro o trial activo.
# Retorna $true (bloquea) si no tiene acceso; $false si puede continuar.
# ------------------------------------------------------------
function Lock-ProFeature {
    param([string]$FeatureName = "")

    if ($script:IS_PRO) { return $false }

    $base = if ($FeatureName) { $FeatureName } else { "Esta funcion" }
    if ($script:settings.TrialExpired -eq $true) {
        $msg = "$base requiere licencia Pro.`n`nTu periodo de prueba ha vencido. Activa tu licencia en el tab Licencia."
    } else {
        $msg = "$base requiere licencia Pro.`n`nActiva tu licencia para desbloquear todas las funciones de WinBoost."
    }

    [Windows.MessageBox]::Show(
        $msg,
        "WinBoost - Funcion Pro",
        [Windows.MessageBoxButton]::OK,
        [Windows.MessageBoxImage]::Information) | Out-Null

    return $true
}

# ============================================================
# MODULO 12C - UI DE ACTIVACION
# ============================================================

$script:LICENSE_BUY_URL = ""

$script:brLicFree = New-Brush "#888888"
$script:brLicPro  = New-Brush "#F59E0B"
$script:brLicOk   = New-Brush "#22C55E"
$script:brLicErr  = New-Brush "#EF4444"

function Update-LicenseBadge {
    if ($script:IS_TECH) {
        $badgeLicenseFree.Visibility = "Collapsed"
        $badgeLicensePro.Visibility  = "Visible"
        $lblLicenseStatus.Text       = "WinBoost TECNICO activado — multi-PC"
        $lblLicenseStatus.Foreground = $script:brLicOk
    } elseif ($script:IS_PRO -and -not $script:IS_TRIAL) {
        $badgeLicenseFree.Visibility = "Collapsed"
        $badgeLicensePro.Visibility  = "Visible"
        $lblLicenseStatus.Text       = "WinBoost PRO activado"
        $lblLicenseStatus.Foreground = $script:brLicPro
    } elseif ($script:IS_PRO -and $script:IS_TRIAL) {
        $badgeLicenseFree.Visibility = "Collapsed"
        $badgeLicensePro.Visibility  = "Visible"
        $lblLicenseStatus.Text       = "Periodo de prueba activo ($($script:TRIAL_DAYS_LEFT) dias restantes)"
        $lblLicenseStatus.Foreground = $script:brLicPro
    } else {
        $badgeLicenseFree.Visibility = "Visible"
        $badgeLicensePro.Visibility  = "Collapsed"
        if ($script:settings.TrialExpired -eq $true) {
            $lblLicenseStatus.Text       = "Periodo de prueba vencido"
            $lblLicenseStatus.Foreground = $script:brLicErr
        } else {
            $lblLicenseStatus.Text       = "Version gratuita activa"
            $lblLicenseStatus.Foreground = $script:brLicFree
        }
    }
    Flush-UI
}

$lblHardwareID.Text = Get-HardwareID
Update-LicenseBadge

$btnTrialUpgrade.Add_Click({ Set-ActiveNav 8 })

$btnCopyHWID.Add_Click({
    [System.Windows.Clipboard]::SetText($lblHardwareID.Text)
    $btnCopyHWID.Content = "Copiado"
    Flush-UI
    $script:hwidCopyTimer = New-Object Windows.Threading.DispatcherTimer
    $script:hwidCopyTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $script:hwidCopyTimer.Add_Tick({
        $btnCopyHWID.Content = "Copiar"
        $script:hwidCopyTimer.Stop()
        Flush-UI
    })
    $script:hwidCopyTimer.Start()
})

$btnActivateLicense.Add_Click({
    $key = $txtLicenseKey.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        $lblActivationResult.Text       = "Pega tu clave de activacion."
        $lblActivationResult.Foreground = $script:brLicPro
        Flush-UI
        return
    }
    # --- Tier Tecnico (TECH-<Base64>, multi-PC) ---
    if ($key -match '^TECH-') {
        if (Test-TechLicenseKey -Key $key) {
            $dir = Split-Path $script:TECH_LICENSE_PATH
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $key.Substring(5) | Set-Content -Path $script:TECH_LICENSE_PATH -Encoding UTF8
            $script:IS_PRO  = $true
            $script:IS_TECH = $true
            Update-LicenseBadge
            try { if($script:techNameRow){ $script:techNameRow.Visibility = "Visible" } } catch {}
            $lblActivationResult.Text       = "Licencia Tecnico activada. Valida en cualquier equipo."
            $lblActivationResult.Foreground = $script:brLicOk
        } else {
            $lblActivationResult.Text       = "Clave Tecnico invalida. Asegurate de pegarla exactamente como la recibiste."
            $lblActivationResult.Foreground = $script:brLicErr
        }
        Flush-UI
        return
    }
    # --- Tier Pro (firma RSA Base64, hardware-bound) ---
    if (Test-LicenseKey -Key $key) {
        $dir = Split-Path $script:LICENSE_PATH
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $key | Set-Content -Path $script:LICENSE_PATH -Encoding UTF8
        $script:IS_PRO  = $true
        $script:IS_TECH = $false
        Update-LicenseBadge
        $lblActivationResult.Text       = "Activacion exitosa. Bienvenido a WinBoost PRO."
        $lblActivationResult.Foreground = $script:brLicOk
    } else {
        $lblActivationResult.Text       = "Clave invalida o generada para otro equipo. Pega la clave exactamente como la recibiste."
        $lblActivationResult.Foreground = $script:brLicErr
    }
    Flush-UI
})

$btnGetLicense.Add_Click({
    if ($script:LICENSE_BUY_URL -ne "") {
        Start-Process $script:LICENSE_BUY_URL
    } else {
        [Windows.MessageBox]::Show(
            "Contacta al soporte para obtener tu licencia Pro.",
            "WinBoost PRO",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
    }
})

# ============================================================
# MODULO 15A - DETECCION DE PRIMER USO
# ============================================================

$script:isFirstRun = $false

# ------------------------------------------------------------
# Test-FirstRun
# Lee profile.json y determina si es la primera ejecucion.
# Reglas:
#   - firstRun ausente o true  -> primera vez  -> retorna $true
#   - firstRun == false        -> ya completo   -> retorna $false
# Efecto secundario: escribe firstRun=true la primera vez para
# que reinicios sin completar el onboarding lo muestren de nuevo.
# ------------------------------------------------------------
function Test-FirstRun {
    $dir = Split-Path $PROFILE_PATH
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path $PROFILE_PATH) {
        try {
            $json = Get-Content $PROFILE_PATH -Raw -EA Stop | ConvertFrom-Json
            if ($json.firstRun -eq $false) { return $false }
        } catch {}
    }

    # Primera ejecucion o onboarding no completado: marcar firstRun=true
    try {
        $obj = @{}
        if (Test-Path $PROFILE_PATH) {
            try {
                $raw = Get-Content $PROFILE_PATH -Raw -EA SilentlyContinue | ConvertFrom-Json
                if ($raw) { $raw.PSObject.Properties | ForEach-Object { $obj[$_.Name] = $_.Value } }
            } catch {}
        }
        $obj["firstRun"] = $true
        $obj | ConvertTo-Json | Out-File $PROFILE_PATH -Encoding UTF8 -Force
    } catch {}

    return $true
}

# ------------------------------------------------------------
# Set-FirstRunComplete
# Escribe firstRun=false en profile.json preservando todos los
# demas campos. Llamar al completar el onboarding (Modulo 15B).
# ------------------------------------------------------------
function Set-FirstRunComplete {
    $script:isFirstRun = $false
    try {
        $dir = Split-Path $PROFILE_PATH
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $obj = @{}
        if (Test-Path $PROFILE_PATH) {
            try {
                $raw = Get-Content $PROFILE_PATH -Raw -EA SilentlyContinue | ConvertFrom-Json
                if ($raw) { $raw.PSObject.Properties | ForEach-Object { $obj[$_.Name] = $_.Value } }
            } catch {}
        }
        $obj["firstRun"] = $false
        $obj | ConvertTo-Json | Out-File $PROFILE_PATH -Encoding UTF8 -Force
    } catch {}
}

# ============================================================
# MODULO 15B - VENTANA DE BIENVENIDA (ONBOARDING)
# ============================================================

$script:onboardDlg      = $null
$script:onboardStep     = 0
$script:onboardPreset   = "gaming"
$script:onboardCanClose = $false
$script:obdPanels = @("step0","step1","step2","step3")
$script:obdDots   = @("dot0","dot1","dot2","dot3")
$script:obdTitles = @(
    "Bienvenido a WinBoost",
    "Tu salud del sistema",
    "Perfil de optimizacion",
    "Todo listo"
)
$script:obdSubs = @(
    "Revisamos tu hardware en 4 pasos rapidos.",
    "Analizamos el estado actual de tu PC.",
    "Elegimos la configuracion ideal para tu equipo.",
    "WinBoost configurado y listo para usar."
)

# Actualiza visibilidad de pasos, dots y texto de botones
$script:obdUpdateStep = {
    $s = $script:onboardStep
    $d = $script:onboardDlg
    for ($i = 0; $i -lt 4; $i++) {
        $d.FindName($script:obdPanels[$i]).Visibility = if ($i -eq $s) { "Visible" } else { "Collapsed" }
        $dotColor = if ($i -le $s) { "#00C8FF" } else { "#2A2A2A" }
        $d.FindName($script:obdDots[$i]).Background = New-Brush $dotColor
    }
    $d.FindName("lblObdStepTitle").Text = $script:obdTitles[$s]
    $d.FindName("lblObdStepSub").Text   = $script:obdSubs[$s]
    $d.FindName("btnObdBack").IsEnabled = ($s -gt 0)
    $d.FindName("btnObdNext").Content   = if ($s -eq 3) { "Empezar" } else { "Siguiente" }
}

# Actualiza highlight de tarjetas y resumen del paso 3
$script:obdUpdateCards = {
    $p   = $script:onboardPreset
    $d   = $script:onboardDlg
    $sel = New-Brush "#00C8FF"
    $off = New-Brush "#2A2A2A"
    $d.FindName("cardGaming").BorderBrush = if ($p -eq "gaming") { $sel } else { $off }
    $d.FindName("cardProd").BorderBrush   = if ($p -eq "prod")   { $sel } else { $off }
    $d.FindName("cardSafe").BorderBrush   = if ($p -eq "safe")   { $sel } else { $off }
    $presetName = switch ($p) { "gaming" { "Gaming" } "prod" { "Productividad" } default { "Conservador" } }
    $d.FindName("lblObdPresetChosen").Text = $presetName
}

# ------------------------------------------------------------
# Show-OnboardingDialog
# Wizard de 4 pasos mostrado solo en la primera ejecucion.
# Bloquea X hasta completar paso 4. Al finalizar aplica el
# preset elegido y llama Set-FirstRunComplete.
# ------------------------------------------------------------
function Show-OnboardingDialog {
    $script:onboardStep     = 0
    $script:onboardCanClose = $false
    $recPreset = if ($IS_LAPTOP) { "prod" } elseif ($totalRAM -ge 8) { "gaming" } else { "safe" }
    $script:onboardPreset = $recPreset

    $scoreVal = 0
    try { $sv = [string]$lblScoreValue.Text; if ($sv -match '^\d+$') { $scoreVal = [int]$sv } } catch {}

    $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinBoost - Bienvenido"
        Width="600" Height="540"
        WindowStartupLocation="CenterOwner"
        Background="#0D0D0D" FontFamily="Segoe UI"
        ResizeMode="NoResize" ShowInTaskbar="False">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#161616" BorderBrush="#2A2A2A"
            BorderThickness="0,0,0,1" Padding="28,18">
      <StackPanel>
        <TextBlock x:Name="lblObdStepTitle" Text="Bienvenido a WinBoost"
                   FontSize="18" FontWeight="SemiBold" Foreground="#EEEEEE"/>
        <TextBlock x:Name="lblObdStepSub" Text=""
                   FontSize="12" Foreground="#555555" Margin="0,4,0,0"/>
        <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
          <Border x:Name="dot0" Width="32" Height="6" CornerRadius="3" Background="#00C8FF" Margin="0,0,7,0"/>
          <Border x:Name="dot1" Width="32" Height="6" CornerRadius="3" Background="#2A2A2A" Margin="0,0,7,0"/>
          <Border x:Name="dot2" Width="32" Height="6" CornerRadius="3" Background="#2A2A2A" Margin="0,0,7,0"/>
          <Border x:Name="dot3" Width="32" Height="6" CornerRadius="3" Background="#2A2A2A"/>
        </StackPanel>
      </StackPanel>
    </Border>
    <Grid Grid.Row="1">
      <Border x:Name="step0" Visibility="Visible" Padding="28,20">
        <StackPanel>
          <TextBlock Text="HARDWARE DETECTADO" FontSize="10" FontWeight="SemiBold"
                     Foreground="#555555" Margin="0,0,0,14"/>
          <Border Background="#161616" CornerRadius="8" BorderBrush="#2A2A2A"
                  BorderThickness="1" Padding="20,14">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="90"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Grid.Column="0" Text="CPU"    FontSize="12" Foreground="#555555" Margin="0,7"/>
              <TextBlock Grid.Row="0" Grid.Column="1" x:Name="lblObdCPU"  FontSize="12" Foreground="#CCCCCC" Margin="0,7" TextTrimming="CharacterEllipsis"/>
              <TextBlock Grid.Row="1" Grid.Column="0" Text="GPU"    FontSize="12" Foreground="#555555" Margin="0,7"/>
              <TextBlock Grid.Row="1" Grid.Column="1" x:Name="lblObdGPU"  FontSize="12" Foreground="#CCCCCC" Margin="0,7" TextTrimming="CharacterEllipsis"/>
              <TextBlock Grid.Row="2" Grid.Column="0" Text="RAM"    FontSize="12" Foreground="#555555" Margin="0,7"/>
              <TextBlock Grid.Row="2" Grid.Column="1" x:Name="lblObdRAM"  FontSize="12" Foreground="#CCCCCC" Margin="0,7"/>
              <TextBlock Grid.Row="3" Grid.Column="0" Text="Disco"  FontSize="12" Foreground="#555555" Margin="0,7"/>
              <TextBlock Grid.Row="3" Grid.Column="1" x:Name="lblObdDisk" FontSize="12" Foreground="#CCCCCC" Margin="0,7"/>
              <TextBlock Grid.Row="4" Grid.Column="0" Text="Equipo" FontSize="12" Foreground="#555555" Margin="0,7"/>
              <TextBlock Grid.Row="4" Grid.Column="1" x:Name="lblObdType" FontSize="12" Foreground="#CCCCCC" Margin="0,7"/>
            </Grid>
          </Border>
        </StackPanel>
      </Border>
      <Border x:Name="step1" Visibility="Collapsed" Padding="28,20">
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
          <TextBlock Text="PUNTUACION DE SALUD ACTUAL" FontSize="10" FontWeight="SemiBold"
                     Foreground="#555555" HorizontalAlignment="Center" Margin="0,0,0,24"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
            <TextBlock x:Name="lblObdScore" Text="--" FontSize="72" FontWeight="Bold"
                       Foreground="#00C8FF" VerticalAlignment="Bottom"/>
            <TextBlock Text="%" FontSize="28" Foreground="#555555"
                       VerticalAlignment="Bottom" Margin="4,0,0,10"/>
          </StackPanel>
          <TextBlock x:Name="lblObdScoreLabel" Text="Calculando..."
                     FontSize="14" Foreground="#888888"
                     HorizontalAlignment="Center" Margin="0,14,0,0"/>
          <Border Background="#161616" CornerRadius="8" Padding="18,14" Margin="0,28,0,0"
                  BorderBrush="#2A2A2A" BorderThickness="1">
            <TextBlock FontSize="11" Foreground="#555555" TextWrapping="Wrap" TextAlignment="Center"
              Text="WinBoost analiza 19 aspectos de tu PC: rendimiento, privacidad, red y servicios. Una puntuacion mas alta indica un sistema mas optimizado."/>
          </Border>
        </StackPanel>
      </Border>
      <Border x:Name="step2" Visibility="Collapsed" Padding="28,20">
        <StackPanel>
          <TextBlock Text="SELECCIONA TU PERFIL DE USO" FontSize="10" FontWeight="SemiBold"
                     Foreground="#555555" Margin="0,0,0,6"/>
          <TextBlock Text="Podras cambiarlo en cualquier momento desde la pantalla principal."
                     FontSize="11" Foreground="#444444" Margin="0,0,0,20"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border x:Name="cardGaming" Grid.Column="0" Background="#161616"
                    CornerRadius="8" BorderBrush="#2A2A2A" BorderThickness="2"
                    Padding="14,18" Cursor="Hand">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="&#x26A1;" FontFamily="Segoe UI Symbol" FontSize="32"
                           HorizontalAlignment="Center" Foreground="#00C8FF" Margin="0,0,0,10"/>
                <TextBlock Text="Gaming" FontSize="13" FontWeight="SemiBold"
                           Foreground="#CCCCCC" HorizontalAlignment="Center"/>
                <TextBlock Text="Maximo rendimiento" FontSize="10" Foreground="#555555"
                           HorizontalAlignment="Center" Margin="0,4,0,0"
                           TextWrapping="Wrap" TextAlignment="Center"/>
                <Border x:Name="badgeRecGaming" Background="#0D1520" CornerRadius="4"
                        Padding="6,2" Margin="0,10,0,0" Visibility="Collapsed"
                        HorizontalAlignment="Center">
                  <TextBlock Text="Recomendado" FontSize="9" Foreground="#00C8FF"/>
                </Border>
              </StackPanel>
            </Border>
            <Border x:Name="cardProd" Grid.Column="2" Background="#161616"
                    CornerRadius="8" BorderBrush="#2A2A2A" BorderThickness="2"
                    Padding="14,18" Cursor="Hand">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="&#x2699;" FontFamily="Segoe UI Symbol" FontSize="32"
                           HorizontalAlignment="Center" Foreground="#F59E0B" Margin="0,0,0,10"/>
                <TextBlock Text="Productividad" FontSize="13" FontWeight="SemiBold"
                           Foreground="#CCCCCC" HorizontalAlignment="Center"/>
                <TextBlock Text="Trabajo y uso general" FontSize="10" Foreground="#555555"
                           HorizontalAlignment="Center" Margin="0,4,0,0"
                           TextWrapping="Wrap" TextAlignment="Center"/>
                <Border x:Name="badgeRecProd" Background="#1A1400" CornerRadius="4"
                        Padding="6,2" Margin="0,10,0,0" Visibility="Collapsed"
                        HorizontalAlignment="Center">
                  <TextBlock Text="Recomendado" FontSize="9" Foreground="#F59E0B"/>
                </Border>
              </StackPanel>
            </Border>
            <Border x:Name="cardSafe" Grid.Column="4" Background="#161616"
                    CornerRadius="8" BorderBrush="#2A2A2A" BorderThickness="2"
                    Padding="14,18" Cursor="Hand">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="&#x2713;" FontFamily="Segoe UI Symbol" FontSize="32"
                           HorizontalAlignment="Center" Foreground="#22C55E" Margin="0,0,0,10"/>
                <TextBlock Text="Conservador" FontSize="13" FontWeight="SemiBold"
                           Foreground="#CCCCCC" HorizontalAlignment="Center"/>
                <TextBlock Text="Solo limpieza basica" FontSize="10" Foreground="#555555"
                           HorizontalAlignment="Center" Margin="0,4,0,0"
                           TextWrapping="Wrap" TextAlignment="Center"/>
                <Border x:Name="badgeRecSafe" Background="#0A2A0A" CornerRadius="4"
                        Padding="6,2" Margin="0,10,0,0" Visibility="Collapsed"
                        HorizontalAlignment="Center">
                  <TextBlock Text="Recomendado" FontSize="9" Foreground="#22C55E"/>
                </Border>
              </StackPanel>
            </Border>
          </Grid>
        </StackPanel>
      </Border>
      <Border x:Name="step3" Visibility="Collapsed" Padding="28,20">
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
          <TextBlock Text="&#x2605;" FontFamily="Segoe UI Symbol" FontSize="52"
                     Foreground="#00C8FF" HorizontalAlignment="Center" Margin="0,0,0,16"/>
          <TextBlock Text="Todo listo para optimizar"
                     FontSize="18" FontWeight="SemiBold" Foreground="#EEEEEE"
                     HorizontalAlignment="Center" Margin="0,0,0,10"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,4">
            <TextBlock Text="Perfil configurado: " FontSize="13" Foreground="#555555"
                       VerticalAlignment="Center"/>
            <TextBlock x:Name="lblObdPresetChosen" Text="Gaming" FontSize="13"
                       FontWeight="SemiBold" Foreground="#00C8FF" VerticalAlignment="Center"/>
          </StackPanel>
          <Border Background="#161616" CornerRadius="8" Padding="18,14" Margin="0,24,0,0"
                  BorderBrush="#2A2A2A" BorderThickness="1">
            <TextBlock FontSize="11" Foreground="#555555" TextWrapping="Wrap" TextAlignment="Center"
              Text="Los checkboxes de la pantalla Optimizar se configuraron segun tu perfil. Podes ajustarlos antes de ejecutar."/>
          </Border>
        </StackPanel>
      </Border>
    </Grid>
    <Border Grid.Row="2" Background="#111111" BorderBrush="#2A2A2A"
            BorderThickness="0,1,0,0" Padding="20,14">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="btnObdBack" Content="Anterior" Height="34" Padding="18,0"
                Margin="0,0,8,0" IsEnabled="False" Background="#1E1E1E"
                Foreground="#CCCCCC" BorderBrush="#2A2A2A" BorderThickness="1"
                Cursor="Hand" FontSize="12">
          <Button.Template><ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#2A2A2A"/>
                <Setter Property="BorderBrush" Value="#00C8FF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Background" Value="#111111"/>
                <Setter Property="Foreground" Value="#333333"/>
                <Setter Property="BorderBrush" Value="#1A1A1A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Button.Template>
        </Button>
        <Button x:Name="btnObdNext" Content="Siguiente" Height="34" Padding="20,0"
                Background="#00C8FF" Foreground="#0D0D0D" BorderThickness="0"
                Cursor="Hand" FontSize="12" FontWeight="SemiBold">
          <Button.Template><ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#33D6FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Button.Template>
        </Button>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

    $xmlRdr = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dlgXaml))
    $dlg    = [Windows.Markup.XamlReader]::Load($xmlRdr)
    $xmlRdr.Close()
    $script:onboardDlg = $dlg
    $dlg.Owner = $window

    # Paso 0 - hardware
    $dlg.FindName("lblObdCPU").Text  = $cpuName
    $dlg.FindName("lblObdGPU").Text  = $gpuName
    $dlg.FindName("lblObdRAM").Text  = "$totalRAM GB"
    $dlg.FindName("lblObdDisk").Text = $diskType
    $dlg.FindName("lblObdType").Text = if ($IS_LAPTOP) { "Laptop" } else { "PC Escritorio" }

    # Paso 1 - score
    $scoreColor = if ($scoreVal -ge 80) { "#22C55E" } elseif ($scoreVal -ge 60) { "#F59E0B" } else { "#EF4444" }
    $scoreLabel = if ($scoreVal -ge 80) { "Sistema en buen estado" } elseif ($scoreVal -ge 60) { "Hay margen de mejora" } else { "Optimizacion recomendada" }
    $dlg.FindName("lblObdScore").Text       = [string]$scoreVal
    $dlg.FindName("lblObdScoreLabel").Text  = $scoreLabel
    $dlg.FindName("lblObdScore").Foreground = New-Brush $scoreColor

    # Paso 2 - badge del preset recomendado
    $recBadge = switch ($recPreset) { "gaming" { "badgeRecGaming" } "prod" { "badgeRecProd" } default { "badgeRecSafe" } }
    $dlg.FindName($recBadge).Visibility = "Visible"

    # Render inicial de step y tarjetas
    & $script:obdUpdateStep
    & $script:obdUpdateCards

    # Seleccion de preset
    $dlg.FindName("cardGaming").Add_MouseLeftButtonUp({
        $script:onboardPreset = "gaming"; & $script:obdUpdateCards
    })
    $dlg.FindName("cardProd").Add_MouseLeftButtonUp({
        $script:onboardPreset = "prod";   & $script:obdUpdateCards
    })
    $dlg.FindName("cardSafe").Add_MouseLeftButtonUp({
        $script:onboardPreset = "safe";   & $script:obdUpdateCards
    })

    # Navegacion
    $dlg.FindName("btnObdBack").Add_Click({
        if ($script:onboardStep -gt 0) {
            $script:onboardStep--
            & $script:obdUpdateStep
        }
    })

    $dlg.FindName("btnObdNext").Add_Click({
        if ($script:onboardStep -lt 3) {
            $script:onboardStep++
            & $script:obdUpdateStep
        } else {
            $script:onboardCanClose = $true
            switch ($script:onboardPreset) {
                "gaming" { Apply-Preset $presetGaming }
                "prod"   { Apply-Preset $presetProd }
                default  { Apply-Preset $presetSafe }
            }
            Set-FirstRunComplete
            $script:onboardDlg.Close()
        }
    })

    # Bloquear cierre con X hasta completar
    $dlg.Add_Closing({
        param($s, $e)
        if (-not $script:onboardCanClose) { $e.Cancel = $true }
    })

    $dlg.ShowDialog() | Out-Null
}

# ============================================================
# MODULO 14 - AUTO-UPDATER MEJORADO
# ============================================================

# ------------------------------------------------------------
# Show-ChangelogDialog
# Ventana secundaria con changelog y botones de accion.
# Retorna via $script:changelogResult: "later"|"github"|"download"
# ------------------------------------------------------------
function Show-ChangelogDialog {
    $meta = $script:updateMeta
    if (-not $meta) { return }

    $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Actualizacion disponible"
        Width="520" Height="400"
        WindowStartupLocation="CenterOwner"
        Background="#0D0D0D" FontFamily="Segoe UI"
        ResizeMode="NoResize" ShowInTaskbar="False">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#161616" BorderBrush="#2A2A2A"
            BorderThickness="0,0,0,1" Padding="20,16">
      <StackPanel>
        <TextBlock x:Name="lblUpdateVersion" Text="WinBoost disponible"
                   FontSize="16" FontWeight="SemiBold" Foreground="#00C8FF"/>
        <TextBlock x:Name="lblUpdateCurrentVer" Text=""
                   FontSize="11" Foreground="#555555" Margin="0,4,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="1" Padding="20,14">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <TextBlock x:Name="tbChangelog" Text="" FontSize="12"
                   Foreground="#CCCCCC" TextWrapping="Wrap" LineHeight="20"/>
      </ScrollViewer>
    </Border>
    <Border Grid.Row="2" Background="#111111" BorderBrush="#2A2A2A"
            BorderThickness="0,1,0,0" Padding="16,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="btnUpdateLater" Content="Ahora no" Height="32"
                Padding="14,0" Margin="0,0,8,0" Background="#1E1E1E"
                Foreground="#CCCCCC" BorderBrush="#2A2A2A" BorderThickness="1"
                Cursor="Hand" FontSize="12">
          <Button.Template><ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#2A2A2A"/>
                <Setter Property="BorderBrush" Value="#00C8FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Button.Template>
        </Button>
        <Button x:Name="btnUpdateGitHub" Content="Ver en GitHub" Height="32"
                Padding="14,0" Margin="0,0,8,0" Background="#1E1E1E"
                Foreground="#CCCCCC" BorderBrush="#2A2A2A" BorderThickness="1"
                Cursor="Hand" FontSize="12">
          <Button.Template><ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#2A2A2A"/>
                <Setter Property="BorderBrush" Value="#00C8FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Button.Template>
        </Button>
        <Button x:Name="btnUpdateDownload" Content="Descargar e instalar" Height="32"
                Padding="16,0" Background="#00C8FF" Foreground="#0D0D0D"
                BorderThickness="0" Cursor="Hand" FontSize="12" FontWeight="SemiBold">
          <Button.Template><ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#33D6FF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Background" Value="#2A2A2A"/>
                <Setter Property="Foreground" Value="#555555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Button.Template>
        </Button>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

    $xmlRdr = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dlgXaml))
    $dlg    = [Windows.Markup.XamlReader]::Load($xmlRdr)
    $xmlRdr.Close()

    $dlg.FindName("lblUpdateVersion").Text    = "WinBoost v$($meta.Version) disponible"
    $dlg.FindName("lblUpdateCurrentVer").Text = "Version actual: v$VERSION"
    $dlg.FindName("tbChangelog").Text         = $meta.Changelog

    $btnUpdateDownload = $dlg.FindName("btnUpdateDownload")
    if (-not $meta.DownloadUrl) {
        $btnUpdateDownload.IsEnabled = $false
        $btnUpdateDownload.Content   = "Descarga no disponible"
    }

    $script:changelogResult = "later"
    $script:updateDlg       = $dlg

    $dlg.FindName("btnUpdateLater").Add_Click({
        $script:changelogResult = "later"
        $script:updateDlg.Close()
    })
    $dlg.FindName("btnUpdateGitHub").Add_Click({
        $script:changelogResult = "github"
        if ($script:updateMeta.ReleaseUrl) { Start-Process $script:updateMeta.ReleaseUrl }
        $script:updateDlg.Close()
    })
    $dlg.FindName("btnUpdateDownload").Add_Click({
        $script:changelogResult = "download"
        $script:updateDlg.Close()
    })

    $dlg.Owner = $window
    $dlg.ShowDialog() | Out-Null

    if ($script:changelogResult -eq "download") { Start-UpdateDownload }
}

# ------------------------------------------------------------
# Start-UpdateDownload
# Descarga el archivo usando WebClient async + DispatcherTimer.
# Progreso en la progressBar del footer (tab Optimizar).
# Al completar: verifica SHA256 y llama Apply-Update.
# ------------------------------------------------------------
function Start-UpdateDownload {
    $meta = $script:updateMeta
    if (-not $meta -or -not $meta.DownloadUrl) {
        [Windows.MessageBox]::Show(
            "No hay URL de descarga disponible.`nDescarga manualmente desde GitHub.",
            "WinBoost - Actualizacion",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
        if ($meta -and $meta.ReleaseUrl) { Start-Process $meta.ReleaseUrl }
        return
    }

    $tmpDir = "$env:TEMP\OptimizarPC_update"
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }

    $fileName         = [System.IO.Path]::GetFileName($meta.DownloadUrl)
    if (-not $fileName) { $fileName = "WinBoost_update.exe" }
    $script:dlTmpFile = Join-Path $tmpDir $fileName
    $script:dlDone    = $false
    $script:dlError   = $null

    Set-ActiveNav 0
    Set-Progress 0 "Iniciando descarga de v$($meta.Version)..."
    Flush-UI

    $wc = New-Object System.Net.WebClient
    $wc.Add_DownloadProgressChanged({
        param($s, $e)
        $progressBar.Value = $e.ProgressPercentage
        $lblProgress.Text  = "Descargando v$($script:updateMeta.Version)..."
        $lblPct.Text       = "$($e.ProgressPercentage)%"
    })
    $wc.Add_DownloadFileCompleted({
        param($s, $e)
        $script:dlDone  = $true
        $script:dlError = if ($e.Error) { $e.Error.Message } else { $null }
    })

    try {
        $wc.DownloadFileAsync([Uri]$meta.DownloadUrl, $script:dlTmpFile)
    } catch {
        Set-Progress 0 "Error al iniciar la descarga: $_"
        return
    }

    # DispatcherTimer monitorea la completacion sin bloquear la UI
    $script:dlTimer          = New-Object Windows.Threading.DispatcherTimer
    $script:dlTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:dlTimer.Add_Tick({
        if (-not $script:dlDone) { return }
        $script:dlTimer.Stop()

        if ($script:dlError) {
            Set-Progress 0 "Error en la descarga: $script:dlError"
            return
        }

        Set-Progress 100 "Verificando integridad SHA256..."
        Flush-UI

        $expectedHash = $script:updateMeta.Sha256
        if ($expectedHash) {
            $actualHash = (Get-FileHash $script:dlTmpFile -Algorithm SHA256).Hash.ToUpper()
            if ($actualHash -ne $expectedHash) {
                Set-Progress 0 "Error: hash invalido. El archivo puede estar corrupto."
                return
            }
        }

        Set-Progress 100 "Aplicando actualizacion..."
        Flush-UI
        Apply-Update -NewFile $script:dlTmpFile
    })
    $script:dlTimer.Start()
}

# ------------------------------------------------------------
# Apply-Update
# Crea un script helper que espera al cierre del proceso actual,
# copia el nuevo archivo sobre el actual y relanza la app.
# ------------------------------------------------------------
function Apply-Update {
    param([string]$NewFile)

    $currentExe = ""
    try { $currentExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch {}

    $isExe = ($currentExe -ne "" -and
              $currentExe -notlike "*powershell*" -and
              $currentExe -notlike "*pwsh*" -and
              $currentExe -like "*.exe")

    $target = ""
    if ($isExe) {
        $target = $currentExe
    } elseif ($PSCommandPath) {
        $target = $PSCommandPath
    } else {
        $target = $currentExe
    }

    $procId  = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $swapDir = "$env:TEMP\OptimizarPC_update"
    $swapPs1 = Join-Path $swapDir "do_update.ps1"

    $srcEsc = $NewFile -replace "'","''"
    $dstEsc = $target  -replace "'","''"

    $swapLines = @(
        "`$src  = '$srcEsc'",
        "`$dst  = '$dstEsc'",
        "`$pid_ = $procId",
        "for (`$i = 0; `$i -lt 20; `$i++) {",
        "    if (-not (Get-Process -Id `$pid_ -EA SilentlyContinue)) { break }",
        "    Start-Sleep -Seconds 1",
        "}",
        "Start-Sleep -Seconds 1",
        "try { Copy-Item `$src `$dst -Force -EA Stop } catch {",
        "    `$errMsg = `$_.Exception.Message",
        "    Add-Type -AssemblyName System.Windows.Forms",
        "    [System.Windows.Forms.MessageBox]::Show('Error al aplicar la actualizacion: ' + `$errMsg, 'WinBoost Update', 'OK', 'Error') | Out-Null",
        "    exit 1",
        "}",
        "Start-Process `$dst"
    )
    ($swapLines -join [System.Environment]::NewLine) | Out-File $swapPs1 -Encoding UTF8 -Force

    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$swapPs1`""

    Set-Progress 100 "Reiniciando en un momento..."
    Flush-UI

    $script:applyTimer          = New-Object Windows.Threading.DispatcherTimer
    $script:applyTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
    $script:applyTimer.Add_Tick({
        $script:applyTimer.Stop()
        $window.Close()
    })
    $script:applyTimer.Start()
}

# ============================================================
# MODULO 1.1 - SPLASH SCREEN DE CARGA
# ============================================================
function Show-SplashScreen {
    $splashXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinBoost" Width="400" Height="260"
        WindowStyle="None" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        Background="#0D0D0D">
  <Border Background="#111111" BorderBrush="#1A3A44" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="50"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0" VerticalAlignment="Center" HorizontalAlignment="Center">
        <TextBlock Text="&#x26A1;" FontFamily="Segoe UI Symbol" FontSize="44"
                   HorizontalAlignment="Center" Foreground="#00C8FF"/>
        <TextBlock Text="WinBoost" FontSize="30" FontWeight="Bold" FontFamily="Segoe UI"
                   HorizontalAlignment="Center" Foreground="#FFFFFF" Margin="0,8,0,4"/>
        <TextBlock Text="Optimizador de sistema" FontSize="12" FontFamily="Segoe UI"
                   HorizontalAlignment="Center" Foreground="#555555"/>
      </StackPanel>
      <TextBlock Grid.Row="1" Text="Iniciando..." FontSize="11" FontFamily="Segoe UI"
                 HorizontalAlignment="Center" Foreground="#404040" Margin="0,0,0,8"/>
      <Grid Grid.Row="2" Margin="48,0,48,20" VerticalAlignment="Bottom">
        <Border x:Name="pbTrack" Background="#1A1A1A" CornerRadius="4" Height="6"/>
        <Border x:Name="pbFill"  Background="#00C8FF"  CornerRadius="4" Height="6"
                HorizontalAlignment="Left" Width="0"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

    try {
        $rd = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($splashXaml))
        $script:_splashWindow = [Windows.Markup.XamlReader]::Load($rd)
        $rd.Close()
    } catch { return }

    $script:_splashTrack = $script:_splashWindow.FindName("pbTrack")
    $script:_splashFill  = $script:_splashWindow.FindName("pbFill")
    $script:_splashTick  = 0
    $script:_splashTotal = 150

    $splashTimer          = New-Object Windows.Threading.DispatcherTimer
    $splashTimer.Interval = [TimeSpan]::FromMilliseconds(16)
    $splashTimer.Add_Tick({
        $script:_splashTick++
        $raw   = [math]::Min(1.0, $script:_splashTick / $script:_splashTotal)
        $eased = 1.0 - [math]::Pow(1.0 - $raw, 3)
        $w     = $script:_splashTrack.ActualWidth
        if ($w -gt 0) { $script:_splashFill.Width = [math]::Max(0.0, $w * $eased) }
        if ($script:_splashTick -ge $script:_splashTotal) {
            $this.Stop()
            $script:_splashWindow.Close()
        }
    })

    try {
        $script:_splashWindow.Add_ContentRendered({ $splashTimer.Start() })
        $script:_splashWindow.ShowDialog() | Out-Null
    } catch {}
}

$window.Dispatcher.Add_UnhandledException({
    param($s, $e)
    $ex = $e.Exception
    $lines = @(
        "=== WinBoost Crash Log ===",
        "Type:    $($ex.GetType().FullName)",
        "Message: $($ex.Message)",
        "Stack:",
        $ex.StackTrace
    )
    if ($ex.InnerException) {
        $lines += @("","Inner Type:    $($ex.InnerException.GetType().FullName)",
                    "Inner Message: $($ex.InnerException.Message)",
                    "Inner Stack:", $ex.InnerException.StackTrace)
    }
    $lines | Out-File "$env:USERPROFILE\Desktop\winboost_crash.txt" -Encoding UTF8 -Force
    $e.Handled = $false
})

# ============================================================
# F2.15 — MODO SILENCIOSO / CLI
# ============================================================

function Invoke-SilentMode {
    param([string]$SilentPreset = "Safe")

    # Log en archivo
    $logDir = "$env:USERPROFILE\.OptimizarPC\logs"
    if(-not (Test-Path $logDir)){ New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $script:silentLogPath = Join-Path $logDir "silent_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    @("WinBoost v$VERSION - Modo silencioso",
      "Preset: $SilentPreset  |  Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
      ("=" * 60)) | Out-File $script:silentLogPath -Encoding UTF8

    # Redirigir Write-Log/Set-Progress/Flush-UI al archivo (scope script para que
    # Invoke-*Tweaks que llaman Write-Log vean esta version en lugar de la de WPF)
    function script:Write-Log {
        param([string]$msg, [string]$type = "info")
        $pfx = switch($type){
            "ok"   { "[OK]  " }
            "err"  { "[ERR] " }
            "skip" { "[SKIP]" }
            "head" { "[====]" }
            default{ "[INFO]" }
        }
        "$(Get-Date -Format 'HH:mm:ss') $pfx $msg" | Out-File $script:silentLogPath -Append -Encoding UTF8
    }
    function script:Set-Progress { param($pct,$msg) Write-Log "[$pct%] $msg" }
    function script:Flush-UI {}

    # Seleccionar preset (reusar las tablas de la UI)
    $sel = switch($SilentPreset.ToLower()){
        "gaming" { $presetGaming }
        "prod"   { $presetProd }
        default  { $presetSafe }
    }

    # DNS provider: Cloudflare (index 0) por defecto en modo silencioso
    try { $cboDNSProvider.SelectedIndex = 0 } catch {}

    # Resetear contadores
    $script:freed       = 0
    $script:logLines    = @()
    $script:_optApplied = 0
    $script:_optSkipped = 0
    $script:_cancelOptimize = $false

    $exitCode = 0
    try {
        # Punto de restauracion
        if($sel["Startup"]){
            Write-Log "PUNTO DE RESTAURACION" "head"
            try {
                Enable-ComputerRestore -Drive "$SYSDRIVE\" -EA SilentlyContinue
                Checkpoint-Computer -Description "WinBoost Silent $SilentPreset" `
                    -RestorePointType "MODIFY_SETTINGS" -EA Stop
                Write-Log "Punto de restauracion creado" "ok"
            } catch { Write-Log "Punto de restauracion omitido: $_" "skip" }
        }

        Invoke-CleanupTweaks   $sel
        Invoke-RegistryTweaks  $sel
        Invoke-NetworkTweaks   $sel
        Invoke-ServiceTweaks   $sel

        if($sel["FastStartup"]){
            Set-Progress 88 "Fast Startup..."
            Write-Log "FAST STARTUP" "head"
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" DWord 0
            powercfg /hibernate off 2>$null | Out-Null
            Write-Log "Fast Startup deshabilitado" "ok"
            $script:_optApplied++
        }

        if($sel["PageFile"]){
            Set-Progress 91 "Optimizando PageFile..."
            Write-Log "PAGEFILE" "head"
            Save-PageFileBackup
            try {
                $pfMin = [math]::Max(4096, [math]::Min($totalRAM * 1024, 8192))
                $pfMax = [math]::Max(8192, [math]::Min($totalRAM * 1024 * 2, 16384))
                $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
                if($cs.AutomaticManagedPagefile){
                    Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -EA Stop
                }
                $pfPath = "$SYSDRIVE\pagefile.sys"
                New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                    Name        = $pfPath
                    InitialSize = [uint32]$pfMin
                    MaximumSize = [uint32]$pfMax
                } -EA Stop | Out-Null
                Write-Log "PageFile: $pfPath  min=$pfMin MB  max=$pfMax MB" "ok"
                $script:_optApplied++
            } catch {
                Write-Log "Error PageFile: $_" "err"
                try {
                    $cs2 = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
                    if($cs2 -and -not $cs2.AutomaticManagedPagefile){
                        Set-CimInstance -InputObject $cs2 -Property @{AutomaticManagedPagefile=$true} -EA SilentlyContinue
                    }
                } catch {}
            }
        }

        # TRIM sincrono en modo silencioso (sin DispatcherTimer disponible)
        if($sel["TrimDesfrag"]){
            Set-Progress 94 "TRIM / Desfrag..."
            Write-Log "TRIM / DESFRAG" "head"
            if($HAS_SSD){
                try {
                    Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" `
                        -TaskName "ScheduledDefrag" -EA SilentlyContinue | Out-Null
                } catch {}
                $ssdVols = Get-PhysicalDisk -EA SilentlyContinue |
                    Where-Object { $_.MediaType -eq "SSD" } |
                    Get-Disk      -EA SilentlyContinue |
                    Get-Partition -EA SilentlyContinue |
                    Get-Volume    -EA SilentlyContinue |
                    Where-Object  { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
                foreach($vol in $ssdVols){
                    try {
                        Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -NormalPriority -EA SilentlyContinue
                        Write-Log "TRIM completado en $($vol.DriveLetter):" "ok"
                    } catch { Write-Log "TRIM en $($vol.DriveLetter):: sin acceso" "skip" }
                }
            } else {
                try {
                    Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" `
                        -TaskName "ScheduledDefrag" -EA SilentlyContinue | Out-Null
                    Write-Log "Desfrag semanal habilitado (HDD)" "ok"
                } catch { Write-Log "Desfrag: no se pudo habilitar tarea" "skip" }
            }
            $script:_optApplied++
        }

        Set-Progress 100 "Completado"
        Write-Log "Completado. $($script:_optApplied) aplicados / $($script:_optSkipped) omitidos." "ok"

    } catch {
        Write-Log "Error critico: $_" "err"
        $exitCode = 1
    }

    @(("=" * 60),
      "Fin: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  Exit code: $exitCode",
      "Log: $script:silentLogPath") | Out-File $script:silentLogPath -Append -Encoding UTF8

    # Toast via NotifyIcon (no requiere ventana WPF ni modulos externos)
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        Add-Type -AssemblyName System.Drawing        -EA SilentlyContinue
        $notif = New-Object System.Windows.Forms.NotifyIcon
        $notif.Icon             = [System.Drawing.SystemIcons]::Application
        $notif.BalloonTipIcon   = if($exitCode -eq 0){ [System.Windows.Forms.ToolTipIcon]::Info } else { [System.Windows.Forms.ToolTipIcon]::Error }
        $notif.BalloonTipTitle  = if($exitCode -eq 0){ "WinBoost - Completado" } else { "WinBoost - Error" }
        $notif.BalloonTipText   = if($exitCode -eq 0){
            "$($script:_optApplied) cambios aplicados (preset: $SilentPreset). Reinicia para aplicar todos los cambios."
        } else {
            "Error durante la optimizacion. Ver: $script:silentLogPath"
        }
        $notif.Visible = $true
        $notif.ShowBalloonTip(8000)
        Start-Sleep -Milliseconds 400
        $notif.Dispose()
    } catch {}

    exit $exitCode
}

# ============================================================
# INICIO — bifurcar entre modo UI y modo silencioso
# ============================================================

if($Silent){
    Invoke-SilentMode -SilentPreset $Preset
} else {
    Load-Settings
    if($script:settings.ShowSplash){ Show-SplashScreen }
    $window.ShowDialog()|Out-Null
}