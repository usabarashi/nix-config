{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.blackhole;

  # Import the BlackHole package using relative path
  blackhole-2ch = pkgs.callPackage ../../packages/blackhole-2ch/default.nix { };

in
{
  # Module options definition
  options.programs.blackhole = {
    enable = lib.mkEnableOption "BlackHole 2ch audio loopback driver";

    package = lib.mkOption {
      type = lib.types.package;
      default = blackhole-2ch;
      description = "BlackHole package to use";
    };

    autoInstall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        WARNING: This option requires manual confirmation and is NOT recommended.

        When enabled, this will attempt to automatically install the BlackHole driver
        to the system location during nix-darwin activation. This requires:
        - Administrator privileges during build
        - Manual intervention for system security
        - Potential conflicts with existing installations

        It is strongly recommended to keep this disabled and use manual installation:
        1. Build the package: programs.blackhole.enable = true;
        2. Run: sudo blackhole-install
      '';
    };

    enableUserInstructions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show installation instructions when package is enabled";
    };
  };

  # Module implementation
  config = lib.mkIf cfg.enable {

    # Add BlackHole package to system packages for easy access
    environment.systemPackages = [ cfg.package ];

    # Create helpful aliases for installation/uninstallation
    environment.shellAliases = {
      blackhole-install = "sudo ${cfg.package}/bin/blackhole-install";
      blackhole-uninstall = "sudo ${cfg.package}/bin/blackhole-uninstall";
      blackhole-status = "ls -la /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver 2>/dev/null && echo 'BlackHole 2ch: Installed' || echo 'BlackHole 2ch: Not installed'";
    };

    # Show user instructions on activation (only if enabled)
    system.activationScripts.blackhole-instructions = lib.mkIf cfg.enableUserInstructions ''
      echo ""
      echo "🔊 BlackHole 2ch Audio Driver Package Available"
      echo "============================================="
      echo ""
      echo "📦 Package Location: ${cfg.package}"
      echo ""
      echo "⚠️  MANUAL INSTALLATION REQUIRED:"
      echo "   BlackHole requires system-level installation that cannot be"
      echo "   automated by Nix. Please install manually using:"
      echo ""
      echo "   💾 Install:     sudo blackhole-install"
      echo "   🗑️ Uninstall:   sudo blackhole-uninstall" 
      echo "   📊 Status:      blackhole-status"
      echo ""
      echo "📖 Documentation: ${cfg.package}/share/doc/blackhole-2ch/README.md"
      echo "📁 Package Contents:"
      echo "   - BlackHole2ch.driver (audio driver)"
      echo "   - install.sh / uninstall.sh (installation scripts)"
      echo "   - README.md (detailed documentation)"
      echo ""
      echo "💡 Quick Start:"
      echo "   1. sudo blackhole-install"
      echo "   2. Open Audio MIDI Setup to verify 'BlackHole 2ch' appears"
      echo "   3. Configure your audio applications to use BlackHole 2ch"
      echo ""
    '';

    # Optional automatic installation (NOT RECOMMENDED)
    system.activationScripts.blackhole-auto-install = lib.mkIf cfg.autoInstall ''
      echo ""
      echo "⚠️  WARNING: Attempting automatic BlackHole installation..."
      echo "This is experimental and may require manual intervention."
      echo ""

      # Check if already installed
      if [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]; then
        echo "ℹ️  BlackHole 2ch already installed, skipping."
      else
        echo "📦 Installing BlackHole 2ch driver..."
        
        # Attempt to copy driver (requires root privileges)
        if cp -R "${cfg.package}/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" "/Library/Audio/Plug-Ins/HAL/" 2>/dev/null; then
          # Set proper permissions
          chown -R root:wheel "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" 2>/dev/null || true
          chmod -R 755 "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" 2>/dev/null || true
          
          # Restart CoreAudio
          killall -9 coreaudiod 2>/dev/null || true
          
          echo "✅ BlackHole 2ch installed successfully"
        else
          echo "❌ Failed to install BlackHole 2ch automatically"
          echo "   Please run: sudo blackhole-install"
        fi
      fi
      echo ""
    '';

  };
}
