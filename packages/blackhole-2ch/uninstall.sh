#!/bin/bash
set -e

# BlackHole 2ch Uninstallation Script
# This script removes the BlackHole 2ch audio driver from the system

echo "===================================="
echo "BlackHole 2ch Uninstallation Script"
echo "===================================="
echo ""

# Check for admin privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run with sudo privileges"
    echo "Usage: sudo $0"
    echo ""
    echo "Example:"
    echo "  sudo ./uninstall.sh"
    exit 1
fi

# Check if we're on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Error: This script is only for macOS systems"
    exit 1
fi

DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"

echo "🔍 Checking for BlackHole 2ch installation..."
echo "📍 Driver location: $DRIVER_PATH"
echo ""

# Check if driver is installed
if [ ! -d "$DRIVER_PATH" ]; then
    echo "ℹ️  BlackHole 2ch driver is not installed (or already removed)"
    echo "No action needed."
    exit 0
fi

echo "⚠️  BlackHole 2ch driver found. This will:"
echo "  - Remove the driver from the system"
echo "  - Restart CoreAudio service"
echo "  - Make BlackHole 2ch unavailable to all applications"
echo ""

# Confirmation prompt
read -p "Are you sure you want to uninstall BlackHole 2ch? [y/N]: " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""

# Close Audio MIDI Setup if it's running
echo "📱 Checking for running Audio MIDI Setup..."
if pgrep -f "Audio MIDI Setup" > /dev/null; then
    echo "🔄 Closing Audio MIDI Setup..."
    pkill -f "Audio MIDI Setup" || true
    sleep 1
fi

# Check for applications that might be using BlackHole
echo "🔍 Checking for applications that might be using audio devices..."
AUDIO_APPS=(
    "Logic Pro X"
    "GarageBand" 
    "Audacity"
    "Pro Tools"
    "Ableton Live"
    "Reaper"
    "QuickTime Player"
    "Zoom"
    "Skype"
    "Discord"
    "OBS"
)

RUNNING_AUDIO_APPS=()
for app in "${AUDIO_APPS[@]}"; do
    if pgrep -f "$app" > /dev/null; then
        RUNNING_AUDIO_APPS+=("$app")
    fi
done

if [ ${#RUNNING_AUDIO_APPS[@]} -gt 0 ]; then
    echo "⚠️  Warning: The following audio applications are running:"
    for app in "${RUNNING_AUDIO_APPS[@]}"; do
        echo "  - $app"
    done
    echo ""
    echo "It's recommended to close these applications before uninstalling."
    read -p "Continue anyway? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled. Please close audio applications and try again."
        exit 0
    fi
fi

echo ""

# Remove the driver
echo "🗑️  Removing BlackHole 2ch driver..."
rm -rf "$DRIVER_PATH"

if [ -d "$DRIVER_PATH" ]; then
    echo "❌ Error: Failed to remove driver. Please check permissions."
    exit 1
fi

echo "✅ Driver removed successfully"

# Restart CoreAudio service
echo "🔄 Restarting CoreAudio service..."
killall -9 coreaudiod 2>/dev/null || true

# Wait a moment for CoreAudio to restart
sleep 2

# Verify removal
if [ -d "$DRIVER_PATH" ]; then
    echo "⚠️  Warning: Driver directory still exists after removal"
else
    echo "✅ Driver removal verified"
fi

echo ""
echo "✅ BlackHole 2ch uninstallation completed successfully!"
echo ""
echo "📋 Verification steps:"
echo "  1. Open 'Audio MIDI Setup' app"
echo "  2. 'BlackHole 2ch' should no longer appear in the device list"
echo "  3. Applications using BlackHole 2ch may need to be reconfigured"
echo ""
echo "💡 Notes:"
echo "  - You may need to restart your computer for complete removal"
echo "  - Audio applications may need to have their audio settings updated"
echo "  - Multi-Output devices containing BlackHole 2ch will need to be recreated"
echo ""
echo "🔄 To reinstall: sudo ./install.sh"
echo ""