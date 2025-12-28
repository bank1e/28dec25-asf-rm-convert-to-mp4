# ============================================
# Configuration Loading
# ============================================
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

if (-not (Test-Path $configPath)) {
    Write-Error "Config file not found at: $configPath"
    Write-Host "Please create 'config.json' in the same directory as this script."
    exit 1
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ffmpeg = $config.ffmpeg_path
    $src    = $config.source_dir
}
catch {
    Write-Error "Failed to load config file: $_"
    exit 1
}

# ============================================
# Validation
# ============================================
if (-not (Test-Path $ffmpeg)) {
    Write-Error "FFmpeg not found at: $ffmpeg"
    exit 1
}

if (-not (Test-Path $src)) {
    Write-Error "Source directory not found at: $src"
    exit 1
}

# ============================================
# Setup Output Directory
# ============================================
$out = Join-Path $src "_mp4"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ============================================
# Optional Config (defaults)
# ============================================
$size         = if ($config.size -and $config.size.Trim() -ne "") { $config.size } else { "1280x720" }
$fps          = if ($config.fps  -and $config.fps.ToString().Trim() -ne "") { $config.fps } else { "30" }
$audioBitrate = if ($config.audio_bitrate -and $config.audio_bitrate.Trim() -ne "") { $config.audio_bitrate } else { "192k" }
$overwrite    = if ($null -ne $config.overwrite) { [bool]$config.overwrite } else { $true }
$skipIfExists = if ($null -ne $config.skip_if_exists) { [bool]$config.skip_if_exists } else { $false }
$writeLog     = if ($null -ne $config.write_log) { [bool]$config.write_log } else { $false }

# ============================================
# Build lavfi filter string SAFELY
# IMPORTANT: use ${size} / ${fps} because ":" breaks $size parsing otherwise
# ============================================
$lavfi = "color=c=black:s=${size}:r=${fps}"

# Optional log file
$logPath = Join-Path $out ("ffmpeg_log_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# ============================================
# Get Files to Convert
# ============================================
$files = Get-ChildItem -Path $src -File | Where-Object {
    $_.Extension.ToLower() -in ".rm", ".asf", ".mp3", ".mp4"
}

if ($files.Count -eq 0) {
    Write-Warning "No target files (.rm/.asf/.mp3/.mp4) found in: $src"
    exit 0
}

Write-Host "Found $($files.Count) file(s) to convert"
Write-Host "Output directory: $out"
Write-Host "lavfi: $lavfi"
Write-Host ("-" * 60)

# ============================================
# Convert Files
# ============================================
$successCount = 0
$failCount    = 0
$skipCount    = 0

foreach ($f in $files) {
    $in = $f.FullName
    $outFile = Join-Path $out ($f.BaseName + $f.Extension.ToLower() + ".mp4")

    if ($skipIfExists -and (Test-Path $outFile)) {
        Write-Host "Skipping (exists): $($f.Name)" -ForegroundColor Yellow
        $skipCount++
        continue
    }

    Write-Host "Converting: $($f.Name)"

    $yFlag = if ($overwrite) { "-y" } else { "-n" }

    if ($writeLog) {
        & $ffmpeg -hide_banner $yFlag `
            -f lavfi -i $lavfi `
            -i $in `
            -map 0:v:0 -map 1:a:0? `
            -shortest `
            -c:v libx264 -pix_fmt yuv420p -tune stillimage `
            -c:a aac -b:a $audioBitrate `
            -movflags +faststart `
            $outFile 2>> $logPath
    }
    else {
        & $ffmpeg -hide_banner $yFlag `
            -f lavfi -i $lavfi `
            -i $in `
            -map 0:v:0 -map 1:a:0? `
            -shortest `
            -c:v libx264 -pix_fmt yuv420p -tune stillimage `
            -c:a aac -b:a $audioBitrate `
            -movflags +faststart `
            $outFile
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Success: $($f.Name)" -ForegroundColor Green
        $successCount++
    }
    else {
        Write-Warning "  ✗ Failed: $($f.Name) (exit code: $LASTEXITCODE)"
        $failCount++
    }

    Write-Host ""
}

# ============================================
# Summary
# ============================================
Write-Host ("-" * 60)
Write-Host "Conversion Complete!" -ForegroundColor Cyan
Write-Host "  Successful: $successCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped: $skipCount" -ForegroundColor Yellow
Write-Host "  Output folder: $out"
if ($writeLog) { Write-Host "  Log file: $logPath" -ForegroundColor Cyan }
