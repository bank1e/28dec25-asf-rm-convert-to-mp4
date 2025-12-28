# ============================================
# Configuration Loading
# ============================================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

if (-not (Test-Path $configPath)) {
    Write-Error "Config file not found at: $configPath"
    Write-Host "Please create 'config.json' in the same directory as this script."
    exit 1
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ffmpeg = $config.ffmpeg_path
    $src = $config.source_dir
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
# Get Files to Convert
# ============================================
$files = Get-ChildItem -Path $src -File | Where-Object { 
    $_.Extension.ToLower() -in ".rm", ".asf" 
}

if ($files.Count -eq 0) {
    Write-Warning "No .rm or .asf files found in: $src"
    exit 0
}

Write-Host "Found $($files.Count) file(s) to convert"
Write-Host "Output directory: $out"
Write-Host ("-" * 60)

# ============================================
# Convert Files
# ============================================
$successCount = 0
$failCount = 0

foreach ($f in $files) {
    $in = $f.FullName
    $outFile = Join-Path $out ($f.BaseName + $f.Extension.ToLower() + ".mp4")
    
    Write-Host "Converting: $($f.Name)"
    
    & $ffmpeg -hide_banner -y `
        -f lavfi -i "color=c=black:s=1280x720:r=30" `
        -i $in `
        -map 0:v:0 -map 1:a:0? `
        -shortest `
        -c:v libx264 -pix_fmt yuv420p -tune stillimage `
        -c:a aac -b:a 192k `
        -movflags +faststart `
        $outFile
    
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
Write-Host "  Output folder: $out"
```

## Create your `config.json` in the same folder as the script:

**File structure:**
```
📁 Your script folder/
├── convert-video.ps1  (your script)
└── config.json        (your config)