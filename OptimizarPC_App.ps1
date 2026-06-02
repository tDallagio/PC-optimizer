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
    public static void PurgeStandbyList() {
        IntPtr p = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(p, 4);
        NtSetSystemInformation(0x50, p, 4);
        Marshal.FreeHGlobal(p);
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
$VERSION   = "4.0"
$PROFILE_PATH = "$env:USERPROFILE\.OptimizarPC\profile.json"

# Cargar XAML desde archivo externo
$xamlPath = Join-Path $PSScriptRoot "OptimizarPC_UI.xaml"
if (-not (Test-Path $xamlPath)) {
    [Windows.MessageBox]::Show(
        "No se encontro OptimizarPC_UI.xaml`nAsegurate de que ambos archivos esten en la misma carpeta:`n$PSScriptRoot",
        "OptimizarPC - Archivo no encontrado","OK","Error")
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
$lblCPU=Get-Ctrl "lblCPU"; $lblGPU=Get-Ctrl "lblGPU"; $lblRAM=Get-Ctrl "lblRAM"; $lblDisk=Get-Ctrl "lblDisk"
$lblOS=Get-Ctrl "lblOS"; $badgeLaptop=Get-Ctrl "badgeLaptop"
$infoOS=Get-Ctrl "infoOS"; $infoCPU=Get-Ctrl "infoCPU"; $infoGPU=Get-Ctrl "infoGPU"
$infoRAM=Get-Ctrl "infoRAM"; $infoDisk=Get-Ctrl "infoDisk"; $infoType=Get-Ctrl "infoType"
$diskPanel=Get-Ctrl "diskPanel"; $rtbLog=Get-Ctrl "rtbLog"; $logScroll=Get-Ctrl "logScroll"
$lblLogStatus=Get-Ctrl "lblLogStatus"; $lblProgress=Get-Ctrl "lblProgress"; $lblPct=Get-Ctrl "lblPct"
$progressBar=Get-Ctrl "progressBar"; $lblSpaceFreed=Get-Ctrl "lblSpaceFreed"
$btnRun=Get-Ctrl "btnRun"; $btnSelAll=Get-Ctrl "btnSelAll"; $btnSelNone=Get-Ctrl "btnSelNone"
$btnClearLog=Get-Ctrl "btnClearLog"; $btnExportLog=Get-Ctrl "btnExportLog"; $mainTabs=Get-Ctrl "mainTabs"
$btnPresetGaming=Get-Ctrl "btnPresetGaming"; $btnPresetProd=Get-Ctrl "btnPresetProd"
$btnPresetSafe=Get-Ctrl "btnPresetSafe"; $btnSaveProfile=Get-Ctrl "btnSaveProfile"
$badgeUpdate=Get-Ctrl "badgeUpdate"; $lblUpdateBadge=Get-Ctrl "lblUpdateBadge"
$btnBenchmark=Get-Ctrl "btnBenchmark"; $lblBenchStatus=Get-Ctrl "lblBenchStatus"
$lblWriteSpeed=Get-Ctrl "lblWriteSpeed"; $lblReadSpeed=Get-Ctrl "lblReadSpeed"
$lblWriteCompare=Get-Ctrl "lblWriteCompare"; $lblReadCompare=Get-Ctrl "lblReadCompare"
$btnDeepClean=Get-Ctrl "btnDeepClean"; $lblDeepCleanStatus=Get-Ctrl "lblDeepCleanStatus"
$pbCPU=Get-Ctrl "pbCPU"; $lblCPUPct=Get-Ctrl "lblCPUPct"
$pbRAM=Get-Ctrl "pbRAM"; $lblRAMVal=Get-Ctrl "lblRAMVal"
$pbDisk=Get-Ctrl "pbDisk"; $lblDiskPct=Get-Ctrl "lblDiskPct"
$icStartup=Get-Ctrl "icStartup"; $lblStartupStatus=Get-Ctrl "lblStartupStatus"
$lblStartupCount=Get-Ctrl "lblStartupCount"; $btnRefreshStartup=Get-Ctrl "btnRefreshStartup"
$lblRAMTotal=Get-Ctrl "lblRAMTotal"; $lblRAMUsed=Get-Ctrl "lblRAMUsed"
$lblRAMFree=Get-Ctrl "lblRAMFree"; $lblRAMFreeStatus=Get-Ctrl "lblRAMFreeStatus"
$btnFreeRAM=Get-Ctrl "btnFreeRAM"
$cboDNSProvider=Get-Ctrl "cboDNSProvider"
$lblDNSHint=Get-Ctrl "lblDNSHint"

$checks = @{
    TempUser=Get-Ctrl "chkTempUser"; TempSys=Get-Ctrl "chkTempSys"
    Prefetch=Get-Ctrl "chkPrefetch"; WinUpdate=Get-Ctrl "chkWinUpdate"
    Browsers=Get-Ctrl "chkBrowsers"; Thumb=Get-Ctrl "chkThumb"
    Recycle=Get-Ctrl "chkRecycle";   EventLogs=Get-Ctrl "chkEventLogs"
    Power=Get-Ctrl "chkPower";       HPET=Get-Ctrl "chkHPET"
    GPUPrio=Get-Ctrl "chkGPUPrio";   Scheduler=Get-Ctrl "chkScheduler"
    PowerThrot=Get-Ctrl "chkPowerThrot"; Memory=Get-Ctrl "chkMemory"
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
        $t1.Foreground=New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::DarkGray)
        [Windows.Controls.Grid]::SetColumn($t1,0); $hdr.Children.Add($t1)|Out-Null
        $t2=New-Object Windows.Controls.TextBlock; $t2.Text="$used GB / $total GB  ($pct%)"; $t2.FontSize=12
        $t2.Foreground=New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($col))
        [Windows.Controls.Grid]::SetColumn($t2,1); $hdr.Children.Add($t2)|Out-Null
        $tb=New-Object Windows.Controls.Border
        $tb.Background=New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::DimGray)
        $tb.CornerRadius=New-Object Windows.CornerRadius(4); $tb.Height=5
        $tb.Margin=New-Object Windows.Thickness(0,5,0,0); $tb.ClipToBounds=$true
        $fb=New-Object Windows.Controls.Border; $fb.Height=5
        $fb.HorizontalAlignment=[Windows.HorizontalAlignment]::Left
        $fb.CornerRadius=New-Object Windows.CornerRadius(4)
        $fb.Background=New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($col))
        $pl=$pct; $fr=$fb
        $tb.add_SizeChanged({param($s,$e); $fr.Width=[math]::Max(0,$e.NewSize.Width*$pl/100)})
        $tb.Child=$fb; $sp.Children.Add($hdr)|Out-Null; $sp.Children.Add($tb)|Out-Null
        $diskPanel.Items.Add($sp)|Out-Null
    }
} catch {}

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
# HELPERS
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

    $para = New-Object System.Windows.Documents.Paragraph
    $para.Margin = New-Object Windows.Thickness(0)
    $run = New-Object System.Windows.Documents.Run($line)
    $run.Foreground = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($col))
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
    try{if(-not(Test-Path $p)){New-Item -Path $p -Force|Out-Null};Set-ItemProperty -Path $p -Name $n -Type $t -Value $v -Force;Write-Log "$n = $v" "ok"}
    catch{Write-Log "Fallo: $n" "err"}
}
function Disable-Svc {
    param([string]$name,[string]$label)
    try{$s=Get-Service -Name $name -EA SilentlyContinue
        if($s -and $s.StartType-ne"Disabled"){Stop-Service -Name $name -Force -EA SilentlyContinue;Set-Service -Name $name -StartupType Disabled -EA Stop;Write-Log $label "ok"}
        else{Write-Log "$label (ya deshabilitado)" "skip"}}
    catch{Write-Log "Sin permisos: $label" "skip"}
}

# ============================================================
# PRESETS
# ============================================================
$presetGaming=@{TempUser=$true;TempSys=$true;Prefetch=$true;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$true;HPET=$true;GPUPrio=$true;Scheduler=$true;PowerThrot=$true;Memory=$true;Visual=$true;MouseAccel=$true;Startup=$true;FastStartup=$true;PageFile=$true;TrimDesfrag=$true;GameDVR=$true;GameMode=$true;Telemetry=$true;Cortana=$true;Notif=$true;Tasks=$true;Nagle=$true;TCP=$true;DNS=$true;DNSFlush=$true;DisableIPv6=$false;SvcXbox=$true;SvcDiag=$true;SvcWER=$true;SvcSysMain=$true;SvcMaps=$true;SvcFax=$true;SvcWSearch=$true}
$presetProd  =@{TempUser=$true;TempSys=$true;Prefetch=$false;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$true;HPET=$false;GPUPrio=$false;Scheduler=$false;PowerThrot=$false;Memory=$false;Visual=$false;MouseAccel=$false;Startup=$true;FastStartup=$false;PageFile=$true;TrimDesfrag=$true;GameDVR=$true;GameMode=$true;Telemetry=$true;Cortana=$true;Notif=$false;Tasks=$true;Nagle=$false;TCP=$false;DNS=$true;DNSFlush=$true;DisableIPv6=$false;SvcXbox=$true;SvcDiag=$true;SvcWER=$false;SvcSysMain=$false;SvcMaps=$false;SvcFax=$false;SvcWSearch=$false}
$presetSafe  =@{TempUser=$true;TempSys=$true;Prefetch=$false;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$false;HPET=$false;GPUPrio=$false;Scheduler=$false;PowerThrot=$false;Memory=$false;Visual=$false;MouseAccel=$false;Startup=$true;FastStartup=$false;PageFile=$false;TrimDesfrag=$false;GameDVR=$false;GameMode=$false;Telemetry=$false;Cortana=$false;Notif=$false;Tasks=$false;Nagle=$false;TCP=$false;DNS=$true;DNSFlush=$true;DisableIPv6=$false;SvcXbox=$false;SvcDiag=$false;SvcWER=$false;SvcSysMain=$false;SvcMaps=$false;SvcFax=$false;SvcWSearch=$false}

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
        $obj|ConvertTo-Json|Out-File $PROFILE_PATH -Encoding UTF8
        [Windows.MessageBox]::Show("Perfil guardado:`n$PROFILE_PATH","OptimizarPC v$VERSION","OK","Information")|Out-Null
    } catch { [Windows.MessageBox]::Show("Error al guardar: $_","Error","OK","Error")|Out-Null }
})

# ============================================================
# BOTONES AUXILIARES
# ============================================================
$btnSelAll.Add_Click({foreach($c in $checks.Values){$c.IsChecked=$true}})
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
        [Windows.MessageBox]::Show("Log exportado a:`n$outFile","OptimizarPC v$VERSION","OK","Information")|Out-Null
    } catch { [Windows.MessageBox]::Show("Error al exportar: $_","Error","OK","Error")|Out-Null }
})

# ============================================================
# EJECUTAR
# ============================================================
$btnRun.Add_Click({
    $sel=@{}; foreach($k in $checks.Keys){$sel[$k]=[bool]$checks[$k].IsChecked}
    $btnRun.IsEnabled=$false; $btnSelAll.IsEnabled=$false; $btnSelNone.IsEnabled=$false
    $lblSpaceFreed.Text=""; $script:freed=0; $script:logLines=@()
    $rtbLog.Document.Blocks.Clear()
    $mainTabs.SelectedIndex=1; $lblLogStatus.Text="Ejecutando..."; Flush-UI

    if($sel["Startup"]){Set-Progress 2 "Punto de restauracion..."
        Write-Log "PUNTO DE RESTAURACION" "head"
        try{Enable-ComputerRestore -Drive "$SYSDRIVE\" -EA SilentlyContinue
            Checkpoint-Computer -Description "OptimizarPC v$VERSION" -RestorePointType "MODIFY_SETTINGS" -EA Stop
            Write-Log "Punto de restauracion creado" "ok"}catch{Write-Log "No se pudo crear: $_" "err"}}

    Write-Log "LIMPIEZA DE ARCHIVOS" "head"; Set-Progress 8 "Limpiando temporales..."
    if($sel["TempUser"]){$script:freed+=Remove-Dir $env:TEMP "Temp usuario"}
    if($sel["TempSys"]){$script:freed+=Remove-Dir "$SYSDRIVE\Windows\Temp" "Temp sistema"}
    if($sel["Prefetch"] -and $HAS_SSD){$script:freed+=Remove-Dir "$SYSDRIVE\Windows\Prefetch" "Prefetch"}
    if($sel["WinUpdate"]){Stop-Service -Name wuauserv -Force -EA SilentlyContinue;$script:freed+=Remove-Dir "$SYSDRIVE\Windows\SoftwareDistribution\Download" "WUpdate cache";Start-Service -Name wuauserv -EA SilentlyContinue}
    if($sel["Browsers"]){Set-Progress 14 "Cache navegadores..."
        @(@{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache";N="Chrome"},
          @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache";N="Edge"},
          @{P="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache";N="Brave"},
          @{P="$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache";N="Opera"},
          @{P="$env:APPDATA\Mozilla\Firefox\Profiles";N="Firefox"})|ForEach-Object{$script:freed+=Remove-Dir $_.P "Cache $($_.N)"}}
    if($sel["Thumb"]){$script:freed+=Remove-Dir "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" "Thumbnails"}
    if($sel["Recycle"]){try{Clear-RecycleBin -Force -EA SilentlyContinue;Write-Log "Papelera vaciada" "ok"}catch{Write-Log "Papelera: archivos en uso" "skip"}}
    if($sel["EventLogs"]){Set-Progress 18 "Logs de eventos..."
        Get-WinEvent -ListLog * -EA SilentlyContinue|Where-Object{$_.IsEnabled}|ForEach-Object{try{[System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)}catch{}}
        Write-Log "Logs de eventos limpiados" "ok"}
    $mb=[math]::Round($script:freed,1); Write-Log "Total liberado: $mb MB" "ok"; $lblSpaceFreed.Text="$mb MB liberados"

    if($sel["Power"]){Set-Progress 30 "Plan de energia..."; Write-Log "PLAN DE ENERGIA" "head"
        if(-not $IS_LAPTOP){$g="e9a42b02-d5df-448d-aa00-03f14749eb61"
            if(-not(powercfg /list|Select-String $g)){powercfg -duplicatescheme $g 2>$null}
            $pl=powercfg /list|Select-String $g
            if($pl){$guid=($pl.ToString() -split '\s+'|Where-Object{$_ -match '^[0-9a-f-]{36}$'})[0];powercfg /setactive $guid;Write-Log "Ultimate Performance activado" "ok"}
            else{powercfg /setactive SCHEME_MIN;Write-Log "Alto Rendimiento activado" "ok"}
            powercfg /hibernate off;Write-Log "Hibernate desactivado" "ok"}
        else{powercfg /setactive SCHEME_MIN;Write-Log "Alto Rendimiento activado (laptop)" "ok"}
        powercfg /change standby-timeout-ac 0}

    if($sel["HPET"]){Set-Progress 36 "HPET..."; Write-Log "HPET / TIMER" "head"
        bcdedit /deletevalue useplatformclock 2>$null|Out-Null
        bcdedit /set useplatformtick yes 2>$null|Out-Null
        bcdedit /set disabledynamictick yes 2>$null|Out-Null
        Write-Log "HPET deshabilitado - TSC activado" "ok"}

    Write-Log "REGISTRO" "head"; Set-Progress 44 "Tweaks de registro..."
    $gp="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if($sel["GPUPrio"]){Set-Reg $gp "GPU Priority" DWord 8;Set-Reg $gp "Priority" DWord 6;Set-Reg $gp "Scheduling Category" String "High";Set-Reg $gp "SFIO Priority" String "High";Set-Reg $gp "Background Only" String "False"}
    if($sel["Scheduler"]){Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" DWord 26}
    if($sel["Memory"]){$mp="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management";Set-Reg $mp "LargeSystemCache" DWord 0;Set-Reg $mp "DisablePagingExecutive" DWord 1}
    if($sel["PowerThrot"]){Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" DWord 1}
    if($sel["MouseAccel"]){Set-Reg "HKCU:\Control Panel\Mouse" "MouseSpeed" String "0";Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold1" String "0";Set-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold2" String "0";Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" "MouseDataQueueSize" DWord 20}

    if($sel["GameDVR"] -or $sel["GameMode"]){Set-Progress 52 "Game DVR..."; Write-Log "GAME DVR / XBOX" "head"}
    if($sel["GameDVR"]){Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" DWord 0;Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" DWord 2;Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" DWord 1;Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" DWord 0}
    if($sel["GameMode"]){Set-Reg "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" DWord 0;Set-Reg "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" DWord 0}

    if($sel["Telemetry"] -or $sel["Cortana"] -or $sel["Notif"] -or $sel["Tasks"]){Set-Progress 60 "Privacidad..."; Write-Log "PRIVACIDAD / TELEMETRIA" "head"}
    if($sel["Telemetry"]){Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" DWord 0;Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" DWord 0}
    if($sel["Cortana"]){Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" DWord 0}
    if($sel["Notif"]){Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" "ToastEnabled" DWord 0}
    if($sel["Tasks"]){
        $telTasks=@(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        )
        foreach($t in $telTasks){try{Disable-ScheduledTask -TaskPath(Split-Path $t) -TaskName(Split-Path $t -Leaf) -EA SilentlyContinue|Out-Null}catch{}}
        Write-Log "Tareas telemetria deshabilitadas" "ok"}

    if($sel["Nagle"] -or $sel["TCP"] -or $sel["DNS"] -or $sel["DNSFlush"]){Set-Progress 70 "Red..."; Write-Log "RED" "head"}
    if($sel["Nagle"]){$n=0;Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA SilentlyContinue|ForEach-Object{$ip=Get-ItemProperty -Path $_.PSPath -Name "DhcpIPAddress" -EA SilentlyContinue;if($ip -and $ip.DhcpIPAddress -and $ip.DhcpIPAddress-ne"0.0.0.0"){Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Type DWord -Value 1 -Force -EA SilentlyContinue;Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Type DWord -Value 1 -Force -EA SilentlyContinue;$n++}};Write-Log "Nagle OFF en $n adaptador(es)" "ok"}
    if($sel["TCP"]){netsh int tcp set global autotuninglevel=normal 2>$null|Out-Null;netsh int tcp set global chimney=disabled 2>$null|Out-Null;netsh int tcp set global rss=enabled 2>$null|Out-Null;netsh int tcp set global fastopen=enabled 2>$null|Out-Null;Write-Log "TCP/IP optimizado" "ok"}
    if($sel["DNS"]){
        $dnsIdx = $cboDNSProvider.SelectedIndex
        if($dnsIdx -lt 0 -or $dnsIdx -ge $script:dnsProviders.Count){ $dnsIdx=0 }
        $dnsProv = $script:dnsProviders[$dnsIdx]
        $dn=0
        Get-NetAdapter -EA SilentlyContinue | Where-Object{$_.Status-eq"Up"} | ForEach-Object {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses($dnsProv.Primary, $dnsProv.Secondary) -EA Stop
                $dn++
            } catch {}
        }
        Write-Log "DNS $($dnsProv.Name) ($($dnsProv.Primary) / $($dnsProv.Secondary)) en $dn adaptador(es)" "ok"
    }
    if($sel["DNSFlush"]){ipconfig /flushdns 2>$null|Out-Null;Write-Log "Cache DNS limpiada" "ok"}
    if($sel["DisableIPv6"]){Set-Progress 75 "Deshabilitando IPv6..."
        Write-Log "IPV6" "head"
        $n6=0
        Get-NetAdapter -EA SilentlyContinue | Where-Object{$_.Status -eq "Up"} | ForEach-Object {
            try {
                Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -EA Stop
                $n6++
            } catch {}
        }
        # Tambien via registro para persistencia total
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" DWord 0xFF
        Write-Log "IPv6 deshabilitado en $n6 adaptador(es) + registro" "ok"
    }

    if($sel["SvcXbox"] -or $sel["SvcDiag"] -or $sel["SvcWER"] -or $sel["SvcSysMain"] -or $sel["SvcMaps"] -or $sel["SvcFax"] -or $sel["SvcWSearch"]){Set-Progress 82 "Servicios..."; Write-Log "SERVICIOS" "head"}
    if($sel["SvcXbox"]){Disable-Svc "XblAuthManager" "Xbox Live Auth";Disable-Svc "XblGameSave" "Xbox GameSave";Disable-Svc "XboxNetApiSvc" "Xbox Networking"}
    if($sel["SvcDiag"]){Disable-Svc "DiagTrack" "DiagTrack"}
    if($sel["SvcWER"]){Disable-Svc "WerSvc" "Windows Error Reporting"}
    if($sel["SvcSysMain"] -and $HAS_SSD){Disable-Svc "SysMain" "SysMain/Superfetch"}
    if($sel["SvcMaps"]){Disable-Svc "MapsBroker" "Maps Broker";Disable-Svc "lfsvc" "Geolocation"}
    if($sel["SvcFax"]){Disable-Svc "Fax" "Fax";Disable-Svc "RemoteRegistry" "Remote Registry"}
    if($sel["SvcWSearch"] -and $HAS_SSD){Disable-Svc "WSearch" "Windows Search (indexado)"}

    if($sel["FastStartup"]){Set-Progress 88 "Fast Startup..."; Write-Log "FAST STARTUP" "head"
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" DWord 0
        powercfg /hibernate off 2>$null | Out-Null
        Write-Log "Fast Startup deshabilitado (HiberbootEnabled=0 + hibernate off)" "ok"
    }

    # ----------------------------------------------------------
    # PAGEFILE
    # ----------------------------------------------------------
    if($sel["PageFile"]){Set-Progress 91 "Optimizando PageFile..."; Write-Log "PAGEFILE" "head"
        try {
            # Calcular min/max optimos segun RAM instalada
            # min = 1x RAM (MB), max = 2x RAM (MB), tope de 8192 MB para sistemas con mucha RAM
            $pfMin = [math]::Min($totalRAM * 1024, 4096)
            $pfMax = [math]::Min($totalRAM * 1024 * 2, 8192)

            # Detectar disco secundario (distinto de SYSDRIVE)
            $altDrive = $null
            try {
                $altDrive = Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue |
                    Where-Object { $_.Root -ne "$SYSDRIVE\" -and $null -ne $_.Used } |
                    Select-Object -First 1
            } catch {}

            $targetDrive = $SYSDRIVE
            if($altDrive){
                $altRoot = $altDrive.Root.TrimEnd('\')
                $resp = [Windows.MessageBox]::Show(
                    "Se detecto el disco secundario $altRoot`n`nMover el PageFile a $altRoot para liberar espacio en $SYSDRIVE ?`n`n[Si] = Mover a $altRoot`n[No] = Mantener en $SYSDRIVE",
                    "OptimizarPC - PageFile",
                    [Windows.MessageBoxButton]::YesNo,
                    [Windows.MessageBoxImage]::Question)
                if($resp -eq [Windows.MessageBoxResult]::Yes){ $targetDrive = $altRoot }
            }

            # Deshabilitar gestion automatica para todos los volumenes
            $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
            if($cs.AutomaticManagedPagefile){
                Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -EA Stop
                Write-Log "Gestion automatica de PageFile desactivada" "ok"
            }

            # Eliminar PageFiles existentes via WMI
            $existing = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue
            foreach($pf in $existing){
                try { Remove-CimInstance -InputObject $pf -EA SilentlyContinue } catch {}
            }

            # Crear PageFile en el disco elegido con tamaño fijo
            $pfPath = "$targetDrive\pagefile.sys"
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name        = $pfPath
                InitialSize = [uint32]$pfMin
                MaximumSize = [uint32]$pfMax
            } -EA Stop | Out-Null

            Write-Log "PageFile: $pfPath  min=$pfMin MB  max=$pfMax MB" "ok"
            Write-Log "Cambio efectivo tras reinicio" "info"
        } catch {
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

                # Ejecutar TRIM en todos los volumenes SSD accesibles (en background para no bloquear UI)
                $ssdVolumes = Get-PhysicalDisk -EA SilentlyContinue |
                    Where-Object { $_.MediaType -eq "SSD" } |
                    Get-Disk -EA SilentlyContinue |
                    Get-Partition -EA SilentlyContinue |
                    Get-Volume -EA SilentlyContinue |
                    Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }

                foreach($vol in $ssdVolumes){
                    try {
                        Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -NormalPriority -EA SilentlyContinue
                        Write-Log "TRIM ejecutado en $($vol.DriveLetter):" "ok"
                    } catch { Write-Log "TRIM en $($vol.DriveLetter): omitido" "skip" }
                }

            } else {
                # HDD: habilitar la tarea de desfragmentacion semanal
                try {
                    Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -EA Stop | Out-Null
                    Write-Log "Desfragmentacion semanal habilitada (HDD)" "ok"
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

    if($sel["Visual"]){Set-Progress 96 "Efectos visuales..."; Write-Log "EFECTOS VISUALES" "head"
        Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" DWord 2
        Set-Reg "HKCU:\Control Panel\Desktop" "FontSmoothing" String "2"
        if($totalRAM-le8){Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" DWord 0;Write-Log "Transparencia OFF (RAM baja)" "ok"}
    }

    Set-Progress 100 "Completado"
    Write-Log "Optimizacion completada. Reinicia para aplicar todos los cambios." "ok"
    $lblLogStatus.Text="Completado"; $btnRun.IsEnabled=$true; $btnSelAll.IsEnabled=$true; $btnSelNone.IsEnabled=$true; Flush-UI

    $r=[Windows.MessageBox]::Show("Optimizacion completada.`n`nReiniciar ahora para aplicar todos los cambios?","OptimizarPC v$VERSION",[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question)
    if($r -eq [Windows.MessageBoxResult]::Yes){Restart-Computer -Force}
})


# ============================================================
# CHECK DE ACTUALIZACIONES (GitHub JSON)
# URL del version.json en tu GitHub Gist o repo:
# ============================================================
$UPDATE_CHECK_URL = "https://raw.githubusercontent.com/TU_USUARIO/OptimizarPC/main/version.json"
$script:updateReleaseUrl = ""

function Check-ForUpdates {
    try {
        $response = Invoke-RestMethod -Uri $UPDATE_CHECK_URL -TimeoutSec 5 -ErrorAction Stop
        $remoteVer = [version]($response.version -replace "[^0-9.]","")
        $localVer  = [version]($VERSION -replace "[^0-9.]","")
        $script:updateReleaseUrl = $response.releaseUrl

        if ($remoteVer -gt $localVer) {
            $badgeUpdate.Visibility  = "Visible"
            $lblUpdateBadge.Text     = "v$($response.version) disponible"
            $badgeUpdate.ToolTip     = "Nueva version: $($response.version)`nClick para ver los cambios"
        }
    } catch {
        # Sin conexion o URL invalida: ignorar silenciosamente
    }
}

# Click en el badge abre la URL de release
$badgeUpdate.Add_MouseLeftButtonUp({
    if ($script:updateReleaseUrl) {
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
            $lblWriteCompare.Foreground = New-Object Windows.Media.SolidColorBrush(
                [Windows.Media.ColorConverter]::ConvertFromString($(if($wDiff -ge 0){"#22C55E"}else{"#EF4444"})))
            $lblReadCompare.Foreground  = New-Object Windows.Media.SolidColorBrush(
                [Windows.Media.ColorConverter]::ConvertFromString($(if($rDiff -ge 0){"#22C55E"}else{"#EF4444"})))
            $script:benchWritePre = $writeMBs
            $script:benchReadPre  = $readMBs
            $lblBenchStatus.Text  = "Comparacion completada"
        }
    } catch {
        $lblBenchStatus.Text = "Error: $_"
    }
    $btnBenchmark.IsEnabled = $true
    Flush-UI
})

# ============================================================
# LIMPIEZA PROFUNDA DE CACHE
# ============================================================
$btnDeepClean.Add_Click({
    $r = [Windows.MessageBox]::Show(
        "El Explorador de Windows se detendra y reiniciara automaticamente.`nLa pantalla puede parpadear 2-3 segundos.`n`nContinuar?",
        "OptimizarPC v$VERSION",
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Warning)
    if ($r -ne [Windows.MessageBoxResult]::Yes) { return }

    $btnDeepClean.IsEnabled  = $false
    $lblDeepCleanStatus.Text = "Deteniendo Explorer..."
    Flush-UI
    try {
        Stop-Process -Name explorer -Force -EA SilentlyContinue
        Start-Sleep -Milliseconds 1500

        # IconCache.db (ubicacion clasica)
        Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -EA SilentlyContinue

        # iconcache_*.db y thumbcache_*.db (Win10/11 modernos)
        $cacheDir   = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        $cacheFiles = Get-ChildItem -Path $cacheDir -Include "iconcache_*.db","thumbcache_*.db" -Force -EA SilentlyContinue
        $count = 0
        foreach ($f in $cacheFiles) { Remove-Item $f.FullName -Force -EA SilentlyContinue; $count++ }

        Start-Process explorer
        $lblDeepCleanStatus.Text = "Listo - IconCache.db + $count archivos de cache eliminados"
    } catch {
        $lblDeepCleanStatus.Text = "Error: $_"
        if (-not (Get-Process explorer -EA SilentlyContinue)) { Start-Process explorer }
    }
    $btnDeepClean.IsEnabled = $true
    Flush-UI
})

# ============================================================
# MONITOR EN TIEMPO REAL  (DispatcherTimer - tick cada 1 s)
# ============================================================
$script:monitorTotalRAMMB = $totalRAM * 1024   # total RAM del sistema en MB (entero)

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
    Green  = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#22C55E"))
    Yellow = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#F59E0B"))
    Red    = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#EF4444"))
    Blue   = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#00C8FF"))
}
try { foreach ($b in $brMon.Values) { $b.Freeze() } } catch {}

$script:monitorTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:monitorTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:monitorTimer.Add_Tick({
    try {
        $cpu  = [math]::Min(100, [math]::Round($script:pcCPU.NextValue(),     0))
        $disk = [math]::Min(100, [math]::Round($script:pcDisk.NextValue(),    0))
        $free = [math]::Round($script:pcRAMFree.NextValue(), 0)
        $used = [math]::Max(0, $script:monitorTotalRAMMB - $free)
        $ramPct = [math]::Min(100,[math]::Round($used / [math]::Max(1,$script:monitorTotalRAMMB) * 100, 0))
        $usedGB = [math]::Round($used / 1024, 1)
        $totGB  = $script:monitorTotalRAMMB / 1024

        $pbCPU.Value  = $cpu;    $lblCPUPct.Text = "$cpu%"
        $pbRAM.Value  = $ramPct; $lblRAMVal.Text = "$usedGB / $totGB GB"
        $pbDisk.Value = $disk;   $lblDiskPct.Text = "$disk%"

        $pbCPU.Foreground  = if($cpu    -gt 85){$brMon.Red}elseif($cpu    -gt 60){$brMon.Yellow}else{$brMon.Green}
        $pbRAM.Foreground  = if($ramPct -gt 85){$brMon.Red}elseif($ramPct -gt 70){$brMon.Yellow}else{$brMon.Blue}
        $pbDisk.Foreground = if($disk   -gt 85){$brMon.Red}elseif($disk   -gt 60){$brMon.Yellow}else{$brMon.Green}
    } catch {}
})
$script:monitorTimer.Start()

$window.Add_Closing({
    $script:monitorTimer.Stop()
    try { $script:pcCPU.Dispose(); $script:pcRAMFree.Dispose(); $script:pcDisk.Dispose() } catch {}
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
        $rowBorder.BorderBrush = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#1A1A1A"))

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
        $stBdr.Background = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($(if($item.Enabled){"#0A2A0A"}else{"#222222"})))
        $stTxt = New-Object Windows.Controls.TextBlock
        $stTxt.Text = if($item.Enabled){"Activo"}else{"Inactivo"}
        $stTxt.FontSize = 10
        $stTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($(if($item.Enabled){"#22C55E"}else{"#555555"})))
        $stBdr.Child = $stTxt
        [Windows.Controls.Grid]::SetColumn($stBdr, 0)

        # Col 1 - Nombre
        $nameTxt = New-Object Windows.Controls.TextBlock
        $nameTxt.Text = $item.Name
        $nameTxt.FontSize = 12
        $nameTxt.Foreground = New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::LightGray)
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
        $srcBdr.Background = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#1A1A2A"))
        $srcTxt = New-Object Windows.Controls.TextBlock
        $srcTxt.Text = $item.Source
        $srcTxt.FontSize = 10
        $srcTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#7788AA"))
        $srcBdr.Child = $srcTxt
        [Windows.Controls.Grid]::SetColumn($srcBdr, 2)

        # Col 3 - Ruta
        $pathTxt = New-Object Windows.Controls.TextBlock
        $pathTxt.Text = $item.Path
        $pathTxt.FontSize = 11
        $pathTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#444444"))
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
        $lblStartupStatus.Text = "Error: $_"
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

$btnFreeRAM.Add_Click({
    $btnFreeRAM.IsEnabled    = $false
    $lblRAMFreeStatus.Text   = "Liberando procesos..."
    Flush-UI
    try {
        $osBefore = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        $freeBefore = $osBefore.FreePhysicalMemory

        # Paso 1: EmptyWorkingSet en todos los procesos accesibles
        $count = 0
        Get-Process -EA SilentlyContinue | ForEach-Object {
            try { [MemAPI]::EmptyWorkingSet($_.Handle) | Out-Null; $count++ } catch {}
        }

        $lblRAMFreeStatus.Text = "Vaciando Standby List..."
        Flush-UI

        # Paso 2: Purgar Standby List del kernel (requiere admin)
        try { [MemAPI]::PurgeStandbyList() } catch {}

        Start-Sleep -Milliseconds 600
        $osAfter  = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        $freeAfter = $osAfter.FreePhysicalMemory
        $freedMB  = [math]::Round(($freeAfter - $freeBefore) / 1KB, 0)
        $sign     = if($freedMB -ge 0){"+"}else{""}

        Update-RAMDisplay
        $lblRAMFreeStatus.Text = "Completado  |  ${sign}${freedMB} MB liberados  |  $count procesos procesados"
    } catch {
        $lblRAMFreeStatus.Text = "Error: $_"
    }
    $btnFreeRAM.IsEnabled = $true
    Flush-UI
})

# Cargar datos al mostrar la ventana
$window.Add_ContentRendered({
    Load-StartupItems
    Render-StartupItems
    Update-RAMDisplay
})

$window.ShowDialog()|Out-Null
