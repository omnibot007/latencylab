<#
.SYNOPSIS
    Measures upload bandwidth using Cloudflare's speed test endpoint.
    Use the result to set the QoS upload shaper at 90% of measured bandwidth.

.EXAMPLE
    .\test-upload-speed.ps1
    # Then run: .\apply.ps1 -UploadBandwidthMbps <result * 0.9>
#>
$ErrorActionPreference = 'Continue'

Write-Host "=== Upload Speed Test (Cloudflare) ===" -ForegroundColor Cyan

$sizes = @(0.1, 0.49, 1, 2, 4)  # MB
$results = @()

foreach ($size in $sizes) {
    $bytes = [int]($size * 1MB)
    $data = New-Object byte[] $bytes
    (New-Object Random).NextBytes($data)
    $ms = New-Object System.IO.MemoryStream(,$data)
    
    Write-Host "`n  Testing $size MB upload..." -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest -Uri 'https://speed.cloudflare.com/__up' -Method Post -Body $ms -ContentType 'application/octet-stream' -UseBasicParsing -TimeoutSec 30
        $sw.Stop()
        $secs = $sw.Elapsed.TotalSeconds
        $mbps = ($size * 8) / $secs
        $results += [pscustomobject]@{ SizeMB=$size; Mbps=[math]::Round($mbps,2); Seconds=[math]::Round($secs,2) }
        Write-Host " $([math]::Round($mbps,2)) Mbps ($([math]::Round($secs,2))s)" -ForegroundColor Green
    } catch {
        Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
    $ms.Dispose()
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$best = ($results | Where-Object { $_.SizeMB -ge 2 } | Sort-Object Mbps -Descending | Select-Object -First 1)
if ($best) {
    $shaper = [math]::Round($best.Mbps * 0.9, 0)
    Write-Host "`n  Best upload (large payload): $($best.Mbps) Mbps" -ForegroundColor Green
    Write-Host "  Recommended QoS shaper (90%): $shaper Mbps" -ForegroundColor Yellow
    Write-Host "  Run: .\apply.ps1 -UploadBandwidthMbps $shaper" -ForegroundColor Yellow
} else {
    Write-Host "`n  No valid results. Check your internet connection." -ForegroundColor Red
}
