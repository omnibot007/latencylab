<#
.SYNOPSIS
    Applies competitive Fortnite settings to GameUserSettings.ini.
    ThinkPad P15 Gen 1 adapted edition.

.DESCRIPTION
    Only touches keys exposed in Fortnite's own settings menu (TOS-safe).
    Does NOT create Engine.ini (ban-risk file).
    Does NOT remove visual obstructions (fog, foliage, walls).

    ADAPTED FROM ORIGINAL:
    - 1920x1080 native (not 1600x900 - panel is 1080p)
    - Does NOT touch LatencyTweak2 (user's prior decision: Reflex On, not On+Boost,
      due to single-fan Quadro T1000 thermal limitation)
    - Does NOT touch FrameRateLimit (user's current choice, leave as-is)

    Close Fortnite and Epic Games Launcher before running.

.PARAMETER Width
    Render width. Default 1920 (native panel).

.PARAMETER Height
    Render height. Default 1080 (native panel).

.PARAMETER ResolutionQuality
    3D resolution percentage. Default 100 (native).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$Width = 1920,
    [int]$Height = 1080,
    [double]$ResolutionQuality = 100
)

$ErrorActionPreference = 'Stop'
$cfg = "$env:LOCALAPPDATA\FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini"
if (-not (Test-Path $cfg)) { throw "GameUserSettings.ini not found at $cfg" }

# Fortnite rewrites this file on exit - must be closed
$fn = Get-Process -Name 'FortniteClient-Win64-Shipping','FortniteLauncher','EasyAntiCheat*' -EA SilentlyContinue
if ($fn) { throw "Fortnite is running. Close it completely, then re-run." }

# Backup
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = "$env:LOCALAPPDATA\LatencyLab\backup"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Set-ItemProperty -Path $cfg -Name IsReadOnly -Value $false -EA SilentlyContinue
Copy-Item $cfg (Join-Path $backupDir "GameUserSettings_$stamp.ini.bak") -Force
Write-Host "backup -> $backupDir\GameUserSettings_$stamp.ini.bak" -ForegroundColor DarkGray

$resQ = '{0:F6}' -f $ResolutionQuality

$changes = [ordered]@{
    'ResolutionSizeX'                    = @{ v="$Width";  why='native render resolution' }
    'ResolutionSizeY'                    = @{ v="$Height"; why='native render resolution' }
    'LastUserConfirmedResolutionSizeX'   = @{ v="$Width";  why='stops re-prompting' }
    'LastUserConfirmedResolutionSizeY'   = @{ v="$Height"; why='stops re-prompting' }
    'DesiredScreenWidth'                 = @{ v="$Width";  why='3D resolution target' }
    'DesiredScreenHeight'                = @{ v="$Height"; why='3D resolution target' }
    'LastUserConfirmedDesiredScreenWidth'= @{ v="$Width";  why='matches above' }
    'LastUserConfirmedDesiredScreenHeight'=@{ v="$Height"; why='matches above' }
    'PotentiallyUpscaledResolutionQuality'=@{ v=$resQ;     why='native, no upscale' }
    'NeverUpscaledResolutionQuality'     = @{ v=$resQ;     why='native' }
    'FortAntiAliasingMethod'             = @{ v='Disabled';why='no DLSS overhead in Performance mode' }
    'AudioQualityLevel'                  = @{ v='0';       why='Low audio - saves CPU' }
    'LastConfirmedAudioQualityLevel'     = @{ v='0';       why='Low audio - saves CPU' }
    'FrontendFrameRateLimit'             = @{ v='60';      why='lobby cap - heat saving' }
    'bIsEnergySavingEnabledIdle'         = @{ v='False';   why='no power saving during play' }
    'bIsEnergySavingEnabledFocusLoss'    = @{ v='False';   why='no throttling on alt-tab' }
    'EnergySavingLevelFocusLoss'         = @{ v='0';       why='disable focus-loss throttle' }
    'bUseVSync'                          = @{ v='False';   why='no display pipeline latency' }
    'bMotionBlur'                        = @{ v='False';   why='clearer frames' }
    'bUseHDRDisplayOutput'               = @{ v='False';   why='HDR adds display latency' }
    'bUseDynamicResolution'              = @{ v='False';   why='consistent frame times' }
    'bUseNanite'                         = @{ v='False';   why='not available in Performance mode' }
}
$sgChanges = [ordered]@{
    'sg.ResolutionQuality'   = @{ v='100'; why='native' }
    'sg.ViewDistanceQuality' = @{ v='3';   why='Epic - competitive visibility' }
    'sg.AntiAliasingQuality' = @{ v='0';   why='off' }
    'sg.ShadowQuality'       = @{ v='0';   why='off' }
    'sg.PostProcessQuality'  = @{ v='0';   why='off' }
    'sg.EffectsQuality'      = @{ v='0';   why='off' }
    'sg.FoliageQuality'      = @{ v='0';   why='off' }
}

$lines = Get-Content $cfg
$applied = @(); $skipped = @()

function Set-IniLine {
    param([string[]]$Buf, [string]$Key, [string]$Val)
    $rx = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = 0; $i -lt $Buf.Count; $i++) {
        if ($Buf[$i] -match $rx) { $Buf[$i] = "$Key=$Val"; return ,@($Buf, $true) }
    }
    ,@($Buf, $false)
}

foreach ($set in @($changes, $sgChanges)) {
    foreach ($k in $set.Keys) {
        $want = $set[$k].v
        $old = ($lines | Where-Object { $_ -match ('^\s*' + [regex]::Escape($k) + '\s*=') } | Select-Object -First 1)
        $oldV = if ($old) { ($old -split '=', 2)[1].Trim() } else { '(absent)' }
        if ($oldV -eq $want) { $skipped += $k; continue }
        $r = Set-IniLine -Buf $lines -Key $k -Val $want
        $lines = $r[0]
        if ($r[1]) { $applied += [pscustomobject]@{ Key=$k; Old=$oldV; New=$want; Why=$set[$k].why } }
    }
}

Write-Host ''
Write-Host ('=' * 78) -ForegroundColor Cyan
Write-Host ' FORTNITE CONFIG CHANGES' -ForegroundColor Cyan
Write-Host ('=' * 78) -ForegroundColor Cyan
if ($applied) {
    $applied | Format-Table @{n='Setting';e={$_.Key};w=38}, @{n='From';e={$_.Old};w=12}, @{n='To';e={$_.New};w=12}, Why -AutoSize -Wrap | Out-String | Write-Host
}
Write-Host "  Already correct: $($skipped -join ', ')" -ForegroundColor DarkGray

if ($PSCmdlet.ShouldProcess($cfg, 'write config')) {
    $lines | Set-Content $cfg -Encoding UTF8
    Write-Host "`n  Written." -ForegroundColor Green
}

Write-Host "`n  UNCHANGED ON PURPOSE:" -ForegroundColor Cyan
Write-Host "    PreferredFeatureLevel=es31   Performance Mode"
Write-Host "    FrameRateLimit               (user's choice - not touched)"
Write-Host "    LatencyTweak2                (user's choice - not touched)"
Write-Host "                                  Reflex On (1) recommended over On+Boost (2)"
Write-Host "                                  due to Quadro T1000 single-fan thermal limit"
Write-Host "    No Engine.ini created        (ban-risk file)"
Write-Host ''


