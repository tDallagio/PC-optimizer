#Requires -RunAsAdministrator
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

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
    SvcFax=Get-Ctrl "chkSvcFax"
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
if(-not $HAS_SSD){$checks.Prefetch.IsChecked=$false; $checks.SvcSysMain.IsChecked=$false}

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
$presetGaming=@{TempUser=$true;TempSys=$true;Prefetch=$true;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$true;HPET=$true;GPUPrio=$true;Scheduler=$true;PowerThrot=$true;Memory=$true;Visual=$true;MouseAccel=$true;Startup=$true;GameDVR=$true;GameMode=$true;Telemetry=$true;Cortana=$true;Notif=$true;Tasks=$true;Nagle=$true;TCP=$true;DNS=$true;DNSFlush=$true;SvcXbox=$true;SvcDiag=$true;SvcWER=$true;SvcSysMain=$true;SvcMaps=$true;SvcFax=$true}
$presetProd  =@{TempUser=$true;TempSys=$true;Prefetch=$false;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$true;HPET=$false;GPUPrio=$false;Scheduler=$false;PowerThrot=$false;Memory=$false;Visual=$false;MouseAccel=$false;Startup=$true;GameDVR=$true;GameMode=$true;Telemetry=$true;Cortana=$true;Notif=$false;Tasks=$true;Nagle=$false;TCP=$false;DNS=$true;DNSFlush=$true;SvcXbox=$true;SvcDiag=$true;SvcWER=$false;SvcSysMain=$false;SvcMaps=$false;SvcFax=$false}
$presetSafe  =@{TempUser=$true;TempSys=$true;Prefetch=$false;WinUpdate=$true;Browsers=$true;Thumb=$true;Recycle=$true;EventLogs=$false;Power=$false;HPET=$false;GPUPrio=$false;Scheduler=$false;PowerThrot=$false;Memory=$false;Visual=$false;MouseAccel=$false;Startup=$true;GameDVR=$false;GameMode=$false;Telemetry=$false;Cortana=$false;Notif=$false;Tasks=$false;Nagle=$false;TCP=$false;DNS=$true;DNSFlush=$true;SvcXbox=$false;SvcDiag=$false;SvcWER=$false;SvcSysMain=$false;SvcMaps=$false;SvcFax=$false}

function Apply-Preset { param($p); foreach($k in $p.Keys){if($checks.ContainsKey($k)){$checks[$k].IsChecked=$p[$k]}} }

$btnPresetGaming.Add_Click({ Apply-Preset $presetGaming })
$btnPresetProd.Add_Click({   Apply-Preset $presetProd })
$btnPresetSafe.Add_Click({   Apply-Preset $presetSafe })

$btnSaveProfile.Add_Click({
    try {
        $dir=Split-Path $PROFILE_PATH
        if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $obj=@{}; foreach($k in $checks.Keys){$obj[$k]=[bool]$checks[$k].IsChecked}
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
    if($sel["DNS"]){$dn=0;Get-NetAdapter -EA SilentlyContinue|Where-Object{$_.Status-eq"Up"}|ForEach-Object{try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses("1.1.1.1","1.0.0.1") -EA Stop;$dn++}catch{}};Write-Log "DNS Cloudflare en $dn adaptador(es)" "ok"}
    if($sel["DNSFlush"]){ipconfig /flushdns 2>$null|Out-Null;Write-Log "Cache DNS limpiada" "ok"}

    if($sel["SvcXbox"] -or $sel["SvcDiag"] -or $sel["SvcWER"] -or $sel["SvcSysMain"] -or $sel["SvcMaps"] -or $sel["SvcFax"]){Set-Progress 82 "Servicios..."; Write-Log "SERVICIOS" "head"}
    if($sel["SvcXbox"]){Disable-Svc "XblAuthManager" "Xbox Live Auth";Disable-Svc "XblGameSave" "Xbox GameSave";Disable-Svc "XboxNetApiSvc" "Xbox Networking"}
    if($sel["SvcDiag"]){Disable-Svc "DiagTrack" "DiagTrack"}
    if($sel["SvcWER"]){Disable-Svc "WerSvc" "Windows Error Reporting"}
    if($sel["SvcSysMain"] -and $HAS_SSD){Disable-Svc "SysMain" "SysMain/Superfetch"}
    if($sel["SvcMaps"]){Disable-Svc "MapsBroker" "Maps Broker";Disable-Svc "lfsvc" "Geolocation"}
    if($sel["SvcFax"]){Disable-Svc "Fax" "Fax";Disable-Svc "RemoteRegistry" "Remote Registry"}

    if($sel["Visual"]){Set-Progress 90 "Efectos visuales..."; Write-Log "EFECTOS VISUALES" "head"
        Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" DWord 2
        Set-Reg "HKCU:\Control Panel\Desktop" "FontSmoothing" String "2"
        if($totalRAM-le8){Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" DWord 0;Write-Log "Transparencia OFF (RAM baja)" "ok"}}

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

$window.ShowDialog()|Out-Null
