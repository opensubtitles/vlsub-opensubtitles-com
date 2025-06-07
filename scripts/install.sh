#!/bin/bash
set -e

echo "================================================"
echo "VLSub OpenSubtitles.com Extension Installer"
echo "================================================"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if curl is available
if ! command -v curl &> /dev/null; then
    printf "${RED}Error: curl is required but not installed.${NC}\n"
    echo "Please install curl and try again."
    echo ""
    echo "Install curl:"
    echo "  macOS: brew install curl (or use built-in)"
    echo "  Ubuntu/Debian: sudo apt install curl"
    echo "  Fedora: sudo dnf install curl"
    echo "  Arch: sudo pacman -S curl"
    exit 1
fi

# Detect platform and set installation directory
detect_platform() {
    case "$OSTYPE" in
        darwin*)
            PLATFORM="macOS"
            VLC_EXT_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
            ;;
        linux-gnu*|linux-musl*)
            PLATFORM="Linux"
            VLC_EXT_DIR="$HOME/.local/share/vlc/lua/extensions"
            ;;
        msys|cygwin|win*)
            PLATFORM="Windows"
            if [ -n "$APPDATA" ]; then
                VLC_EXT_DIR="$APPDATA/vlc/lua/extensions"
            else
                printf "${RED}Error: Cannot detect VLC extensions directory on Windows.${NC}\n"
                echo "Please install manually by copying vlsubcom.lua to:"
                echo "%APPDATA%\\vlc\\lua\\extensions\\"
                exit 1
            fi
            ;;
        *)
            printf "${RED}Error: Unsupported platform: $OSTYPE${NC}\n"
            echo "Supported platforms: macOS, Linux, Windows (Git Bash/WSL)"
            echo ""
            echo "For manual installation, copy vlsubcom.lua to your VLC extensions directory:"
            echo "  Windows: %APPDATA%\\vlc\\lua\\extensions\\"
            echo "  macOS: ~/Library/Application Support/org.videolan.vlc/lua/extensions/"
            echo "  Linux: ~/.local/share/vlc/lua/extensions/"
            exit 1
            ;;
    esac
}

# Check if VLC is installed
check_vlc() {
    echo "Checking for VLC installation..."
    
    case "$PLATFORM" in
        "macOS")
            if [ -d "/Applications/VLC.app" ] || command -v vlc &> /dev/null; then
                printf "${GREEN}✓ VLC found${NC}\n"
            else
                printf "${YELLOW}⚠ VLC not found.${NC}\n"
                echo "Download VLC: https://www.videolan.org/vlc/download-macosx.html"
                read -p "Continue installation anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            ;;
        "Linux")
            if command -v vlc &> /dev/null; then
                printf "${GREEN}✓ VLC found${NC}\n"
            else
                printf "${YELLOW}⚠ VLC not found.${NC}\n"
                echo "Install VLC:"
                echo "  Ubuntu/Debian: sudo apt install vlc"
                echo "  Fedora: sudo dnf install vlc"
                echo "  Arch: sudo pacman -S vlc"
                echo "  Or download from: https://www.videolan.org/"
                read -p "Continue installation anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            ;;
        "Windows")
            echo "Please ensure VLC is installed from https://www.videolan.org/"
            ;;
    esac
}

# Create installation directory
create_directory() {
    echo "Creating extension directory..."
    printf "${BLUE}Directory: $VLC_EXT_DIR${NC}\n"
    
    if [ ! -d "$VLC_EXT_DIR" ]; then
        mkdir -p "$VLC_EXT_DIR"
        printf "${GREEN}✓ Directory created${NC}\n"
    else
        printf "${GREEN}✓ Directory exists${NC}\n"
    fi
}

# Backup existing installation
backup_existing() {
    local existing_file="$VLC_EXT_DIR/vlsubcom.lua"
    
    if [ -f "$existing_file" ]; then
        echo "Found existing VLSub installation..."
        local backup_file="$existing_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$existing_file" "$backup_file"
        printf "${GREEN}✓ Backup created: $(basename "$backup_file")${NC}\n"
    fi
}

# Download and install the extension
install_extension() {
    local temp_file=$(mktemp)
    local download_url="https://github.com/opensubtitles/vlsub-opensubtitles-com/releases/latest/download/vlsubcom.lua"
    
    echo "Downloading VLSub extension..."
    printf "${BLUE}From: $download_url${NC}\n"
    
    if curl -L -f -o "$temp_file" "$download_url" --progress-bar; then
        printf "${GREEN}✓ Download successful${NC}\n"
    else
        printf "${RED}✗ Download failed${NC}\n"
        echo "Please check your internet connection and try again."
        echo "Or download manually from: https://github.com/opensubtitles/vlsub-opensubtitles-com/releases"
        rm -f "$temp_file"
        exit 1
    fi
    
    echo "Installing extension..."
    mv "$temp_file" "$VLC_EXT_DIR/vlsubcom.lua"
    printf "${GREEN}✓ Installation complete${NC}\n"
    printf "${BLUE}📍 Installed to: $VLC_EXT_DIR/vlsubcom.lua${NC}\n"
}

# Set permissions (Linux/macOS)
set_permissions() {
    if [ "$PLATFORM" != "Windows" ]; then
        chmod 644 "$VLC_EXT_DIR/vlsubcom.lua"
        printf "${GREEN}✓ Permissions set${NC}\n"
    fi
}

# Show completion message
show_completion() {
    echo
    echo "================================================"
    printf "${GREEN}🎉 Installation Complete!${NC}\n"
    echo "================================================"
    echo
    printf "${BLUE}📁 Extension installed to:${NC}\n"
    printf "${YELLOW}   $VLC_EXT_DIR/vlsubcom.lua${NC}\n"
    echo
    printf "${YELLOW}Next steps:${NC}\n"
    printf "1. ${BLUE}Restart VLC Media Player${NC}\n"
    printf "2. ${BLUE}Go to View → VLSub OpenSubtitles.com${NC}\n"
    printf "3. ${BLUE}Enter your OpenSubtitles.com credentials${NC}\n"
    printf "   ${GREEN}(Create free account at https://www.opensubtitles.com/)${NC}\n"
    echo
    printf "${YELLOW}Quick start:${NC}\n"
    printf "• ${BLUE}Hash search:${NC} For exact subtitle matches\n"
    printf "• ${BLUE}Name search:${NC} For flexible title-based search\n"
    printf "• ${BLUE}Double-click subtitle${NC} to download and load\n"
    echo
    printf "${YELLOW}Support & Documentation:${NC}\n"
    printf "• ${BLUE}Issues:${NC} https://github.com/opensubtitles/vlsub-opensubtitles-com/issues\n"
    printf "• ${BLUE}Docs:${NC} https://github.com/opensubtitles/vlsub-opensubtitles-com\n"
    printf "• ${BLUE}OpenSubtitles:${NC} https://www.opensubtitles.com/\n"
    echo
    printf "${BLUE}💡 To uninstall:${NC} Delete the file at the path shown above\n"
    echo
}

# Main installation process
main() {
    printf "${BLUE}Platform detection...${NC}\n"
    detect_platform
    printf "${GREEN}Platform: $PLATFORM${NC}\n"
    echo
    
    check_vlc
    echo
    
    create_directory
    echo
    
    backup_existing
    echo
    
    install_extension
    echo
    
    set_permissions
    echo
    
    show_completion
}

# Run installation
main "$@"