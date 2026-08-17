<#
.SYNOPSIS
    LatencyLab boot script — runs at every logon via scheduled task.
    Re-asserts registry tweaks and manages background process affinity.

.DESCRIPTION
    Registered by apply.ps1 as 'LatencyLab-Boot' scheduled task.
    Runs hidden at logon and stays resident.

    ALWAYS:
      * Re-asserts all registry tweaks (Windows/driver updates can reset them)
      * Re-disables telemetry scheduled tasks
      * Disables NVIDIA bloat directories (when files aren't in use)
      * Starts timer resolution task if not running
      * Pins background processes to E-cores

    ON FORTNITE LAUNCH (auto-detected):
      * Closes Spotify
      * Tightens affinity loop to 5s
      * Monitors downlink saturation

    ON FORTNITE EXIT:
      * Relaxes loop to 15s
#>
$ErrorActionPreference = 'Continue'
$log = "$env:LOCALAPPDATA\LatencyLab\logs\boot.log"
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
if ((Test-Path $log) -and (Get-Item $log).Length -gt 2MB) { Set-Content $log '' }
function Log { param($m) "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Add-Content $log }

Log '--- boot task start ---'

# --- Start timer resolution ---
try {
    if (-not (Get-Process SetTimerResolution -ErrorAction SilentlyContinue)) {
        Start-ScheduledTask -TaskName 'LatencyLab-TimerResolution' -ErrorAction Stop
        Log 'started timer task'
    }
} catch { Log "timer FAILED: $($_.Exception.Message)" }

# --- Re-assert ALL registry tweaks ---
try {
    function Set-Reg { param($Path,$Name,$Value,$Type='DWord')
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty $Path -Name $Name -Value $Value -Type $Type -Force -EA SilentlyContinue
    }

    # Scheduler
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 36
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NoLazyMode' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10

    # Timer
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' 1
    @('kernel','Power','Memory Management','Executive','') | ForEach-Object {
        $p = if ($_ -ne '') { "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\$_" } else { 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' }
        Set-Reg $p 'CoalescingTimerInterval' 0
    }
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'CoalescingTimerInterval' 0
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'CoalescingTimerInterval' 0

    # GPU
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' 'Start' 4
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'RmGpsPsEnablePerCpuCoreDpc' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'VsyncIdleTimeout' 0
    $nvClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $nvClass -EA SilentlyContinue | ForEach-Object {
        $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc
        if ($desc -like '*NVIDIA*') {
            Set-Reg $_.PSPath 'DisableDynamicPstate' 1
            foreach ($k in 'LOWLATENCY','Node3DLowLatency','D3PCLatency','TransitionLatency','vrrCursorMarginUs','vrrDeflickerMarginUs','vrrDeflickerMaxUs') { Set-Reg $_.PSPath $k 1 }
        }
    }
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm' 'Display%MonitorAmount%_PipeOptimizationEnable' 1
    $fts = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'
    if (Test-Path $fts) { Set-Reg $fts 'EnableRID44231' 0; Set-Reg $fts 'EnableRID64640' 0; Set-Reg $fts 'EnableRID66610' 0 }

    # Network — RSS for I225-V
    $netClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
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

    # QoS shaper
    Remove-NetQosPolicy -Name 'FN-UploadShaper' -PolicyStore 'localhost' -Confirm:$false -EA SilentlyContinue
    New-NetQosPolicy -Name 'FN-UploadShaper' -Default -ThrottleRateActionBitsPerSecond 18000000 -PolicyStore 'localhost' -EA SilentlyContinue | Out-Null

    # AFD / TCP
    $afd = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
    Set-Reg $afd 'DefaultReceiveWindow' 16384; Set-Reg $afd 'DefaultSendWindow' 16384
    Set-Reg $afd 'FastCopyReceiveThreshold' 16384; Set-Reg $afd 'FastSendDatagramThreshold' 16384
    Set-Reg $afd 'DynamicSendBufferDisable' 0; Set-Reg $afd 'IgnorePushBitOnReceives' 1; Set-Reg $afd 'NonBlockingSendSpecialBuffering' 1
    $tcp = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-Reg $tcp 'FastCopyReceiveThreshold' 16384; Set-Reg $tcp 'FastSendDatagramThreshold' 16384
    Set-Reg $tcp 'DelayedAckFrequency' 1; Set-Reg $tcp 'DelayedAckTicks' 1
    $sp = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'
    Set-Reg $sp 'LocalPriority' 4; Set-Reg $sp 'HostsPriority' 5; Set-Reg $sp 'DnsPriority' 6; Set-Reg $sp 'NetbtPriority' 7
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' 'TimerResolution' 1

    # IFEO
    $ifeoFn = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FortniteClient-Win64-Shipping.exe\PerfOptions'
    Set-Reg $ifeoFn 'CpuPriorityClass' 3; Set-Reg $ifeoFn 'IoPriority' 3; Set-Reg $ifeoFn 'PagePriority' 5
    $ifeoCsrss = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions'
    Set-Reg $ifeoCsrss 'CpuPriorityClass' 3; Set-Reg $ifeoCsrss 'IoPriority' 3

    # MMCSS tasks
    $g = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    Set-Reg $g 'Priority' 6; Set-Reg $g 'GPU Priority' 8
    $dpp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\DisplayPostProcessing'
    Set-Reg $dpp 'Priority' 8; Set-Reg $dpp 'GPU Priority' 18; Set-Reg $dpp 'Latency Sensitive' 'True' 'String'

    # Memory / FS
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NTFSDisable8dot3NameCreation' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMftZoneReservation' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'ContigFileAllocSize' 100

    # Telemetry / bloat
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FTH' 'Enabled' 0
    Set-Reg 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowFullControl' 0

    # Display / desktop
    $gcs = 'HKCU:\System\GameConfigStore'
    Set-Reg $gcs 'GameDVR_Enabled' 0; Set-Reg $gcs 'GameDVR_FSEBehaviorMode' 2; Set-Reg $gcs 'GameDVR_DSEBehavior' 2
    Set-Reg $gcs 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg $gcs 'GameDVR_DXGIHonorFSEWindowsCompatible' 1; Set-Reg $gcs 'GameDVR_EFSEFeatureFlags' 0
    $gb = 'HKCU:\Software\Microsoft\GameBar'
    Set-Reg $gb 'AutoGameModeEnabled' 1; Set-Reg $gb 'UseNexusForGameBarEnabled' 0; Set-Reg $gb 'ShowStartupPanel' 0
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Multimedia\Audio' 'UserDuckingPreference' 3
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DelayedDesktopSwitchTimeout' 0

    # Kill timeouts
    Set-Reg 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'LowLevelHooksTimeout' '1000' 'String'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' 2000

    Log 're-asserted all registry tweaks'
} catch { Log "registry re-assert FAILED: $($_.Exception.Message)" }

# --- Re-disable telemetry tasks ---
try {
    $telTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
        '\Microsoft\Windows\Feedback\Siuf\DmClient','\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting','\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\DiskFootprint\Diagnostics','\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
        '\Microsoft\Windows\Shell\FamilySafetyMonitor','\Microsoft\Windows\Shell\FamilySafetyRefreshTask'
    )
    $td = 0
    foreach ($t in $telTasks) {
        $tn = $t.Split('\')[-1]; $tp = $t.Substring(0, $t.LastIndexOf('\')) + '\'
        $task = Get-ScheduledTask -TaskName $tn -TaskPath $tp -EA SilentlyContinue
        if ($task -and $task.State -ne 'Disabled') { Disable-ScheduledTask -TaskName $tn -TaskPath $tp -EA SilentlyContinue | Out-Null; $td++ }
    }
    if ($td -gt 0) { Log "disabled $td telemetry task(s)" }
} catch { Log "telemetry task disable FAILED: $($_.Exception.Message)" }

# --- Disable NVIDIA bloat directories ---
try {
    $sp = 'C:\Program Files\NVIDIA Corporation\NVIDIA App\ShadowPlay'
    if (Test-Path $sp) { Rename-Item $sp -NewName 'ShadowPlay.disabled' -Force -EA SilentlyContinue }
    $nt = 'C:\Program Files\NVIDIA Corporation\NvTelemetry'
    if (Test-Path $nt) { Rename-Item $nt -NewName 'NvTelemetry.disabled' -Force -EA SilentlyContinue }
} catch { Log "NVIDIA bloat disable FAILED: $($_.Exception.Message)" }

# --- Background affinity watcher ---
# E-cores = logical 16-31 on i9-13900KF. Adjust for your CPU.
# 0xFFFF0000 as signed Int64 for PowerShell.
$E_CORES = [IntPtr][int64]4294901760

$targets = @(
    'Discord','discord_clips','DiscordSystemHelper','Spotify','Notion',
    'steam','steamwebhelper','steamservice','EpicWebHelper','Voicemod',
    'antimicrox','msedge','chrome','firefox','RtkAudUService64',
    'SearchIndexer','OneDrive','RustDesk'
)

# NEVER pin these — display pipeline, audio, controller, or focus-stealing
$NEVER_PIN = @(
    'nvcontainer','NVDisplay.Container','nvsphelper64','NVIDIA Share','NVIDIA Web Helper',
    'nvcplui','nvtelemetrycontainer','dwm','audiodg','csrss','winlogon','explorer',
    'GameInputSvc','GameInputRedistService','EpicGamesLauncher'
)
$targets = $targets | Where-Object { $NEVER_PIN -notcontains $_ }

$GAME = 'FortniteClient-Win64-Shipping'
Log "watcher start (targets=$($targets.Count))"
$inGame = $false; $interval = 15

while ($true) {
    $running = [bool](Get-Process -Name $GAME -ErrorAction SilentlyContinue)
    if ($running -and -not $inGame) {
        $inGame = $true; $interval = 5
        Log 'FORTNITE DETECTED -> game mode on'
        $sp = Get-Process Spotify -EA SilentlyContinue
        if ($sp) { $sp | Stop-Process -Force -EA SilentlyContinue; Log "closed Spotify" }
    } elseif (-not $running -and $inGame) {
        $inGame = $false; $interval = 15
        Log 'Fortnite exited -> game mode off'
    }

    # Pin background processes to E-cores
    $n = 0
    foreach ($p in (Get-Process -EA SilentlyContinue | Where-Object { $targets -contains $_.Name })) {
        if ($p.ProcessorAffinity -ne $E_CORES) { try { $p.ProcessorAffinity = $E_CORES; $n++ } catch {} }
    }
    if ($n -gt 0) { Log "pinned $n process(es) to E-cores" }

    Start-Sleep -Seconds $interval
}
