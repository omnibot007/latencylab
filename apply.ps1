<#
.SYNOPSIS
    Apply ALL LatencyLab tweaks. Run as Administrator.

.DESCRIPTION
    Applies every tweak in the LatencyLab pack:
    - Timer resolution (SetTimerResolution + registry)
    - CPU scheduler (Win32PrioritySeparation, PowerThrottling, MMCSS)
    - GPU / NVIDIA (DisableDynamicPstate, MPO, VRR, telemetry, bloat)
    - Network (I225-V RSS, AFD buffers, TCP, QoS shaper)
    - USB / Controller (power management off, selective suspend off)
    - Fortnite IFEO priority
    - Windows telemetry / bloat / services
    - Filesystem / memory
    - Display / desktop / kill timeouts
    - Background process management (boot task)

    After running, REBOOT to bind kernel, GPU, NIC, and USB changes.

.PARAMETER UploadBandwidthMbps
    Your upload bandwidth in Mbps. QoS shaper will be set to 90% of this.
    Default: 18 (based on measured 20 Mbps). Run test-upload-speed.ps1 to measure.

.PARAMETER DisableWifi
    Disable the unused Wi-Fi adapter.

.EXAMPLE
    .\apply.ps1
    .\apply.ps1 -UploadBandwidthMbps 25
    .\apply.ps1 -DisableWifi
#>
[CmdletBinding()]
param(
    [int]$UploadBandwidthMbps = 18,
    [switch]$DisableWifi
)

$ErrorActionPreference = 'Continue'
$bar = '=' * 72
$ok = 0; $fail = 0
function Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ("  {0,-52} " -f $Name) -NoNewline
    try { & $Action; Write-Host "OK" -ForegroundColor Green; $ok++ }
    catch { Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red; $fail++ }
}
function Set-Reg { param($Path,$Name,$Value,$Type='DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty $Path -Name $Name -Value $Value -Type $Type -Force
}

# --- Admin check ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host "ERROR: Run as Administrator" -ForegroundColor Red; exit 1 }

Write-Host "`n$bar" -ForegroundColor Cyan
Write-Host ' LatencyLab — Apply ALL Tweaks' -ForegroundColor Cyan
Write-Host $bar -ForegroundColor Cyan

# === 1. TIMER RESOLUTION ===
Write-Host "`n=== 1. TIMER RESOLUTION ===" -ForegroundColor Yellow
Step "GlobalTimerResolutionRequests=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1 }
Step "DistributeTimers=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' 1 }
Step "CoalescingTimerInterval=0 (all paths)" {
    @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Power',
      'HKLM:\SYSTEM\CurrentControlSet\Control') | ForEach-Object {
        Set-Reg $_ 'CoalescingTimerInterval' 0
    }
}
Step "BCD disabledynamictick=yes" { bcdedit /set disabledynamictick yes | Out-Null }

# === 2. CPU SCHEDULER ===
Write-Host "`n=== 2. CPU SCHEDULER ===" -ForegroundColor Yellow
Step "Win32PrioritySeparation=36" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 36 }
Step "PowerThrottlingOff=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
Step "NoLazyMode=1" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NoLazyMode' 1 }
Step "SystemResponsiveness=0" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0 }
Step "NetworkThrottlingIndex=10" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10 }

# === 3. GPU / NVIDIA ===
Write-Host "`n=== 3. GPU / NVIDIA ===" -ForegroundColor Yellow
$nvClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$nvKey = $null
Get-ChildItem $nvClass -EA SilentlyContinue | ForEach-Object {
    $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
    if ($desc -like '*NVIDIA*') { $script:nvKey = $_.PSPath }
}
Step "DisableDynamicPstate=1" { Set-Reg $nvKey 'DisableDynamicPstate' 1 }
Step "RmGpsPsEnablePerCpuCoreDpc=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'RmGpsPsEnablePerCpuCoreDpc' 1 }
Step "GpuEnergyDrv disabled" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' 'Start' 4 }
Step "MPO disabled (OverlayTestMode=5)" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 }
Step "VsyncIdleTimeout=0" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'VsyncIdleTimeout' 0 }
Step "GPU VRR latency keys" {
    $vrrKeys = @('LOWLATENCY','Node3DLowLatency','D3PCLatency','TransitionLatency','vrrCursorMarginUs','vrrDeflickerMarginUs','vrrDeflickerMaxUs')
    foreach ($k in $vrrKeys) { Set-Reg $nvKey $k 1 }
}
Step "nvlddmkm PipeOptimization=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm' 'Display%MonitorAmount%_PipeOptimizationEnable' 1 }
Step "NVIDIA telemetry registry=0" {
    $fts = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'
    if (Test-Path $fts) {
        Set-Reg $fts 'EnableRID44231' 0; Set-Reg $fts 'EnableRID64640' 0; Set-Reg $fts 'EnableRID66610' 0
    }
    Set-Reg 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0
}

# === 4. NETWORK (I225-V) ===
Write-Host "`n=== 4. NETWORK (Intel I225-V) ===" -ForegroundColor Yellow
$netClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
Step "I225-V RSS registry keys" {
    Get-ChildItem $netClass -EA SilentlyContinue | ForEach-Object {
        $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
        if ($desc -like '*I225*') {
            Set-ItemProperty $_.PSPath -Name '*RSS' -Value '1' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*NumRssQueues' -Value '4' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*RSSProfile' -Value '4' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*RssBaseProcNumber' -Value '0' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*MaxRssProcessors' -Value '4' -Type String -Force
        }
    }
}
Step "Set-NetAdapterRSS" {
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*I225*' -and $_.Status -eq 'Up' } | Select-Object -First 1
    if ($adapter) { Set-NetAdapterRSS -Name $adapter.Name -Enabled $true -NumberOfReceiveQueues 4 -Profile NUMAStatic -EA Stop }
}
Step "NIC Interrupt Moderation=Disabled" { Set-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword '*InterruptModeration' -RegistryValue 0 -NoRestart -EA SilentlyContinue }
Step "NIC Flow Control=Disabled" { Set-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword '*FlowControl' -RegistryValue 0 -NoRestart -EA SilentlyContinue }
Step "NIC Receive Buffers=1024" { Set-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword 'ReceiveBuffers' -RegistryValue 1024 -NoRestart -EA SilentlyContinue }
Step "NIC Transmit Buffers=1024" { Set-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword 'TransmitBuffers' -RegistryValue 1024 -NoRestart -EA SilentlyContinue }
Step "Wake on LAN disabled" { Set-NetAdapterPowerManagement -Name Ethernet -WakeOnMagicPacket Disabled -WakeOnPattern Disabled -EA SilentlyContinue }
Step "Global RSC disabled" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -EA SilentlyContinue }
Step "Psched TimerResolution=1" { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' 'TimerResolution' 1 }
Step "TCP InitialRto=1000ms" {
    Set-NetTCPSetting -SettingName InternetCustom -InitialRtoMs 1000 -EA SilentlyContinue
    Set-NetTCPSetting -SettingName Internet -InitialRtoMs 1000 -EA SilentlyContinue
}
if ($DisableWifi) { Step "Disable Wi-Fi adapter" { Disable-NetAdapter -Name 'Wi-Fi' -Confirm:$false -EA Stop } }

# === 5. AFD / WINSOCK / TCP REGISTRY ===
Write-Host "`n=== 5. AFD / WINSOCK / TCP ===" -ForegroundColor Yellow
Step "AFD Winsock buffers" {
    $afd = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
    Set-Reg $afd 'DefaultReceiveWindow' 16384; Set-Reg $afd 'DefaultSendWindow' 16384
    Set-Reg $afd 'FastCopyReceiveThreshold' 16384; Set-Reg $afd 'FastSendDatagramThreshold' 16384
    Set-Reg $afd 'DynamicSendBufferDisable' 0; Set-Reg $afd 'IgnorePushBitOnReceives' 1
    Set-Reg $afd 'NonBlockingSendSpecialBuffering' 1
}
Step "TCP fast path thresholds" {
    $tcp = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-Reg $tcp 'FastCopyReceiveThreshold' 16384; Set-Reg $tcp 'FastSendDatagramThreshold' 16384
    Set-Reg $tcp 'DelayedAckFrequency' 1; Set-Reg $tcp 'DelayedAckTicks' 1
}
Step "TCP ServiceProvider priorities" {
    $sp = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'
    Set-Reg $sp 'LocalPriority' 4; Set-Reg $sp 'HostsPriority' 5
    Set-Reg $sp 'DnsPriority' 6; Set-Reg $sp 'NetbtPriority' 7
}

# === 6. QoS UPLOAD SHAPER ===
Write-Host "`n=== 6. QoS UPLOAD SHAPER ===" -ForegroundColor Yellow
$qosRate = [int]($UploadBandwidthMbps * 1000000)
Step "QoS FN-UploadShaper=$UploadBandwidthMbps Mbps" {
    Remove-NetQosPolicy -Name 'FN-UploadShaper' -PolicyStore 'localhost' -Confirm:$false -EA SilentlyContinue
    New-NetQosPolicy -Name 'FN-UploadShaper' -Default -ThrottleRateActionBitsPerSecond $qosRate -PolicyStore 'localhost' -EA Stop | Out-Null
}

# === 7. USB / CONTROLLER ===
Write-Host "`n=== 7. USB / CONTROLLER ===" -ForegroundColor Yellow
Step "USB device power management OFF" {
    $n = 0
    Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -EA SilentlyContinue | ForEach-Object {
        $inst = $_.InstanceName -replace '_0$',''
        $dev = Get-PnpDevice -InstanceId $inst -EA SilentlyContinue
        if ($dev -and $dev.Class -in 'USB','HIDClass','XboxComposite','Bluetooth' -and $_.Enable) {
            try { $_.Enable = $false; Set-CimInstance -InputObject $_ -EA Stop; $n++ } catch {}
        }
    }
    Write-Host "($n devices) " -NoNewline
}
Step "USB selective suspend registry=0" {
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -EA SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.PSPath -EA SilentlyContinue | ForEach-Object {
            $dp = Join-Path $_.PSPath 'Device Parameters'
            if (Test-Path $dp) {
                foreach ($n in 'EnhancedPowerManagementEnabled','SelectiveSuspendEnabled','AllowIdleIrpInD3','DeviceSelectiveSuspended','SelectiveSuspendOn') {
                    if ($null -ne (Get-ItemProperty $dp -Name $n -EA SilentlyContinue).$n) {
                        Set-ItemProperty $dp -Name $n -Value 0 -Type DWord -EA SilentlyContinue
                    }
                }
            }
        }
    }
}
Step "USB DisableSelectiveSuspend=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\USB' 'DisableSelectiveSuspend' 1 }
$scheme = ((powercfg /getactivescheme) -split '\s+')[3]
Step "USB selective suspend (power plan)=0" {
    powercfg /setacvalueindex $scheme '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 | Out-Null
    powercfg /setactive $scheme | Out-Null
}

# === 8. FORTNITE IFEO ===
Write-Host "`n=== 8. FORTNITE IFEO ===" -ForegroundColor Yellow
$ifeoFn = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FortniteClient-Win64-Shipping.exe\PerfOptions'
Step "Fortnite IFEO CpuPriorityClass=3" { Set-Reg $ifeoFn 'CpuPriorityClass' 3 }
Step "Fortnite IFEO IoPriority=3" { Set-Reg $ifeoFn 'IoPriority' 3 }
Step "Fortnite IFEO PagePriority=5" { Set-Reg $ifeoFn 'PagePriority' 5 }
$ifeoCsrss = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions'
Step "csrss IFEO CpuPriorityClass=3" { Set-Reg $ifeoCsrss 'CpuPriorityClass' 3 }
Step "csrss IFEO IoPriority=3" { Set-Reg $ifeoCsrss 'IoPriority' 3 }

# === 9. MMCSS TASKS ===
Write-Host "`n=== 9. MMCSS TASKS ===" -ForegroundColor Yellow
$mmcssBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks'
Step "Games task (Priority=6, GPU=8)" {
    $g = "$mmcssBase\Games"
    Set-Reg $g 'Affinity' 0; Set-Reg $g 'Background Only' 'False' 'String'
    Set-Reg $g 'Clock Rate' 10000; Set-Reg $g 'GPU Priority' 8; Set-Reg $g 'Priority' 6
    Set-Reg $g 'Scheduling Category' 'High' 'String'; Set-Reg $g 'SFIO Priority' 'High' 'String'
}
Step "DisplayPostProcessing (Priority=8, GPU=18)" {
    $d = "$mmcssBase\DisplayPostProcessing"
    Set-Reg $d 'Affinity' 0; Set-Reg $d 'Background Only' 'True' 'String'
    Set-Reg $d 'BackgroundPriority' 24; Set-Reg $d 'Clock Rate' 10000
    Set-Reg $d 'GPU Priority' 18; Set-Reg $d 'Priority' 8
    Set-Reg $d 'Scheduling Category' 'High' 'String'; Set-Reg $d 'SFIO Priority' 'High' 'String'
    Set-Reg $d 'Latency Sensitive' 'True' 'String'
}

# === 10. WINDOWS TELEMETRY / BLOAT ===
Write-Host "`n=== 10. WINDOWS TELEMETRY / BLOAT ===" -ForegroundColor Yellow
Step "AllowTelemetry=0" { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 }
Step "AdvertisingInfo=0" { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 }
Step "TailoredExperiences=0" { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 }
Step "BingSearchEnabled=0" { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 }
Step "DisableWindowsConsumerFeatures=1" { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 }
Step "DisableConsumerAccountStateContent=1" { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1 }
Step "Background apps disabled" { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 }
Step "SilentInstalledAppsEnabled=0" { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0 }
Step "Fault Tolerant Heap disabled" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FTH' 'Enabled' 0 }
Step "WerSvc disabled" { Stop-Service WerSvc -Force -EA SilentlyContinue; Set-Service WerSvc -StartupType Disabled -EA Stop }
Step "TrkWks disabled" { Stop-Service TrkWks -Force -EA SilentlyContinue; Set-Service TrkWks -StartupType Disabled -EA Stop }
Step "Hibernation off" { powercfg /h off }
Step "Remote Assistance disabled" {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowFullControl' 0
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
}
Step "Maps auto-update=0" { Set-Reg 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' 0 }
Step "Push toasts off" {
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'LockScreenToastEnabled' 0
}
Step "DisableAutomaticRestartSignOn=1" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' 1 }

# Telemetry scheduled tasks
Write-Host "`n  Disabling telemetry scheduled tasks..." -ForegroundColor DarkGray
$telTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask'
)
$td = 0
foreach ($t in $telTasks) {
    $tn = $t.Split('\')[-1]; $tp = $t.Substring(0, $t.LastIndexOf('\')) + '\'
    $task = Get-ScheduledTask -TaskName $tn -TaskPath $tp -EA SilentlyContinue
    if ($task -and $task.State -ne 'Disabled') { Disable-ScheduledTask -TaskName $tn -TaskPath $tp -EA SilentlyContinue | Out-Null; $td++ }
}
Write-Host "  Disabled $td telemetry task(s)" -ForegroundColor Green

# === 11. FILESYSTEM / MEMORY ===
Write-Host "`n=== 11. FILESYSTEM / MEMORY ===" -ForegroundColor Yellow
Step "DisablePagingExecutive=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1 }
Step "NTFS memoryusage=2" { fsutil behavior set memoryusage 2 | Out-Null }
Step "NTFS 8dot3=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NTFSDisable8dot3NameCreation' 1 }
Step "NtfsMftZoneReservation=1" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMftZoneReservation' 1 }
Step "ContigFileAllocSize=100" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'ContigFileAllocSize' 100 }

# === 12. DISPLAY / DESKTOP ===
Write-Host "`n=== 12. DISPLAY / DESKTOP ===" -ForegroundColor Yellow
Step "GameDVR disabled" {
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
}
Step "Fullscreen Optimizations disabled" {
    $gcs = 'HKCU:\System\GameConfigStore'
    Set-Reg $gcs 'GameDVR_FSEBehaviorMode' 2; Set-Reg $gcs 'GameDVR_FSEBehavior' 2
    Set-Reg $gcs 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg $gcs 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
    Set-Reg $gcs 'GameDVR_EFSEFeatureFlags' 0; Set-Reg $gcs 'GameDVR_DSEBehavior' 2
}
Step "GameBar (Game Mode on, overlay off)" {
    $gb = 'HKCU:\Software\Microsoft\GameBar'
    Set-Reg $gb 'AllowAutoGameMode' 1; Set-Reg $gb 'AutoGameModeEnabled' 1
    Set-Reg $gb 'UseNexusForGameBarEnabled' 0; Set-Reg $gb 'ShowStartupPanel' 0
}
Step "Audio ducking disabled" { Set-Reg 'HKCU:\SOFTWARE\Microsoft\Multimedia\Audio' 'UserDuckingPreference' 3 }
Step "Sticky Keys shortcut disabled" { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' }
Step "MenuShowDelay=0" { Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String' }
Step "DelayedDesktopSwitchTimeout=0" { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DelayedDesktopSwitchTimeout' 0 }

# === 13. KILL TIMEOUTS ===
Write-Host "`n=== 13. KILL TIMEOUTS ===" -ForegroundColor Yellow
Step "AutoEndTasks=1" { Set-Reg 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1' 'String' }
Step "HungAppTimeout=1000" { Set-Reg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000' 'String' }
Step "WaitToKillAppTimeout=2000" { Set-Reg 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String' }
Step "LowLevelHooksTimeout=1000" { Set-Reg 'HKCU:\Control Panel\Desktop' 'LowLevelHooksTimeout' '1000' 'String' }
Step "WaitToKillServiceTimeout=2000" { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' 2000 }

# === 14. DISCORD ===
Write-Host "`n=== 14. DISCORD ===" -ForegroundColor Yellow
Step "Discord CLIPS_ENABLED=false" {
    $ds = "$env:APPDATA\discord\settings.json"
    if (Test-Path $ds) {
        $s = Get-Content $ds -Raw | ConvertFrom-Json
        if ($s.PSObject.Properties.Name -notcontains 'CLIPS_ENABLED') { $s | Add-Member 'CLIPS_ENABLED' $false }
        else { $s.CLIPS_ENABLED = $false }
        if ($s.PSObject.Properties.Name -notcontains 'KARMA_ENABLED') { $s | Add-Member 'KARMA_ENABLED' $false }
        else { $s.KARMA_ENABLED = $false }
        $s | ConvertTo-Json -Depth 10 | Set-Content $ds -Force
    }
}

# === 15. NVIDIA BLOAT ===
Write-Host "`n=== 15. NVIDIA BLOAT ===" -ForegroundColor Yellow
Step "NVIDIA Virtual Audio disabled" {
    $va = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA Virtual Audio*' -or $_.FriendlyName -like '*NVVAD*' }
    if ($va) { $va | ForEach-Object { Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -EA SilentlyContinue } }
}
Step "NVIDIA App SelfUpdate task disabled" {
    $su = Get-ScheduledTask -TaskName 'NVIDIA App SelfUpdate_*' -EA SilentlyContinue
    if ($su) { $su | Disable-ScheduledTask -EA SilentlyContinue }
}
Step "ShadowPlay directory renamed" {
    $sp = 'C:\Program Files\NVIDIA Corporation\NVIDIA App\ShadowPlay'
    if (Test-Path $sp) { Rename-Item $sp -NewName 'ShadowPlay.disabled' -Force -EA SilentlyContinue }
}
Step "NvTelemetry directory renamed" {
    $nt = 'C:\Program Files\NVIDIA Corporation\NvTelemetry'
    if (Test-Path $nt) { Rename-Item $nt -NewName 'NvTelemetry.disabled' -Force -EA SilentlyContinue }
}

# === 16. BOOT TASK (persistence) ===
Write-Host "`n=== 16. BOOT TASK ===" -ForegroundColor Yellow
$bootScript = Join-Path $PSScriptRoot 'boot.ps1'
Step "Register LatencyLab-Boot task" {
    Get-ScheduledTask -TaskName 'LatencyLab-Boot' -EA SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -EA SilentlyContinue
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootScript`""
    $trg = New-ScheduledTaskTrigger -AtLogOn
    $pri = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DisallowHardTerminate
    Register-ScheduledTask -TaskName 'LatencyLab-Boot' -Action $act -Trigger $trg -Principal $pri -Settings $set -Description 'LatencyLab: re-asserts tweaks at logon + background affinity watcher' -EA Stop | Out-Null
}

# Timer resolution task
$timerExe = Join-Path $PSScriptRoot 'tools\SetTimerResolution.exe'
if (Test-Path $timerExe) {
    Step "Register LatencyLab-TimerResolution task" {
        Get-ScheduledTask -TaskName 'LatencyLab-TimerResolution' -EA SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -EA SilentlyContinue
        $a = New-ScheduledTaskAction -Execute $timerExe -Argument '--resolution 5000 --no-console'
        $t = New-ScheduledTaskTrigger -AtLogOn
        $p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName 'LatencyLab-TimerResolution' -Action $a -Trigger $t -Principal $p -Settings $s -Force -EA Stop | Out-Null
        Start-ScheduledTask -TaskName 'LatencyLab-TimerResolution' -EA SilentlyContinue
    }
} else {
    Write-Host "  [SKIP] SetTimerResolution.exe not found in tools\ - timer task not registered" -ForegroundColor DarkGray
    Write-Host "         Download it and place at: $timerExe" -ForegroundColor DarkGray
}

# === SUMMARY ===
Write-Host "`n$bar" -ForegroundColor Cyan
Write-Host " APPLY COMPLETE: $ok succeeded, $fail failed" -ForegroundColor Cyan
Write-Host " REBOOT REQUIRED for kernel, GPU, NIC, USB, and timer changes." -ForegroundColor Yellow
Write-Host " After reboot, run verify.ps1 to confirm everything." -ForegroundColor Yellow
Write-Host " Then run set-fortnite-config.ps1 (with Fortnite closed)." -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Cyan
