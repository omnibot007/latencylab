# LatencyLab - Windows + Fortnite Latency Optimization Pack

Complete, evidence-based Windows 10 + Fortnite latency and performance optimization.
Every tweak is documented with what it does, why it helps, and whether it was measured
or is theoretical.

**All changes are reversible.** Run `revert.ps1` to undo everything.

## Supported hardware

This pack has been adapted for TWO machines. The scripts auto-detect and skip
tweaks that don't apply to your hardware.

| Component | Original (desktop) | ThinkPad P15 Gen 1 (laptop) |
|---|---|---|
| OS | Windows 10 Home, build 19045 | Windows 10 Pro, build 19045 |
| CPU | Intel Core i9-13900KF (8P + 16E, 32 threads) | Intel Core i7-10750H (6P, 12 threads) |
| GPU | NVIDIA GeForce RTX 4070 (200W stock) | NVIDIA Quadro T1000 4GB (mobile, single-fan) |
| RAM | 32 GB | 32 GB |
| Monitor | MSI MPG 271Q X50 QD-OLED, 500 Hz | Lenovo LEN4183, 60 Hz, 1920x1080 |
| NIC | Intel Ethernet Controller I225-V, 2.5 Gbps | Intel Ethernet Connection (11) I219-V, 1 Gbps |
| Wi-Fi | Intel AX211 (disabled - unused) | Intel Wi-Fi 6 AX201 (kept as backup) |
| Upload | ~20 Mbps | ~10 Mbps (Comcast) |

### ThinkPad-specific adaptations

The following tweaks are SKIPPED on the ThinkPad because they are incompatible
or dangerous on that hardware:

| Tweak | Why skipped |
|---|---|
| `DisableDynamicPstate=1` | Quadro T1000 mobile single-fan - risks thermal throttling |
| GPU VRR latency keys | 60Hz panel has no VRR support |
| `nvlddmkm PipeOptimizationEnable` | Broken `%MonitorAmount%` variable in registry write |
| I225-V RSS registry keys | Wrong chip - this machine has I219-V |
| Speed & Duplex 2.5 Gbps | I219-V is 1 Gbps, not 2.5 Gbps |
| `powercfg /h off` | Laptop needs hibernation - uses `HiberbootEnabled=0` instead |
| BCD `disabledynamictick` | Already set; MaxxTopia de-recommended for mouse desync |
| Wi-Fi disable | Wi-Fi is backup connection, keep available |
| E-core pinning | i7-10750H has no E-cores (6P/12T only) |
| SetTimerResolution.exe | 60Hz panel doesn't need 0.5ms timer |
| Fortnite Reflex On+Boost | Single-fan Quadro T1000 thermal limit - use Reflex On instead |
| Fortnite 1600x900 render | Panel is 1920x1080 native - render at native |

### ThinkPad Fortnite config

The ThinkPad edition of `set-fortnite-config.ps1` sets:
- 1920x1080 @ 100% (native, no upscale)
- Performance Mode (es31)
- All low settings except View Distance (Epic)
- Audio Quality Low
- Lobby FPS cap 60
- VSync off, Motion Blur off, HDR off
- Does NOT touch FrameRateLimit or LatencyTweak2 (user's choice)

## Quick start

```powershell
# 1. Apply all tweaks (run as Administrator)
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply.ps1

# 2. Reboot (required for kernel, GPU, NIC, USB, and timer changes)

# 3. Verify everything
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1

# 4. Fortnite config (close Fortnite + Epic Games Launcher first)
powershell -NoProfile -ExecutionPolicy Bypass -File .\set-fortnite-config.ps1

# To undo everything:
powershell -NoProfile -ExecutionPolicy Bypass -File .\revert.ps1
```

## What this does NOT do

- No cheats, macros, input injectors, or memory manipulation
- No anti-cheat bypasses or kernel exploits
- No HPET/platform-clock forcing
- No Spectre/Meltdown mitigation disabling
- No UAC disabling
- No Windows Update disabling
- No third-party "FPS booster" executables
- No obfuscated scripts or unauditable binaries
- No Engine.ini edits (ban-risk file)

---

## Complete tweak inventory

### 1. Timer Resolution

| Tweak | Value | Effect |
|---|---|---|
| `SetTimerResolution.exe` | 0.5ms (5000us) | Resident process holds 0.5ms timer. Measured: Sleep STDEV -94%. |
| `GlobalTimerResolutionRequests` | 1 | Allows apps to request global timer resolution. Frame pacing at 500Hz. |
| `DistributeTimers` | 1 | Spreads timer expiration across cores. Reduces timer-interrupt contention. |
| `CoalescingTimerInterval` | 0 (all paths) | Timers fire immediately instead of being grouped for power saving. |
| BCD `disabledynamictick` | Yes | Forces constant timer, reduces DPC latency spikes. |

### 2. CPU Scheduler

| Tweak | Value | Effect |
|---|---|---|
| `Win32PrioritySeparation` | 36 | Short, fixed quantum for foreground. FrameSync measured best 1% lows. |
| `PowerThrottlingOff` | 1 | Disables background process throttling. |
| `NoLazyMode` (MMCSS) | 1 | Stops MMCSS dropping into lazy mode. |
| `SystemResponsiveness` | 0 | MMCSS gives all CPU to foreground/game. |
| `NetworkThrottlingIndex` | 10 (default) | djdallmann xperf: default gives lower NDIS DPC latency than disabled on Intel NICs. |

### 3. GPU / NVIDIA

| Tweak | Value | Effect |
|---|---|---|
| `DisableDynamicPstate` | 1 | Locks GPU at max P-state (beyond NVCP "Prefer Max Performance"). |
| `RmGpsPsEnablePerCpuCoreDpc` | 1 | Per-CPU core DPC for GPU scheduler. |
| `GpuEnergyDrv` Start | 4 (disabled) | Removes GPU energy telemetry driver overhead. |
| MPO disabled (`OverlayTestMode`) | 5 | Prevents Multiplane Overlay stutter/flicker. |
| `VsyncIdleTimeout` | 0 | Eliminates idle Vsync wait when HAGS enabled. |
| GPU VRR latency keys | 1 (all) | `LOWLATENCY`, `Node3DLowLatency`, `D3PCLatency`, `TransitionLatency`, `vrrCursorMarginUs`, `vrrDeflickerMarginUs`, `vrrDeflickerMaxUs` — minimizes VRR latency on 500Hz. |
| `nvlddmkm PipeOptimizationEnable` | 1 | NVIDIA display driver pipe optimization. |
| NVIDIA telemetry registry | 0 | `EnableRID44231`, `EnableRID64640`, `EnableRID66610`, `OptInOrOutPreference` — disables driver-level telemetry. |
| ShadowPlay directory | Renamed `.disabled` | Prevents ShadowPlay overlay from loading. |
| NvTelemetry directory | Renamed `.disabled` | Prevents NVIDIA telemetry from loading. |
| NVIDIA Virtual Audio | Disabled | Removes unused virtual audio device. |
| NVIDIA App SelfUpdate task | Disabled | Prevents NVIDIA App auto-update background task. |
| NVIDIA FrameView SDK | Uninstalled | Removes FrameView telemetry SDK. |

### 4. Network (Intel I225-V)

| Tweak | Value | Effect |
|---|---|---|
| RSS | Enabled, 4 queues | Driver failed to set registry keys. Fixed: `*RSS=1`, `*NumRssQueues=4`, `*RSSProfile=4` (NUMAStatic), `*RssBaseProcNumber=0`, `*MaxRssProcessors=4`. Network traffic distributes across cores. |
| Interrupt Moderation | Disabled | Lowest latency for UDP game traffic. |
| Flow Control | Disabled | No pause frames — immediate send. |
| Receive Buffers | 1024 | Max receive buffers. |
| Transmit Buffers | 1024 | Max transmit buffers. |
| Speed & Duplex | 2.5 Gbps Full Duplex | Auto-negotiation bypassed. |
| Checksum Offloads | Rx & Tx Enabled | CPU offload for checksums. |
| LSO V2 | Enabled | Large send offload. |
| Wake on LAN | Disabled | No WoL overhead. |
| Global RSC | Disabled | Receive Segment Coalescing off — lower latency. |
| IPv6 | Enabled on Ethernet | Kept (some Epic services use it). |
| Wi-Fi AX211 | Disabled | Unused adapter — no driver/services overhead. |
| Psched TimerResolution | 1 | QoS packet scheduler timer resolution. |
| QoS Upload Shaper | 18 Mbps | 90% of measured 20 Mbps upload. Prevents bufferbloat. |

### 5. AFD / Winsock / TCP

| Tweak | Value | Effect |
|---|---|---|
| AFD `DefaultReceiveWindow` | 16384 | Winsock receive buffer. |
| AFD `DefaultSendWindow` | 16384 | Winsock send buffer. |
| AFD `FastCopyReceiveThreshold` | 16384 | Fast copy threshold for receives. |
| AFD `FastSendDatagramThreshold` | 16384 | Fast send threshold for UDP datagrams. |
| AFD `IgnorePushBitOnReceives` | 1 | Treat all data as push — less buffering. |
| AFD `NonBlockingSendSpecialBuffering` | 1 | Faster non-blocking sends. |
| TCP `FastCopyReceiveThreshold` | 16384 | TCP fast path. |
| TCP `FastSendDatagramThreshold` | 16384 | UDP fast path. |
| TCP `DelayedAckFrequency` | 1 | Faster TCP ACKs for Epic services. |
| TCP `DelayedAckTicks` | 1 | Faster TCP ACK timing. |
| TCP `InitialRtoMs` | 1000 | Faster retransmission (default 3000ms). |
| TCP ServiceProvider priorities | Local=4, Hosts=5, DNS=6, NetBT=7 | DNS prioritized over NetBIOS. |

### 6. USB / Controller

| Tweak | Value | Effect |
|---|---|---|
| USB device power management | OFF (all HID/USB) | No selective suspend / D3 idle on input devices. Eliminates wake latency on first input after idle. |
| USB selective suspend (power plan) | 0 | Plan-level twin of per-device setting. |
| `DisableSelectiveSuspend` (registry) | 1 | Belt-and-braces registry disable. |
| USB selective suspend registry (per-device) | 0 | `EnhancedPowerManagementEnabled`, `SelectiveSuspendEnabled`, `AllowIdleIrpInD3`, `DeviceSelectiveSuspended`, `SelectiveSuspendOn` all cleared. |

### 7. Fortnite

| Tweak | Value | Effect |
|---|---|---|
| Renderer | Performance Mode (es31) | Lowest overhead renderer. |
| Resolution | 1600x900 @ 100% | 31% fewer pixels than 1440p@75%, no upscale pass. |
| FrameRateLimit | 0 (unlimited) | Matches 500Hz panel. |
| FrontendFrameRateLimit | 60 | Lobby cap — heat saving. |
| VSync | Off | No display pipeline latency. |
| Motion Blur | Off | Clearer frames. |
| Nanite | Off | Not available in Performance mode. |
| Dynamic Resolution | Off | Consistent frame times. |
| Anti-Aliasing | Disabled | No DLSS overhead in Performance mode. |
| Audio Quality | Low (0) | Saves ~1800 CPU-sec in audiodg. |
| Shadows | Off | Maximum FPS. |
| Post-Process | Off | Maximum FPS. |
| Effects | Off | Maximum FPS. |
| Foliage | Off | Maximum FPS. |
| View Distance | Epic (3) | Competitive visibility — see distant players. |
| NVIDIA Reflex | On + Boost (LatencyTweak2=2) | Lowest GPU render queue latency. |
| HDR | Off | No display processing latency. |
| Energy Saving (idle) | Off | No power saving during competitive play. |
| Energy Saving (focus loss) | Off | No throttling on alt-tab. |
| Fortnite IFEO CpuPriorityClass | 3 (High) | OS applies at process creation — no anti-cheat interaction. |
| Fortnite IFEO IoPriority | 3 (High) | High IO priority. |
| Fortnite IFEO PagePriority | 5 | Highest page priority. |
| csrss.exe IFEO CpuPriorityClass | 3 (High) | GUI thread manager gets higher priority. |
| csrss.exe IFEO IoPriority | 3 (High) | GUI IO priority. |

### 8. Windows Telemetry / Bloat

| Tweak | Value | Effect |
|---|---|---|
| `AllowTelemetry` | 0 | No telemetry data collection. |
| `AdvertisingInfo` | 0 | No targeted ads. |
| `TailoredExperiences` | 0 | No tailored experiences with diagnostic data. |
| `BingSearchEnabled` | 0 | No web search in Start Menu. |
| `DisableWindowsConsumerFeatures` | 1 | Prevents bloatware auto-install (Candy Crush, TikTok, etc.). |
| `DisableConsumerAccountStateContent` | 1 | No consumer account state content. |
| Background apps | Globally disabled | `GlobalUserDisabled=1`. |
| `SilentInstalledAppsEnabled` | 0 | No silent app installs. |
| 15 telemetry scheduled tasks | Disabled | CompatTelRunner, CEIP, Feedback, DiskDiagnostic, etc. |
| WerSvc | Disabled | Windows Error Reporting service. |
| Fault Tolerant Heap | Disabled | FTH adds heap indirection — no benefit for games. |
| Remote Assistance | Disabled | Closes background service. Does NOT affect RustDesk. |
| Maps auto-update | 0 | No offline map downloads. |
| Push notification toasts | 0 | No toast interruptions during gameplay. |
| `DisableAutomaticRestartSignOn` | 1 | No auto-restart after updates while logged in. |
| Hibernation | Off | Frees disk space, disables Fast Startup. |
| TrkWks | Disabled | Distributed Link Tracking Client — not needed on single PC. |

### 9. Pre-existing disabled services (before LatencyLab)

These were already disabled on the machine before the LatencyLab session:

| Service | Why |
|---|---|
| DiagTrack | Telemetry |
| PcaSvc | Program Compatibility Assistant |
| Spooler | Print Spooler (no printer) |
| SysMain | Superfetch (SSD, not needed) |
| WSearch | Windows Search (replaced by Everything) |
| WlanSvc | WLAN AutoConfig (using Ethernet) |
| WinDefend | Microsoft Defender (replaced by third-party) |
| WdNisSvc | Defender Network Inspection |
| Xbox services (4) | Not using Xbox |
| GamingServices (2) | Not using Xbox app |
| Bluetooth services (4) | Not using Bluetooth peripherals |
| CDPSvc | Connected Devices Platform |
| dmwappushservice | WAP Push |
| DPS | Diagnostic Policy Service |
| DusmSvc | Data Usage |
| iphlpsvc | IP Helper (IPv6 transition) |
| lfsvc | Geolocation |
| lmhosts | NetBIOS Helper |
| MapsBroker | Downloaded Maps |
| NetTcpPortSharing | Net.Tcp Port Sharing |
| PhoneSvc | Phone Service |
| QWAVE | Quality Windows Audio Video Experience |
| RasMan | Remote Access |
| RemoteAccess | Routing and Remote Access |
| RemoteRegistry | Remote Registry |
| RetailDemo | Retail Demo |
| SharedAccess | ICS |
| ShellHWDetection | Shell Hardware Detection |
| SSDPSRV | SSDP Discovery |
| stisvc | Windows Image Acquisition |
| TabletInputService | Touch Keyboard |
| TroubleshootingSvc | Recommended Troubleshooting |
| tzautoupdate | Auto Time Zone |
| upnphost | UPnP Device Host |
| WdiServiceHost | Diagnostic Service Host |
| WpnService | Push Notifications System |
| diagnosticshub | Diagnostics Hub |
| jhi_service | Intel DAL |
| WMIRegistrationService | Intel ME WMI |

### 10. MMCSS Tasks

| Tweak | Value | Effect |
|---|---|---|
| Games task | Priority=6, GPU=8, High | High priority for game scheduling. |
| DisplayPostProcessing task | Priority=8, GPU=18, LatencySensitive=True | Display post-processing high priority. |
| Audio task | Affinity=0 | Default affinity for audio. |

### 11. Filesystem / Memory

| Tweak | Value | Effect |
|---|---|---|
| `DisablePagingExecutive` | 1 | Kernel drivers stay in RAM — no page faults during DPC processing. |
| NTFS `memoryusage` | 2 | Larger NTFS paged-pool cache. Helps asset streaming. |
| NTFS `NTFSDisable8dot3NameCreation` | 1 | No 8.3 short name generation. |
| NTFS `NtfsMftZoneReservation` | 1 | MFT zone reservation. |
| NTFS `ContigFileAllocSize` | 100 (64KB) | Contiguous file allocation size. |
| NTFS `DisableLastAccess` | 2 (system managed) | Already disabled. |
| `SvcHostSplitThresholdInKB` | 33554432 (32GB) | SvcHost split at 32GB. |

### 12. Display / Desktop

| Tweak | Value | Effect |
|---|---|---|
| Fullscreen Optimizations | Disabled | `GameDVR_FSEBehaviorMode=2`, `GameDVR_FSEBehavior=2`, `GameDVR_HonorUserFSEBehaviorMode=1`, `GameDVR_DXGIHonorFSEWindowsCompatible=1`, `GameDVR_EFSEFeatureFlags=0`, `GameDVR_DSEBehavior=2`. |
| GameDVR | Disabled | `GameDVR_Enabled=0`, `AppCaptureEnabled=0`, `AllowGameDVR=0`. |
| GameBar | Game Mode on, overlay off | `AutoGameModeEnabled=1`, `UseNexusForGameBarEnabled=0`, `ShowStartupPanel=0`. |
| Audio ducking | Disabled (`UserDuckingPreference=3`) | Stops Windows lowering game audio 20% on Discord voice. |
| Sticky Keys shortcut | Disabled (`Flags=506`) | 5x Shift won't trigger during gaming. |
| `MenuShowDelay` | 0 | Instant menu appearance. |
| `DelayedDesktopSwitchTimeout` | 0 | Faster desktop switch on login. |

### 13. Kill Timeouts

| Tweak | Value | Effect |
|---|---|---|
| `AutoEndTasks` | 1 | Auto-end hung tasks on logoff/shutdown. |
| `HungAppTimeout` | 1000ms | Kill hung apps in 1s (default 5s+). |
| `WaitToKillAppTimeout` | 2000ms | Wait 2s before killing apps. |
| `LowLevelHooksTimeout` | 1000ms | Low-level hooks timeout. |
| `WaitToKillServiceTimeout` | 2000ms | Kill services in 2s (default 5s). |

### 14. Background Process Management

The boot script (`boot.ps1`) runs continuously and:
- Pins background processes to E-cores (logical 16-31)
- **Never** pins: nvcontainer, NVDisplay.Container, dwm, audiodg, csrss, winlogon, explorer, GameInput services, EpicGamesLauncher
- Detects Fortnite launch → closes Spotify, tightens affinity loop to 5s
- Detects Fortnite exit → relaxes loop to 15s
- Monitors downlink saturation and logs warnings when line is loaded during a match
- Re-asserts all registry tweaks on every logon (Windows/driver updates can reset them)
- Re-disables telemetry scheduled tasks (Windows re-enables some after updates)
- Disables NVIDIA bloat directories on boot (when files aren't in use)

### 15. Discord

| Tweak | Value | Effect |
|---|---|---|
| `CLIPS_ENABLED` | false | Discord Clips disabled. |
| `KARMA_ENABLED` | false | Discord data collection disabled. |
| discord_clips process | Killed on detection | Prevents clips process from running. |

---

## Repository structure

```
latencylab/
├── README.md                    # This file
├── apply.ps1                    # Apply ALL tweaks
├── verify.ps1                   # Verify ALL tweaks
├── revert.ps1                   # Revert ALL tweaks
├── boot.ps1                     # Persistent watcher (runs at logon)
├── set-fortnite-config.ps1      # Fortnite GameUserSettings.ini config
├── test-upload-speed.ps1        # Measure upload bandwidth for QoS shaper
├── INSTALL.md                   # Detailed installation guide
└── HARDWARE.md                  # Hardware-specific notes
```

## Sources

Research drawn from:
- `djdallmann/GamingPCSetup` — xperf DPC latency measurements
- `DLCI/Gaming-related-Windows-10-Registry-Research` — registry research
- `pan1kt/GamingTweaks` — Windows gaming tweaks
- `eferlin/frameguard` — frame pacing research
- `MaxxTopia/optimizationmaxxing` — MMCSS and audio tweaks
- `omnibot007/fortnite-latency-tweaks` — evidence-based Fortnite tweaks
- `omnibot007/fortnite-tweak-packs` — audited tweak packs (legitimate changes extracted)
- Blur Busters — timer resolution and frame pacing
- Epic Games support — controller input lag documentation
- Intel I225-V driver documentation — RSS configuration

## License

MIT. See `LICENSE`.
