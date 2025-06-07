# VLSub OpenSubtitles.com Extension Installer for Windows
param(
    [switch]$Force
)

# Set colors
$Host.UI.RawUI.ForegroundColor = "White"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "VLSub OpenSubtitles.com Extension Installer" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "❌ PowerShell 3.0 or higher is required" -ForegroundColor Red
    Write-Host "Please update PowerShell and try again." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Check execution policy
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -eq "Restricted") {
    Write-Host "⚠ PowerShell execution policy is restricted" -ForegroundColor Yellow
    Write-Host "Run this command as Administrator to allow scripts:" -ForegroundColor Yellow
    Write-Host "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
    if (-not $Force) {
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Detect VLC installation
Write-Host "Checking for VLC installation..." -ForegroundColor Blue

$vlcPaths = @(
    "${env:ProgramFiles}\VideoLAN\VLC\vlc.exe",
    "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe",
    "${env:LOCALAPPDATA}\Programs\VideoLAN\VLC\vlc.exe"
)

$vlcFound = $false
foreach ($path in $vlcPaths) {
    if (Test-Path $path) {
        Write-Host "✅ VLC found at: $path" -ForegroundColor Green
        $vlcFound = $true
        break
    }
}

if (-not $vlcFound) {
    Write-Host "⚠ VLC not found in standard locations" -ForegroundColor Yellow
    Write-Host "Download VLC: https://www.videolan.org/vlc/download-windows.html" -ForegroundColor Cyan
    if (-not $Force) {
        $continue = Read-Host "Continue installation anyway? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            exit 1
        }
    }
}

# Set installation directory
$vlcExtDir = "$env:APPDATA\vlc\lua\extensions"
Write-Host "Extension directory: $vlcExtDir" -ForegroundColor Blue

# Create directory if it doesn't exist
if (-not (Test-Path $vlcExtDir)) {
    Write-Host "Creating extension directory..." -ForegroundColor Blue
    try {
        New-Item -ItemType Directory -Path $vlcExtDir -Force | Out-Null
        Write-Host "✅ Directory created" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to create directory: $_" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
} else {
    Write-Host "✅ Directory exists" -ForegroundColor Green
}

# Backup existing installation
$existingFile = "$vlcExtDir\vlsubcom.lua"
if (Test-Path $existingFile) {
    Write-Host "Found existing VLSub installation..." -ForegroundColor Blue
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = "$existingFile.backup.$timestamp"
    try {
        Copy-Item $existingFile $backupFile
        Write-Host "✅ Backup created: vlsubcom.lua.backup.$timestamp" -ForegroundColor Green
    } catch {
        Write-Host "⚠ Could not create backup: $_" -ForegroundColor Yellow
    }
}

# Download the extension
$downloadUrl = "https://github.com/opensubtitles/vlsub-opensubtitles-com/releases/latest/download/vlsubcom.lua"
$destinationFile = "$vlcExtDir\vlsubcom.lua"

Write-Host "Downloading VLSub extension..." -ForegroundColor Blue
Write-Host "From: $downloadUrl" -ForegroundColor Cyan

try {
    # Use TLS 1.2 for better compatibility
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    $progressPreference = 'Continue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $destinationFile -UseBasicParsing
    
    Write-Host "✅ Download successful" -ForegroundColor Green
    Write-Host "✅ Installation complete" -ForegroundColor Green
    Write-Host "📍 Installed to: $destinationFile" -ForegroundColor Blue
} catch {
    Write-Host "❌ Download failed: $_" -ForegroundColor Red
    Write-Host "Please check your internet connection and try again." -ForegroundColor Red
    Write-Host "Or download manually from: https://github.com/opensubtitles/vlsub-opensubtitles-com/releases" -ForegroundColor Cyan
    Read-Host "Press Enter to exit"
    exit 1
}

# Verify installation
if (Test-Path $destinationFile) {
    $fileSize = (Get-Item $destinationFile).Length
    Write-Host "✅ File installed successfully ($([math]::Round($fileSize/1KB, 1)) KB)" -ForegroundColor Green
}

# Show completion message
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "🎉 Installation Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Extension installed to:" -ForegroundColor Blue
Write-Host "   $destinationFile" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart VLC Media Player" -ForegroundColor White
Write-Host "2. Go to View → VLSub OpenSubtitles.com" -ForegroundColor White
Write-Host "3. Enter your OpenSubtitles.com credentials" -ForegroundColor White
Write-Host "   (Create free account at https://www.opensubtitles.com/)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Quick start:" -ForegroundColor Yellow
Write-Host "• Hash search: For exact subtitle matches" -ForegroundColor White
Write-Host "• Name search: For flexible title-based search" -ForegroundColor White
Write-Host "• Double-click subtitle to download and load" -ForegroundColor White
Write-Host ""
Write-Host "Support & Documentation:" -ForegroundColor Yellow
Write-Host "• Issues: https://github.com/opensubtitles/vlsub-opensubtitles-com/issues" -ForegroundColor Cyan
Write-Host "• Docs: https://github.com/opensubtitles/vlsub-opensubtitles-com" -ForegroundColor Cyan
Write-Host "• OpenSubtitles: https://www.opensubtitles.com/" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 To uninstall: Delete the file at the path shown above" -ForegroundColor Blue
Write-Host ""

if (-not $Force) {
    Read-Host "Press Enter to exit"
}