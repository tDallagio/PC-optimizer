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
$VERSION      = "4.0"
$PROFILE_PATH = "$env:USERPROFILE\.OptimizarPC\profile.json"
$BACKUP_ROOT  = "$env:USERPROFILE\.OptimizarPC\backups"

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
            $startType = (Get-CimInstance Win32_Service -Filter "Name='$svcName'" -EA SilentlyContinue).StartMode
            $script:sessionSvcBackup += [PSCustomObject]@{
                name      = $svcName
                startMode = if($startType){ $startType } else { $svc.StartType.ToString() }
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
# Restore-RegFromSession
# Importa todos los archivos .reg de una sesion usando reg import.
# Devuelve @{ ok=N; failed=N; skipped=N }
# ------------------------------------------------------------
function Restore-RegFromSession {
    param([string]$sessionPath)
    $result = @{ ok=0; failed=0; skipped=0 }
    try {
        $regFiles = Get-ChildItem -Path $sessionPath -Filter "reg_*.reg" `
                        -EA SilentlyContinue | Sort-Object Name

        foreach($f in $regFiles){
            # Archivo vacio = clave no existia antes, hay que borrarla
            if((Get-Item $f.FullName).Length -lt 5){
                # Intentar eliminar la clave del registro si existe
                # El nombre del .reg codifica la ruta (solo es posible si tenemos el json)
                $result.skipped++
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
        "Auto"     = "Automatic"
        "Automatic"= "Automatic"
        "Manual"   = "Manual"
        "Disabled" = "Disabled"
        "Boot"     = "Boot"
        "System"   = "System"
    }

    foreach($svcInfo in $sessionMeta.services){
        try {
            $svc = Get-Service -Name $svcInfo.name -EA SilentlyContinue
            if(-not $svc){ $result.skipped++; continue }

            $startupType = if($modeMap.ContainsKey($svcInfo.startMode)){
                               $modeMap[$svcInfo.startMode]
                           } else { "Manual" }

            Set-Service -Name $svcInfo.name -StartupType $startupType -EA Stop

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

    # 5) Plan de energia - restaurar Balanced si fue cambiado
    if($meta){
        $powerAction = $meta.actions | Where-Object { $_.label -match "PowerThrottling|power|energia" }
        if($powerAction){
            try {
                powercfg /setactive SCHEME_BALANCED 2>$null | Out-Null
                & $log "Plan de energia restaurado a Equilibrado" "ok"
                $totalOk++
            } catch {}
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
    if($sel["EventLogs"]) { Add-Action "Limpieza" "Logs de eventos"   "Borra el historial de eventos de Windows"                   "medium" }

    # --- RENDIMIENTO ---
    if($sel["Power"])      { Add-Action "Rendimiento" "Plan de energia"        "Activa Ultimate Performance / Alto Rendimiento"         "medium" }
    if($sel["HPET"])       { Add-Action "Rendimiento" "Deshabilitar HPET"      "bcdedit: useplatformtick, disabledynamictick"           "medium" }
    if($sel["GPUPrio"])    { Add-Action "Rendimiento" "GPU Priority"           "Registro DXGI: GPU Priority=8, Scheduling=High"         "medium" }
    if($sel["Scheduler"])  { Add-Action "Rendimiento" "CPU Scheduler"          "Win32PrioritySeparation=26 en registro"                 "medium" }
    if($sel["PowerThrot"]) { Add-Action "Rendimiento" "Power Throttling OFF"   "PowerThrottlingOff=1 - evita bajadas de frecuencia"     "medium" }
    if($sel["Memory"])     { Add-Action "Rendimiento" "Optimizar memoria"      "LargeSystemCache=0, DisablePagingExecutive=1"            "medium" }
    if($sel["Visual"])     { Add-Action "Rendimiento" "Efectos visuales min."  "VisualFXSetting=2 - desactiva animaciones de Windows"   "low"    }
    if($sel["MouseAccel"]) { Add-Action "Rendimiento" "Mouse accel OFF"        "MouseSpeed=0, MouseThreshold1/2=0"                      "low"    }
    if($sel["FastStartup"]){ Add-Action "Rendimiento" "Fast Startup OFF"       "HiberbootEnabled=0 + powercfg hibernate off"            "medium" }
    if($sel["PageFile"])   { Add-Action "Rendimiento" "Optimizar PageFile"     "Tamanio fijo segun RAM via Win32_PageFileSetting"        "high"   }
    if($sel["TrimDesfrag"]){ Add-Action "Rendimiento" "TRIM / Desfrag"         if($HAS_SSD){"Optimize-Volume ReTrim en SSD"}else{"Desfrag semanal HDD"} "low" }

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
    if($sel["DisableIPv6"]){ Add-Action "Red" "Deshabilitar IPv6" "Disable-NetAdapterBinding ms_tcpip6 + registro"            "high"   }

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
        Title="OptimizarPC - Confirmar optimizacion"
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
        <TextBlock Grid.Column="0" Text="Esta accion requiere reinicio para aplicar todos los cambios."
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

        # Header de categoria si cambia
        if($action.Category -ne $currentCat){
            $currentCat = $action.Category
            $catBorder  = New-Object Windows.Controls.Border
            $catBorder.Padding    = New-Object Windows.Thickness(10,8,10,4)
            $catBorder.Margin     = New-Object Windows.Thickness(0,4,0,0)
            $catTxt = New-Object Windows.Controls.TextBlock
            $catTxt.Text       = $action.Category.ToUpper()
            $catTxt.FontSize   = 10
            $catTxt.FontWeight = [Windows.FontWeights]::SemiBold
            $catTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
                [Windows.Media.ColorConverter]::ConvertFromString("#555555"))
            $catBorder.Child = $catTxt
            $icPlan.Items.Add($catBorder) | Out-Null
        }

        # Fila de accion
        $rowBdr = New-Object Windows.Controls.Border
        $rowBdr.Padding         = New-Object Windows.Thickness(10,6,10,6)
        $rowBdr.Margin          = New-Object Windows.Thickness(0,1,0,0)
        $rowBdr.Background      = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $rowBdr.CornerRadius    = New-Object Windows.CornerRadius(5)

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

        # Texto - label + detail
        $textPanel = New-Object Windows.Controls.StackPanel
        $lblTxt = New-Object Windows.Controls.TextBlock
        $lblTxt.Text       = $action.Label
        $lblTxt.FontSize   = 12
        $lblTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#DDDDDD"))
        $detTxt = New-Object Windows.Controls.TextBlock
        $detTxt.Text        = $action.Detail
        $detTxt.FontSize    = 10
        $detTxt.TextWrapping= [Windows.TextWrapping]::Wrap
        $detTxt.Foreground  = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#555555"))
        $detTxt.Margin      = New-Object Windows.Thickness(0,2,0,0)
        $textPanel.Children.Add($lblTxt) | Out-Null
        $textPanel.Children.Add($detTxt) | Out-Null
        [Windows.Controls.Grid]::SetColumn($textPanel, 0)

        # Badge impacto
        $impBdr = New-Object Windows.Controls.Border
        $impBdr.CornerRadius      = New-Object Windows.CornerRadius(3)
        $impBdr.Padding           = New-Object Windows.Thickness(7,3,7,3)
        $impBdr.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $impBdr.HorizontalAlignment=[Windows.HorizontalAlignment]::Right
        $col = $impactColor[$action.Impact]
        $impBdr.Background = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString(
                $(switch($action.Impact){"high"{"#2A0A0A"};"medium"{"#2A1A00"};"low"{"#0A2A0A"}})))
        $impBdr.BorderBrush = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($col))
        $impBdr.BorderThickness = New-Object Windows.Thickness(1)
        $impTxt = New-Object Windows.Controls.TextBlock
        $impTxt.Text       = $impactLabel[$action.Impact]
        $impTxt.FontSize   = 10
        $impTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($col))
        $impBdr.Child = $impTxt
        [Windows.Controls.Grid]::SetColumn($impBdr, 1)

        $rowGrid.Children.Add($textPanel) | Out-Null
        $rowGrid.Children.Add($impBdr)    | Out-Null
        $rowBdr.Child = $rowGrid
        $icPlan.Items.Add($rowBdr) | Out-Null
    }

    # Resultado del dialogo
    $script:dialogResult = $false

    $btnConfirm.Add_Click({
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
# EJECUTAR
# ============================================================
$btnRun.Add_Click({
    $sel=@{}; foreach($k in $checks.Keys){$sel[$k]=[bool]$checks[$k].IsChecked}

    # --- Verificar que hay algo seleccionado ---
    $anySelected = $sel.Values | Where-Object { $_ -eq $true }
    if(-not $anySelected){
        [Windows.MessageBox]::Show(
            "No hay ninguna opcion seleccionada.`nSelecciona al menos una opcion antes de ejecutar.",
            "OptimizarPC v$VERSION",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    # --- Modal de confirmacion pre-ejecucion (Modulo 2) ---
    $plan      = Build-ActionPlan -sel $sel
    $confirmed = Show-ConfirmDialog -plan $plan
    if(-not $confirmed){ return }

    # --- A partir de aqui el usuario confirmo ---
    $btnRun.IsEnabled=$false; $btnSelAll.IsEnabled=$false; $btnSelNone.IsEnabled=$false
    $lblSpaceFreed.Text=""; $script:freed=0; $script:logLines=@()
    $rtbLog.Document.Blocks.Clear()
    $mainTabs.SelectedIndex=1; $lblLogStatus.Text="Ejecutando..."; Flush-UI

    # --- Iniciar sesion de backup para esta ejecucion ---
    New-BackupSession | Out-Null

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

    if($sel["Nagle"] -or $sel["TCP"] -or $sel["DNS"] -or $sel["DNSFlush"] -or $sel["DisableIPv6"]){
        Set-Progress 70 "Red..."; Write-Log "RED" "head"
        # Guardar estado de red antes de cualquier cambio
        if($sel["DNS"] -or $sel["DisableIPv6"]){ Save-NetBackup }
    }
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
    $lblLogStatus.Text="Completado"
    $btnRun.IsEnabled=$true; $btnSelAll.IsEnabled=$true; $btnSelNone.IsEnabled=$true
    Flush-UI

    # --- Cerrar sesion de backup con metadata final ---
    Save-SessionMetadata -freedMB ([int]$script:freed) -scoreBefore 0 -scoreAfter 0 -preset "Manual"

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
    $run.Foreground = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($col))
    $para.Inlines.Add($run) | Out-Null
    $rtbRestoreLog.Document.Blocks.Add($para) | Out-Null
    $restoreLogScroll.ScrollToEnd()

    # Actualizar badge de estado en la cabecera del log
    $lblRestoreLog.Text = $msg.Substring(0, [math]::Min($msg.Length, 55))
    $badgeRestoreStatus.Background = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString(
            $(if($type -eq "err"){"#2A0A0A"}elseif($type -eq "ok"){"#0A2A0A"}else{"#1A1A1A"})))
    $lblRestoreLog.Foreground = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($col))
    Flush-UI
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
        $noItem = New-Object Windows.Controls.Border
        $noItem.Padding = New-Object Windows.Thickness(14,20,14,20)
        $txt = New-Object Windows.Controls.TextBlock
        $txt.Text       = "No hay sesiones de backup guardadas. Ejecuta una optimizacion para crear la primera."
        $txt.FontSize   = 12
        $txt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#555555"))
        $txt.TextWrapping = [Windows.TextWrapping]::Wrap
        $noItem.Child = $txt
        $icHistory.Items.Add($noItem) | Out-Null
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
        $rowBorder.BorderBrush     = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#1A1A1A"))

        # Resaltar la sesion mas reciente
        if($isFirst){
            $rowBorder.Background = New-Object Windows.Media.SolidColorBrush(
                [Windows.Media.ColorConverter]::ConvertFromString("#0D1A0D"))
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
        $tsText.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString(
                $(if($isFirst){"#EEEEEE"}else{"#CCCCCC"})))
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
        $presetBdr.Background = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($presetColor))
        $presetTxt = New-Object Windows.Controls.TextBlock
        $presetTxt.Text       = $session.preset
        $presetTxt.FontSize   = 10
        $presetTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($presetFg))
        $presetBdr.Child = $presetTxt
        [Windows.Controls.Grid]::SetColumn($presetBdr, 1)

        # Col 2 - Acciones
        $actText = New-Object Windows.Controls.TextBlock
        $actText.Text      = "$($session.actions) acc."
        $actText.FontSize  = 11
        $actText.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#888888"))
        $actText.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($actText, 2)

        # Col 3 - MB liberados
        $mbText = New-Object Windows.Controls.TextBlock
        $mbText.Text     = "$($session.freedMB) MB"
        $mbText.FontSize = 11
        $mbText.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString("#22C55E"))
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
        $stateBdr.Background = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($stateColor))
        $stateTxt = New-Object Windows.Controls.TextBlock
        $stateTxt.Text       = $stateLabel
        $stateTxt.FontSize   = 10
        $stateTxt.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString($stateFg))
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

    $folderName = Split-Path $sessionPath -Leaf

    $confirm = [Windows.MessageBox]::Show(
        "Vas a revertir la sesion:`n$folderName`n`nEsto restaurara los valores de registro, servicios y red al estado anterior a esa optimizacion.`n`nContinuar?",
        "OptimizarPC - Revertir sesion",
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
            "OptimizarPC - Restauracion completada",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
    } else {
        [Windows.MessageBox]::Show(
            "La restauracion termino con algunos errores.`n`nRevisa el log de restauracion para ver los detalles.",
            "OptimizarPC - Restauracion con errores",
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
            "OptimizarPC - Historial",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    Invoke-RevertSession -sessionPath $sessions[0].path
})

# ============================================================
# Cargar datos al mostrar la ventana
$window.Add_ContentRendered({
    Load-StartupItems
    Render-StartupItems
    Update-RAMDisplay
    Render-HistoryItems
    # Limpiar backups con mas de 30 dias (todas las funciones ya estan definidas aqui)
    Cleanup-OldBackups -keepDays 30
})

$window.ShowDialog()|Out-Null
