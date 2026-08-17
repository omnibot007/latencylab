# LatencyLab — Installation Guide

## Prerequisites

- Windows 10 (build 19045 or later) or Windows 11
- PowerShell 5.1+ (built-in)
- Administrator access
- NVIDIA GPU (for GPU-specific tweaks)
- Intel I225-V NIC (for RSS tweaks — other NICs will skip this)

## Step-by-step

### 1. Download the repo

```powershell
git clone https://github.com/omnibot007/latencylab.git C:\LatencyLab\repo
```

Or download as ZIP and extract.

### 2. (Optional) Measure your upload bandwidth

The QoS upload shaper needs your actual upload speed to work correctly.
The default is 18 Mbps (based on a 20 Mbps measured connection).

```powershell
cd C:\LatencyLab\repo
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-upload-speed.ps1
```

Note the "Recommended QoS shaper" value from the output.

### 3. Apply all tweaks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply.ps1
```

Or with custom upload bandwidth:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply.ps1 -UploadBandwidthMbps 25
```

Or with Wi-Fi disabled (if you only use Ethernet):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply.ps1 -DisableWifi
```

### 4. REBOOT

This is required for:
- Kernel timer changes (GlobalTimerResolutionRequests, DistributeTimers, CoalescingTimerInterval)
- GPU changes (DisableDynamicPstate, MPO, VRR keys, GpuEnergyDrv)
- NIC changes (RSS, interrupt moderation)
- USB changes (power management, selective suspend)
- BCD changes (disabledynamictick)
- NTFS changes (memoryusage, 8dot3)

### 5. Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1
```

All checks should report OK. Any FAIL indicates a tweak that didn't stick
(usually because a driver update reset it — the boot task will re-assert on next logon).

### 6. Configure Fortnite

Close Fortnite and Epic Games Launcher completely, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\set-fortnite-config.ps1
```

This sets:
- 1600x900 @ 100% resolution (native, no upscale)
- Performance Mode (es31)
- All low settings except View Distance (Epic)
- Audio Quality Low
- Lobby FPS cap 60
- VSync off, Motion Blur off, HDR off
- NVIDIA Reflex On+Boost (verify in-game)

### 7. Verify in-game

Launch Fortnite and check:
- Settings → Video → Performance Mode is selected
- 3D Resolution shows 100%
- Frame Rate Limit shows Unlimited
- NVIDIA Reflex shows "On + Boost"
- Audio Quality shows Low

## What happens at boot

The `LatencyLab-Boot` scheduled task runs automatically at every logon:
1. Re-asserts all registry tweaks (in case Windows/driver updates reset them)
2. Re-disables telemetry scheduled tasks (Windows re-enables some after updates)
3. Disables NVIDIA bloat directories (ShadowPlay, NvTelemetry)
4. Starts the timer resolution process (SetTimerResolution.exe at 0.5ms)
5. Pins background processes to E-cores
6. Detects Fortnite launch → closes Spotify, tightens monitoring
7. Detects Fortnite exit → relaxes monitoring

## SetTimerResolution.exe

The timer resolution tweak requires `SetTimerResolution.exe` in a `tools\` subdirectory.
Download it from: https://github.com/microsoft/TimerResolution (or similar source)
Place at: `C:\LatencyLab\repo\tools\SetTimerResolution.exe`

If not found, the timer task is skipped but all other tweaks still apply.

## Customizing for your hardware

### CPU with no E-cores (e.g., AMD Ryzen)

Edit `boot.ps1` and remove or adjust the E-core affinity section.
On AMD CPUs all cores are equal — background pinning is unnecessary.

### Different GPU

The GPU tweaks target NVIDIA specifically (DisableDynamicPstate, nvlddmkm, VRR keys).
AMD GPUs will skip these automatically (the registry keys won't match).

### Different NIC

The RSS fix is specific to Intel I225-V. Other NICs:
- Check if RSS is enabled: `Get-NetAdapterRSS -Name Ethernet`
- If not, enable it: `Set-NetAdapterRSS -Name Ethernet -Enabled $true -NumberOfReceiveQueues 4`
- The AFD/TCP buffer tweaks apply to all NICs

### Different monitor refresh rate

If you're not on 500Hz, the VRR latency keys and timer resolution may be less impactful.
They're still safe to apply — just less noticeable.

## Reverting

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\revert.ps1
```

Then reboot. Everything goes back to Windows defaults.

## Troubleshooting

### "Access denied" errors
Run PowerShell as Administrator. Right-click → Run as Administrator.

### QoS policy not applying
Check: `Get-NetQosPolicy -Name 'FN-UploadShaper' -PolicyStore 'localhost'`
If missing, re-run apply.ps1 or the boot task will recreate it at next logon.

### RSS not working after driver update
Driver updates can reset NIC registry keys. Reboot (the boot task re-asserts them)
or run: `Set-NetAdapterRSS -Name Ethernet -Enabled $true -NumberOfReceiveQueues 4 -Profile NUMAStatic`

### Fortnite INI keeps reverting
Fortnite rewrites GameUserSettings.ini on exit. Edit it only when Fortnite is closed.
The apply script checks for this. If you change settings in-game, they'll overwrite the file.

### Black screen / flicker after MPO disable
MPO disable (OverlayTestMode=5) is a fix for flickering, but if it causes issues:
```
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode' -Force
```
Then reboot.
