<#
.SYNOPSIS
    Verify ALL LatencyLab tweaks are correctly applied.

.DESCRIPTION
    Checks every tweak applied by apply.ps1 and reports OK/FAIL for each.
#>
$ErrorActionPreference = 'Continue'
$bar = '=' * 72
$ok = 0; $fail = 0
function Check {
    param([string]$Name, [scriptblock]$Test)
    Write-Host ("  {0,-52} " -f $Name) -NoNewline
    $result = & $Test
    if ($result -eq $true) { Write-Host "OK" -ForegroundColor Green; $ok++ }
    else { Write-Host "FAIL ($result)" -ForegroundColor Red; $fail++ }
}
function Get-Reg { param($Path,$Name)
    try { (Get-ItemProperty $Path -Name $Name -EA Stop).$Name } catch { $null }
}

Write-Host "`n$bar" -ForegroundColor Cyan
Write-Host ' LatencyLab — Verify ALL Tweaks' -ForegroundColor Cyan
Write-Host $bar -ForegroundColor Cyan

# 1. TIMER
Write-Host "`n=== 1. TIMER RESOLUTION ===" -ForegroundColor Yellow
Check "GlobalTimerResolutionRequests=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests') -eq 1 }
Check "DistributeTimers=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers') -eq 1 }
Check "CoalescingTimerInterval=0" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'CoalescingTimerInterval') -eq 0 }
Check "BCD disabledynamictick=yes" { (bcdedit /enum 2>&1 | Select-String 'disabledynamictick' | Select-String 'yes') -ne $null }
Check "SetTimerResolution running" { [bool](Get-Process SetTimerResolution -EA SilentlyContinue) }

# 2. CPU SCHEDULER
Write-Host "`n=== 2. CPU SCHEDULER ===" -ForegroundColor Yellow
Check "Win32PrioritySeparation=36" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation') -eq 36 }
Check "PowerThrottlingOff=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff') -eq 1 }
Check "NoLazyMode=1" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NoLazyMode') -eq 1 }
Check "SystemResponsiveness=0" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness') -eq 0 }
Check "NetworkThrottlingIndex=10" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex') -eq 10 }

# 3. GPU / NVIDIA
Write-Host "`n=== 3. GPU / NVIDIA ===" -ForegroundColor Yellow
$nvClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$nvKey = $null
Get-ChildItem $nvClass -EA SilentlyContinue | ForEach-Object {
    if ((Get-ItemProperty $_.PSPath -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc -like '*NVIDIA*') { $script:nvKey = $_.PSPath }
}
Check "DisableDynamicPstate=1" { (Get-Reg $nvKey 'DisableDynamicPstate') -eq 1 }
Check "RmGpsPsEnablePerCpuCoreDpc=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'RmGpsPsEnablePerCpuCoreDpc') -eq 1 }
Check "GpuEnergyDrv Start=4" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' 'Start') -eq 4 }
Check "OverlayTestMode=5 (MPO off)" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode') -eq 5 }
Check "VsyncIdleTimeout=0" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'VsyncIdleTimeout') -eq 0 }
Check "GPU LOWLATENCY=1" { (Get-Reg $nvKey 'LOWLATENCY') -eq 1 }
Check "nvlddmkm PipeOptimization=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm' 'Display%MonitorAmount%_PipeOptimizationEnable') -eq 1 }
$fts = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'
if (Test-Path $fts) {
    Check "NVIDIA EnableRID44231=0" { (Get-Reg $fts 'EnableRID44231') -eq 0 }
    Check "NVIDIA EnableRID64640=0" { (Get-Reg $fts 'EnableRID64640') -eq 0 }
    Check "NVIDIA EnableRID66610=0" { (Get-Reg $fts 'EnableRID66610') -eq 0 }
}

# 4. NETWORK
Write-Host "`n=== 4. NETWORK (I225-V) ===" -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*I225*' -and $_.Status -eq 'Up' } | Select-Object -First 1
if ($adapter) {
    $rss = Get-NetAdapterRSS -Name $adapter.Name -EA SilentlyContinue
    Check "RSS Enabled" { $rss.Enabled -eq $true }
    Check "RSS 4 queues" { $rss.NumberOfReceiveQueues -eq 4 }
    Check "RSS NUMAStatic" { $rss.Profile -eq 'NUMAStatic' }
}
$im = Get-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword '*InterruptModeration' -EA SilentlyContinue
Check "Interrupt Moderation=Disabled" { $im.RegistryValue -eq 0 }
$fc = Get-NetAdapterAdvancedProperty -Name Ethernet -RegistryKeyword '*FlowControl' -EA SilentlyContinue
Check "Flow Control=Disabled" { $fc.RegistryValue -eq 0 }
$rsc = Get-NetOffloadGlobalSetting -EA SilentlyContinue
Check "Global RSC=Disabled" { $rsc.ReceiveSegmentCoalescing -eq 'Disabled' }
Check "Psched TimerResolution=1" { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' 'TimerResolution') -eq 1 }
$tcp = Get-NetTCPSetting -SettingName InternetCustom -EA SilentlyContinue
Check "TCP InitialRto=1000" { $tcp.InitialRtoMs -eq 1000 }

# 5. AFD / TCP REGISTRY
Write-Host "`n=== 5. AFD / TCP ===" -ForegroundColor Yellow
Check "AFD DefaultReceiveWindow=16384" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters' 'DefaultReceiveWindow') -eq 16384 }
Check "AFD FastSendDatagramThreshold=16384" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters' 'FastSendDatagramThreshold') -eq 16384 }
Check "TCP FastSendDatagramThreshold=16384" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'FastSendDatagramThreshold') -eq 16384 }
Check "TCP DelayedAckFrequency=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DelayedAckFrequency') -eq 1 }
Check "TCP DnsPriority=6" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider' 'DnsPriority') -eq 6 }

# 6. QoS
Write-Host "`n=== 6. QoS ===" -ForegroundColor Yellow
$q = Get-NetQosPolicy -Name 'FN-UploadShaper' -PolicyStore 'localhost' -EA SilentlyContinue
Check "QoS FN-UploadShaper active" { $q -ne $null -and $q.ThrottleRateAction -gt 0 }

# 7. USB
Write-Host "`n=== 7. USB ===" -ForegroundColor Yellow
Check "USB DisableSelectiveSuspend=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\USB' 'DisableSelectiveSuspend') -eq 1 }
$scheme = ((powercfg /getactivescheme) -split '\s+')[3]
$usbSuspend = powercfg /query $scheme '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 2>&1 | Select-String 'Current AC Power Setting Index'
Check "USB selective suspend (power plan)=0" { $usbSuspend -match '0x00000000' }

# 8. FORTNITE IFEO
Write-Host "`n=== 8. FORTNITE IFEO ===" -ForegroundColor Yellow
$ifeoFn = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FortniteClient-Win64-Shipping.exe\PerfOptions'
Check "Fortnite CpuPriorityClass=3" { (Get-Reg $ifeoFn 'CpuPriorityClass') -eq 3 }
Check "Fortnite IoPriority=3" { (Get-Reg $ifeoFn 'IoPriority') -eq 3 }
Check "Fortnite PagePriority=5" { (Get-Reg $ifeoFn 'PagePriority') -eq 5 }
$ifeoCsrss = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions'
Check "csrss CpuPriorityClass=3" { (Get-Reg $ifeoCsrss 'CpuPriorityClass') -eq 3 }

# 9. MMCSS
Write-Host "`n=== 9. MMCSS ===" -ForegroundColor Yellow
$games = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
Check "Games Priority=6" { (Get-Reg $games 'Priority') -eq 6 }
Check "Games GPU Priority=8" { (Get-Reg $games 'GPU Priority') -eq 8 }
$dpp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\DisplayPostProcessing'
Check "DisplayPostProcessing Priority=8" { (Get-Reg $dpp 'Priority') -eq 8 }
Check "DisplayPostProcessing GPU=18" { (Get-Reg $dpp 'GPU Priority') -eq 18 }

# 10. TELEMETRY / BLOAT
Write-Host "`n=== 10. TELEMETRY / BLOAT ===" -ForegroundColor Yellow
Check "AllowTelemetry=0" { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry') -eq 0 }
Check "BingSearchEnabled=0" { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled') -eq 0 }
Check "DisableWindowsConsumerFeatures=1" { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures') -eq 1 }
Check "FTH Enabled=0" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FTH' 'Enabled') -eq 0 }
$wer = Get-Service WerSvc -EA SilentlyContinue
Check "WerSvc disabled" { $wer -and $wer.StartType -eq 'Disabled' }
$trk = Get-Service TrkWks -EA SilentlyContinue
Check "TrkWks disabled" { $trk -and $trk.StartType -eq 'Disabled' }
Check "Hibernation off" { (powercfg /a 2>&1) -match 'disabled' }
Check "Remote Assistance off" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowFullControl') -eq 0 }
Check "Maps auto-update=0" { (Get-Reg 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled') -eq 0 }
Check "Toasts off" { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled') -eq 0 }
Check "DisableAutomaticRestartSignOn=1" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn') -eq 1 }

# Telemetry tasks
$activeTel = Get-ScheduledTask | Where-Object {
    $_.TaskName -match 'Compat|CEIP|Consolidator|UsbCeip|KernelCeip|Appraiser|ProgramData|QueueReporting|DmClient' -and
    $_.State -ne 'Disabled' -and $_.TaskPath -like '*Microsoft*'
}
Check "Telemetry tasks disabled" { $activeTel.Count -eq 0 }

# 11. FILESYSTEM
Write-Host "`n=== 11. FILESYSTEM / MEMORY ===" -ForegroundColor Yellow
Check "DisablePagingExecutive=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive') -eq 1 }
Check "NTFS memoryusage=2" { (fsutil behavior query memoryusage 2>&1) -match '2' }
Check "NTFS 8dot3=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NTFSDisable8dot3NameCreation') -eq 1 }
Check "NtfsMftZoneReservation=1" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMftZoneReservation') -eq 1 }

# 12. DISPLAY / DESKTOP
Write-Host "`n=== 12. DISPLAY / DESKTOP ===" -ForegroundColor Yellow
Check "GameDVR_Enabled=0" { (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled') -eq 0 }
Check "GameDVR_FSEBehaviorMode=2" { (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode') -eq 2 }
Check "GameDVR_DSEBehavior=2" { (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DSEBehavior') -eq 2 }
Check "AutoGameModeEnabled=1" { (Get-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 1 }
Check "Audio ducking=3" { (Get-Reg 'HKCU:\SOFTWARE\Microsoft\Multimedia\Audio' 'UserDuckingPreference') -eq 3 }
Check "StickyKeys Flags=506" { (Get-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags') -eq '506' }
Check "MenuShowDelay=0" { (Get-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay') -eq '0' }
Check "DelayedDesktopSwitchTimeout=0" { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DelayedDesktopSwitchTimeout') -eq 0 }

# 13. KILL TIMEOUTS
Write-Host "`n=== 13. KILL TIMEOUTS ===" -ForegroundColor Yellow
Check "HungAppTimeout=1000" { (Get-Reg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout') -eq '1000' }
Check "WaitToKillServiceTimeout=2000" { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout') -eq 2000 }

# 14. BOOT TASK
Write-Host "`n=== 14. PERSISTENCE ===" -ForegroundColor Yellow
$boot = Get-ScheduledTask -TaskName 'LatencyLab-Boot' -EA SilentlyContinue
Check "LatencyLab-Boot task registered" { $boot -ne $null }
$timer = Get-ScheduledTask -TaskName 'LatencyLab-TimerResolution' -EA SilentlyContinue
Check "LatencyLab-TimerResolution task registered" { $timer -ne $null }

# 15. NVIDIA BLOAT
Write-Host "`n=== 15. NVIDIA BLOAT ===" -ForegroundColor Yellow
Check "ShadowPlay disabled" { (Test-Path 'C:\Program Files\NVIDIA Corporation\NVIDIA App\ShadowPlay.disabled') -or (-not (Test-Path 'C:\Program Files\NVIDIA Corporation\NVIDIA App\ShadowPlay')) }
Check "NvTelemetry disabled" { (Test-Path 'C:\Program Files\NVIDIA Corporation\NvTelemetry.disabled') -or (-not (Test-Path 'C:\Program Files\NVIDIA Corporation\NvTelemetry')) }

# === SUMMARY ===
Write-Host "`n$bar" -ForegroundColor Cyan
if ($fail -eq 0) { Write-Host " ALL CHECKS PASSED: $ok OK, 0 failed" -ForegroundColor Green }
else { Write-Host " RESULTS: $ok OK, $fail FAILED" -ForegroundColor Yellow }
Write-Host $bar -ForegroundColor Cyan
