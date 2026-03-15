#!/bin/bash

# BlackHole 2ch Management CLI
# A comprehensive command-line interface for managing BlackHole 2ch audio driver

set -e

SCRIPT_NAME="$(basename "$0")"
DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
PACKAGE_PATH="@PACKAGE_PATH@"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print colored output
print_error() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  Warning: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_header() {
    echo -e "${BOLD}$1${NC}"
}

# Check if running on macOS
check_macos() {
    if [ "$(uname)" != "Darwin" ]; then
        print_error "This tool is only for macOS systems"
        exit 1
    fi
}

# Check admin privileges for operations that require them
check_admin() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This operation requires administrator privileges"
        echo "Usage: sudo $SCRIPT_NAME $1"
        echo ""
        echo "Example:"
        echo "  sudo $SCRIPT_NAME install"
        exit 1
    fi
}

# Get BlackHole installation status
get_status() {
    if [ -d "$DRIVER_PATH" ]; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

# Show status with detailed information
show_status() {
    print_header "BlackHole 2ch Status"
    echo "===================="
    echo ""
    
    local status=$(get_status)
    
    if [ "$status" = "installed" ]; then
        print_success "BlackHole 2ch is installed"
        echo "📍 Location: $DRIVER_PATH"
        
        # Check if it's accessible to audio system
        if ls "$DRIVER_PATH" >/dev/null 2>&1; then
            print_info "Driver files are accessible"
        else
            print_warning "Driver files may have permission issues"
        fi
        
        # Check for running audio applications
        echo ""
        echo "🔍 Audio applications status:"
        local audio_apps=("Logic Pro X" "GarageBand" "Audacity" "Pro Tools" "Ableton Live" "Reaper" "OBS" "Discord" "Zoom" "Skype")
        local running_apps=()
        
        for app in "${audio_apps[@]}"; do
            if pgrep -f "$app" > /dev/null 2>&1; then
                running_apps+=("$app")
            fi
        done
        
        if [ ${#running_apps[@]} -gt 0 ]; then
            print_warning "Audio applications are running:"
            for app in "${running_apps[@]}"; do
                echo "  - $app"
            done
            echo "  Consider restarting them to recognize BlackHole 2ch"
        else
            print_info "No common audio applications are currently running"
        fi
        
    else
        print_warning "BlackHole 2ch is not installed"
        echo "📍 Expected location: $DRIVER_PATH"
    fi
    
    echo ""
    echo "💡 Next steps:"
    if [ "$status" = "installed" ]; then
        echo "  - Open Audio MIDI Setup to verify 'BlackHole 2ch' appears"
        echo "  - Configure audio applications to use BlackHole 2ch"
        echo "  - To uninstall: sudo $SCRIPT_NAME uninstall"
    else
        echo "  - To install: sudo $SCRIPT_NAME install"
        echo "  - To see help: $SCRIPT_NAME help"
    fi
}

# Install BlackHole driver
install_driver() {
    check_admin "install"
    
    print_header "Installing BlackHole 2ch Audio Driver"
    echo "======================================"
    echo ""
    
    # Check if already installed
    if [ -d "$DRIVER_PATH" ]; then
        print_warning "BlackHole 2ch is already installed"
        echo ""
        read -p "Do you want to reinstall? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
        echo ""
        print_info "Removing existing installation..."
        rm -rf "$DRIVER_PATH"
    fi
    
    # Check source driver exists
    local source_driver="$PACKAGE_PATH/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
    if [ ! -d "$source_driver" ]; then
        print_error "BlackHole driver not found in package: $source_driver"
        print_info "Please ensure the blackhole-2ch package is properly installed"
        exit 1
    fi
    
    # Create target directory
    print_info "Creating target directory..."
    mkdir -p "$(dirname "$DRIVER_PATH")"
    
    # Copy driver
    print_info "Copying BlackHole 2ch driver..."
    cp -R "$source_driver" "$DRIVER_PATH"
    
    # Set permissions
    print_info "Setting permissions..."
    chown -R root:wheel "$DRIVER_PATH"
    chmod -R 755 "$DRIVER_PATH"
    
    # Restart CoreAudio
    print_info "Restarting CoreAudio service..."
    killall -9 coreaudiod 2>/dev/null || true
    
    # Wait for CoreAudio to restart
    sleep 2
    
    print_success "BlackHole 2ch installation completed!"
    echo ""
    echo "📋 Verification steps:"
    echo "  1. Open Audio MIDI Setup (Applications → Utilities)"
    echo "  2. Look for 'BlackHole 2ch' in the device list"
    echo "  3. If not visible, restart your computer"
    echo ""
    echo "💡 Usage examples:"
    echo "  - Set as output in audio applications for routing"
    echo "  - Create Multi-Output Device for simultaneous monitoring"
    echo "  - Record system audio by setting as system output"
}

# Uninstall BlackHole driver
uninstall_driver() {
    check_admin "uninstall"
    
    print_header "Uninstalling BlackHole 2ch Audio Driver"
    echo "======================================="
    echo ""
    
    # Check if installed
    if [ ! -d "$DRIVER_PATH" ]; then
        print_info "BlackHole 2ch is not installed"
        echo "No action needed."
        exit 0
    fi
    
    # Show warning about running applications
    echo "⚠️  This will:"
    echo "  - Remove the BlackHole 2ch driver from the system"
    echo "  - Restart CoreAudio service"
    echo "  - Make BlackHole 2ch unavailable to all applications"
    echo ""
    
    # Check for running audio applications
    local audio_apps=("Logic Pro X" "GarageBand" "Audacity" "Pro Tools" "Ableton Live" "Reaper" "OBS" "Discord" "Zoom" "Skype")
    local running_apps=()
    
    for app in "${audio_apps[@]}"; do
        if pgrep -f "$app" > /dev/null 2>&1; then
            running_apps+=("$app")
        fi
    done
    
    if [ ${#running_apps[@]} -gt 0 ]; then
        print_warning "Audio applications are running:"
        for app in "${running_apps[@]}"; do
            echo "  - $app"
        done
        echo ""
        echo "It's recommended to close these applications first."
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Uninstallation cancelled."
            exit 0
        fi
    else
        read -p "Are you sure you want to uninstall BlackHole 2ch? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Uninstallation cancelled."
            exit 0
        fi
    fi
    
    echo ""
    
    # Close Audio MIDI Setup if running
    if pgrep -f "Audio MIDI Setup" > /dev/null; then
        print_info "Closing Audio MIDI Setup..."
        pkill -f "Audio MIDI Setup" || true
        sleep 1
    fi
    
    # Remove driver
    print_info "Removing BlackHole 2ch driver..."
    rm -rf "$DRIVER_PATH"
    
    # Restart CoreAudio
    print_info "Restarting CoreAudio service..."
    killall -9 coreaudiod 2>/dev/null || true
    
    # Wait for CoreAudio to restart
    sleep 2
    
    # Verify removal
    if [ -d "$DRIVER_PATH" ]; then
        print_warning "Driver directory still exists after removal"
    else
        print_success "BlackHole 2ch uninstallation completed!"
    fi
    
    echo ""
    echo "📋 Next steps:"
    echo "  - Audio applications may need audio settings reconfigured"
    echo "  - Multi-Output devices using BlackHole will need recreation"
    echo "  - Restart computer for complete removal (recommended)"
}

# Show help information
show_help() {
    print_header "BlackHole 2ch Management CLI"
    echo "============================="
    echo ""
    echo "A command-line interface for managing BlackHole 2ch audio loopback driver."
    echo ""
    echo "USAGE:"
    echo "    $SCRIPT_NAME <COMMAND>"
    echo ""
    echo "COMMANDS:"
    echo "    status              Show BlackHole 2ch installation status"
    echo "    install             Install BlackHole 2ch driver (requires sudo)"
    echo "    uninstall           Uninstall BlackHole 2ch driver (requires sudo)"
    echo "    help                Show this help message"
    echo "    version             Show version information"
    echo ""
    echo "EXAMPLES:"
    echo "    $SCRIPT_NAME status"
    echo "    sudo $SCRIPT_NAME install"
    echo "    sudo $SCRIPT_NAME uninstall"
    echo ""
    echo "NOTES:"
    echo "    - BlackHole 2ch is a virtual audio loopback driver for macOS"
    echo "    - Installation/uninstallation requires administrator privileges"
    echo "    - After installation, use Audio MIDI Setup to verify the device"
    echo "    - Applications may need to be restarted to recognize changes"
    echo ""
    echo "FOR MORE INFORMATION:"
    echo "    - Package Documentation: $(dirname "$PACKAGE_PATH")/README.md"
    echo "    - Official Website: https://existential.audio/blackhole/"
    echo "    - GitHub Repository: https://github.com/ExistentialAudio/BlackHole"
}

# Show version information
show_version() {
    echo "BlackHole 2ch Management CLI"
    echo "Version: 0.6.1 (package version)"
    echo "BlackHole Version: 0.6.1"
    echo "Package Path: $PACKAGE_PATH"
    echo ""
    echo "This tool is part of the blackhole-2ch Nix package."
    echo "For updates, rebuild your Nix configuration."
}

# Main command dispatcher
main() {
    check_macos
    
    case "${1:-}" in
        "status")
            show_status
            ;;
        "install")
            install_driver
            ;;
        "uninstall")
            uninstall_driver
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        "version"|"--version"|"-v")
            show_version
            ;;
        "")
            print_error "No command specified"
            echo ""
            echo "Usage: $SCRIPT_NAME <command>"
            echo "Run '$SCRIPT_NAME help' for more information."
            exit 1
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            echo "Available commands: status, install, uninstall, help, version"
            echo "Run '$SCRIPT_NAME help' for more information."
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"