#!/bin/bash
set -e

# BlackHole 2ch Installation Script
# This script installs the BlackHole 2ch audio driver to the system

echo "=================================="
echo "BlackHole 2ch Installation Script"
echo "=================================="
echo ""

# Check for admin privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run with sudo privileges"
    echo "Usage: sudo $0"
    echo ""
    echo "Example:"
    echo "  sudo ./install.sh"
    exit 1
fi

# Check if we're on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Error: This script is only for macOS systems"
    exit 1
fi

# Get the script directory to find the driver
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_SOURCE="$SCRIPT_DIR/../lib/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
DRIVER_DEST="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"

# Check if driver source exists
if [ ! -d "$DRIVER_SOURCE" ]; then
    echo "❌ Error: BlackHole driver not found at: $DRIVER_SOURCE"
    echo "Please ensure the package is properly built with Nix"
    exit 1
fi

echo "📂 Driver source: $DRIVER_SOURCE"
echo "📍 Installation target: $DRIVER_DEST"
echo ""

# Check if driver is already installed
if [ -d "$DRIVER_DEST" ]; then
    echo "⚠️  BlackHole 2ch driver is already installed"
    read -p "Do you want to reinstall? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "🗑️  Removing existing driver..."
    rm -rf "$DRIVER_DEST"
fi

# Create target directory if it doesn't exist
echo "📁 Creating target directory..."
mkdir -p "$(dirname "$DRIVER_DEST")"

# Copy driver to system location
echo "📋 Copying BlackHole 2ch driver..."
cp -R "$DRIVER_SOURCE" "$DRIVER_DEST"

# Set proper permissions
echo "🔒 Setting permissions..."
chown -R root:wheel "$DRIVER_DEST"
chmod -R 755 "$DRIVER_DEST"

# Restart CoreAudio service
echo "🔄 Restarting CoreAudio service..."
killall -9 coreaudiod 2>/dev/null || true

# Wait a moment for CoreAudio to restart
sleep 2

echo ""
echo "✅ BlackHole 2ch installation completed successfully!"
echo ""
echo "📋 Next steps:"
echo "  1. Open 'Audio MIDI Setup' app (found in Applications/Utilities/)"
echo "  2. Look for 'BlackHole 2ch' in the device list"
echo "  3. You may need to restart your computer for full recognition"
echo ""
echo "💡 Usage examples:"
echo "  - Set BlackHole 2ch as output in audio applications"
echo "  - Create Multi-Output Device for monitoring + routing"
echo "  - Use with audio software like Logic Pro X, GarageBand, etc."
echo ""
echo "🗑️  To uninstall: sudo ./uninstall.sh"
echo ""