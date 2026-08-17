<#
.SYNOPSIS
    Revert ALL LatencyLab tweaks. Run as Administrator.

.DESCRIPTION
    Returns the machine to its pre-LatencyLab state.
    Reboot required after running.
#>
[CmdletBinding()]
param([switch]$WhatIfOnly)

$ErrorActionPreference = 'Continue'
$bar = '=' * 72
$ok = 0; $fail = 0
function Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ("  {0,-52} " -f $Name) -NoNewline
    if ($WhatIfOnly) { Write-Host "[would revert]" -ForegroundColor DarkGray; return }
    try { & $Action; Write-Host "OK" -ForegroundColor Green; $ok++ }
    catch { Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red; $fail++ }
}
function Remove-Reg { param($Path,$Name)
    Remove-ItemProperty $Path -Name $Name -Force -EA SilentlyContinue
}

Write-Host "`n$bar" -ForegroundColor Cyan
Write-Host ' LatencyLab — Revert ALL Tweaks' -ForegroundColor Cyan
Write-Host $bar -ForegroundColor Cyan

# 1. Stop scheduled tasks first
Write-Host "`n=== 1. SCHEDULED TASKS ===" -ForegroundColor Yellow
foreach ($t in 'LatencyLab-Boot','LatencyLab-TimerResolution') {
    Step "Unregister $t" { Stop-ScheduledTask -TaskName $t -EA SilentlyContinue; Unregister-ScheduledTask -TaskName $t -Confirm:$false -EA Stop }
}
Step "Kill SetTimerResolution" { Get-Process SetTimerResolution -EA SilentlyContinue | Stop-Process -Force }

# 2. Timer
Write-Host "`n=== 2. TIMER ===" -ForegroundColor Yellow
Step "Remove GlobalTimerResolutionRequests" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' }
Step "Remove DistributeTimers" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' }
Step "Remove CoalescingTimerInterval (all)" {
    @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel','HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management','HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager','HKLM:\SYSTEM\CurrentControlSet\Control\Power','HKLM:\SYSTEM\CurrentControlSet\Control') |
      ForEach-Object { Remove-Reg $_ 'CoalescingTimerInterval' }
}
Step "BCD disabledynamictick=no" { bcdedit /set disabledynamictick no | Out-Null }

# 3. CPU Scheduler
Write-Host "`n=== 3. CPU SCHEDULER ===" -ForegroundColor Yellow
Step "Win32PrioritySeparation=38 (default)" { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38 -Type DWord -Force }
Step "Remove PowerThrottlingOff" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' }
Step "Remove NoLazyMode" { Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NoLazyMode' }
Step "SystemResponsiveness=10 (default)" { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 10 -Type DWord -Force }
Step "NetworkThrottlingIndex=10 (default)" { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 10 -Type DWord -Force }

# 4. GPU / NVIDIA
Write-Host "`n=== 4. GPU / NVIDIA ===" -ForegroundColor Yellow
$nvClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
Step "Remove DisableDynamicPstate" {
    Get-ChildItem $nvClass -EA SilentlyContinue | ForEach-Object {
        if ((Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc -like '*NVIDIA*') {
            Remove-Reg $_.PSPath 'DisableDynamicPstate'
        }
    }
}
Step "Remove RmGpsPsEnablePerCpuCoreDpc" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'RmGpsPsEnablePerCpuCoreDpc' }
Step "GpuEnergyDrv Start=3 (default)" { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' -Name 'Start' -Value 3 -Type DWord -Force }
Step "Remove OverlayTestMode (MPO)" { Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' }
Step "Remove VsyncIdleTimeout" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'VsyncIdleTimeout' }
Step "Remove GPU VRR keys" {
    Get-ChildItem $nvClass -EA SilentlyContinue | ForEach-Object {
        if ((Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc -like '*NVIDIA*') {
            foreach ($k in 'LOWLATENCY','Node3DLowLatency','D3PCLatency','TransitionLatency','vrrCursorMarginUs','vrrDeflickerMarginUs','vrrDeflickerMaxUs') {
                Remove-Reg $_.PSPath $k
            }
        }
    }
}
Step "Remove nvlddmkm PipeOptimization" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm' 'Display%MonitorAmount%_PipeOptimizationEnable' }
Step "Re-enable NVIDIA telemetry" {
    $fts = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'
    if (Test-Path $fts) { Set-ItemProperty $fts -Name 'EnableRID44231' -Value 1 -Type DWord -Force; Set-ItemProperty $fts -Name 'EnableRID64640' -Value 1 -Type DWord -Force; Set-ItemProperty $fts -Name 'EnableRID66610' -Value 1 -Type DWord -Force }
}
Step "Restore ShadowPlay directory" {
    $sp = 'C:\Program Files\NVIDIA Corporation\NVIDIA App\ShadowPlay.disabled'
    if (Test-Path $sp) { Rename-Item $sp -NewName 'ShadowPlay' -Force }
}
Step "Restore NvTelemetry directory" {
    $nt = 'C:\Program Files\NVIDIA Corporation\NvTelemetry.disabled'
    if (Test-Path $nt) { Rename-Item $nt -NewName 'NvTelemetry' -Force }
}

# 5. Network
Write-Host "`n=== 5. NETWORK ===" -ForegroundColor Yellow
Step "NIC Interrupt Moderation=Enabled" { Set-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword '*InterruptModeration' -RegistryValue 1 -NoRestart -EA SilentlyContinue }
Step "Remove Psched TimerResolution" { Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' -Recurse -Force -EA SilentlyContinue }
Step "TCP InitialRto=3000 (default)" { Set-NetTCPSetting -SettingName InternetCustom -InitialRtoMs 3000 -EA SilentlyContinue; Set-NetTCPSetting -SettingName Internet -InitialRtoMs 3000 -EA SilentlyContinue }
Step "Global RSC=Enabled" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -EA SilentlyContinue }
Step "Remove QoS shaper" { Remove-NetQosPolicy -Name 'FN-UploadShaper' -PolicyStore 'localhost' -Confirm:$false -EA SilentlyContinue }
Step "Remove AFD buffers" { Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters' -Recurse -Force -EA SilentlyContinue }
Step "Remove TCP fast path keys" {
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'FastCopyReceiveThreshold'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'FastSendDatagramThreshold'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DelayedAckFrequency'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DelayedAckTicks'
}
Step "Restore TCP ServiceProvider (default)" {
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' -Name 'LocalPriority' -Value 499 -Type DWord -Force
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' -Name 'HostsPriority' -Value 500 -Type DWord -Force
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' -Name 'DnsPriority' -Value 2000 -Type DWord -Force
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' -Name 'NetbtPriority' -Value 2001 -Type DWord -Force
}
Step "Wake on LAN=Enabled" { Set-NetAdapterPowerManagement -Name Ethernet -WakeOnMagicPacket Enabled -WakeOnPattern Enabled -EA SilentlyContinue }

# 6. USB
Write-Host "`n=== 6. USB ===" -ForegroundColor Yellow
Step "Re-enable USB device power mgmt" {
    Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -EA SilentlyContinue | ForEach-Object {
        if (-not $_.Enable) { try { $_.Enable = $true; Set-CimInstance -InputObject $_ -EA Stop } catch {} }
    }
}
Step "USB selective suspend=1 (power plan)" {
    $scheme = ((powercfg /getactivescheme) -split '\s+')[3]
    powercfg /setacvalueindex $scheme '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 1 | Out-Null
    powercfg /setactive $scheme | Out-Null
}
Step "Remove USB DisableSelectiveSuspend" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\USB' 'DisableSelectiveSuspend' }

# 7. IFEO
Write-Host "`n=== 7. IFEO ===" -ForegroundColor Yellow
Step "Remove Fortnite IFEO" { Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FortniteClient-Win64-Shipping.exe' -Recurse -Force -EA SilentlyContinue }
Step "Remove csrss IFEO" { Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe' -Recurse -Force -EA SilentlyContinue }

# 8. MMCSS
Write-Host "`n=== 8. MMCSS ===" -ForegroundColor Yellow
Step "Remove DisplayPostProcessing task" { Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\DisplayPostProcessing' -Recurse -Force -EA SilentlyContinue }

# 9. Telemetry / Bloat
Write-Host "`n=== 9. TELEMETRY / BLOAT ===" -ForegroundColor Yellow
Step "AllowTelemetry=3 (default)" { Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 3 -Type DWord -Force }
Step "AdvertisingInfo=1" { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 1 -Type DWord -Force }
Step "BingSearchEnabled=1" { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 1 -Type DWord -Force }
Step "Remove DisableWindowsConsumerFeatures" { Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' }
Step "FTH Enabled=1" { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FTH' -Name 'Enabled' -Value 1 -Type DWord -Force }
Step "WerSvc=Manual (default)" { Set-Service WerSvc -StartupType Manual -EA SilentlyContinue }
Step "TrkWks=Automatic (default)" { Set-Service TrkWks -StartupType Automatic -EA SilentlyContinue }
Step "Hibernation on" { powercfg /h on }
Step "Remote Assistance on" { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name 'fAllowFullControl' -Value 1 -Type DWord -Force }
Step "Remove Maps auto-update" { Remove-Reg 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' }
Step "Toasts on" { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'ToastEnabled' -Value 1 -Type DWord -Force }
Step "Remove DisableAutomaticRestartSignOn" { Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' }
Step "Re-enable telemetry tasks" {
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
    foreach ($t in $telTasks) {
        $tn = $t.Split('\')[-1]; $tp = $t.Substring(0, $t.LastIndexOf('\')) + '\'
        Enable-ScheduledTask -TaskName $tn -TaskPath $tp -EA SilentlyContinue | Out-Null
    }
}

# 10. Filesystem
Write-Host "`n=== 10. FILESYSTEM ===" -ForegroundColor Yellow
Step "DisablePagingExecutive=0" { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 0 -Type DWord -Force }
Step "NTFS memoryusage=1 (default)" { fsutil behavior set memoryusage 1 | Out-Null }
Step "NTFS 8dot3=2 (default)" { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'NTFSDisable8dot3NameCreation' -Value 2 -Type DWord -Force }
Step "Remove NtfsMftZoneReservation" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMftZoneReservation' }
Step "Remove ContigFileAllocSize" { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'ContigFileAllocSize' }

# 11. Display / Desktop
Write-Host "`n=== 11. DISPLAY / DESKTOP ===" -ForegroundColor Yellow
Step "GameDVR_Enabled=1" { Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 1 -Type DWord -Force }
Step "Remove FSE settings" {
    Remove-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode'
    Remove-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehavior'
    Remove-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DSEBehavior'
}
Step "Remove audio ducking" { Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Multimedia\Audio' 'UserDuckingPreference' }
Step "StickyKeys Flags=510 (default)" { Set-ItemProperty 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '510' -Type String -Force }
Step "MenuShowDelay=400 (default)" { Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '400' -Type String -Force }
Step "Remove DelayedDesktopSwitchTimeout" { Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DelayedDesktopSwitchTimeout' }

# 12. Kill timeouts
Write-Host "`n=== 12. KILL TIMEOUTS ===" -ForegroundColor Yellow
Step "Remove kill timeouts" {
    Remove-Reg 'HKCU:\Control Panel\Desktop' 'AutoEndTasks'
    Remove-Reg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout'
    Remove-Reg 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout'
    Remove-Reg 'HKCU:\Control Panel\Desktop' 'LowLevelHooksTimeout'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout'
}

# 13. Restore process affinity
Write-Host "`n=== 13. PROCESS AFFINITY ===" -ForegroundColor Yellow
Step "Restore all processes to all cores" {
    $all = [IntPtr][int64]4294967295
    $n = 0
    foreach ($p in (Get-Process -EA SilentlyContinue)) { try { if ($p.ProcessorAffinity -ne $all) { $p.ProcessorAffinity = $all; $n++ } } catch {} }
    Write-Host "($n unpinned) " -NoNewline
}

# === SUMMARY ===
Write-Host "`n$bar" -ForegroundColor Cyan
if ($WhatIfOnly) { Write-Host " DRY RUN - nothing changed" -ForegroundColor Yellow }
else { Write-Host " REVERT COMPLETE: $ok succeeded, $fail failed" -ForegroundColor Cyan; Write-Host " REBOOT REQUIRED." -ForegroundColor Yellow }
Write-Host $bar -ForegroundColor Cyan
