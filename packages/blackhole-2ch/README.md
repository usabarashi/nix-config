# BlackHole 2ch - Nix Package

A Nix package for [BlackHole](https://existential.audio/blackhole/) 2-channel audio loopback driver.

## ⚠️ Important Notice

**Manual installation required.** This package provides tools and files but cannot automatically install system-level audio drivers.

## 📦 Package Contents

- BlackHole 2ch audio driver (extracted from official PKG)
- CLI management tool (`blackhole`)
- Legacy compatibility scripts (`blackhole-install`, `blackhole-uninstall`, `blackhole-status`)

## 🎛️ CLI Commands

```bash
# Check installation status
blackhole status

# Install driver (requires sudo)
sudo blackhole install

# Uninstall driver (requires sudo)
sudo blackhole uninstall

# Show help and usage
blackhole help
```

## 🛠️ Installation Steps

1. **Build Package**: Ensure this package is built through your Nix configuration
2. **Install Driver**: Run `sudo blackhole install`
3. **Verify**: Check Audio MIDI Setup app for "BlackHole 2ch" device

## 🗑️ Uninstallation

```bash
# Interactive uninstallation with safety checks
sudo blackhole uninstall
```

## 📋 Technical Details

- **Channels**: 2 (stereo)
- **Installation Location**: `/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver`
- **Requirements**: macOS 10.10+, administrator privileges
- **CoreAudio restart**: Automatic via CLI tool

## 🔗 Documentation

- [Official BlackHole Documentation](https://github.com/ExistentialAudio/BlackHole/wiki)
- [Usage Examples and Tutorials](https://existential.audio/howto/)
- [Audio MIDI Setup Guide](https://github.com/ExistentialAudio/BlackHole/wiki/Multi-Output-Device)

## 📝 Notes

- **Why Manual Installation?**: Audio drivers require system-level privileges that Nix cannot automatically manage
- **Persistence**: Installed drivers persist independently of Nix package management
- **Updates**: Reinstall when package is updated to get latest driver version