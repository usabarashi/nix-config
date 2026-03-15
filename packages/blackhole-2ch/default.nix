{
  lib,
  stdenv,
  fetchurl,
  cpio,
  gzip,
  xar,
}:

# ⚠️ WARNING: Manual uninstallation required
# This package installs system-level audio drivers that are NOT
# automatically removed when disabled in Nix configuration.
# To uninstall: run ./uninstall.sh manually or use:
#   sudo rm -rf /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver
#   sudo killall -9 coreaudiod

stdenv.mkDerivation rec {
  pname = "blackhole-2ch";
  version = "0.6.1";

  src = fetchurl {
    url = "https://existential.audio/downloads/BlackHole2ch-${version}.pkg";
    sha256 = "c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988";
  };

  nativeBuildInputs = [
    cpio
    gzip
    xar
  ];

  # PKG file extraction and driver file preparation
  unpackPhase = ''
    runHook preUnpack

    # Create temporary directory for PKG expansion
    mkdir -p ./pkg-expanded
    cd ./pkg-expanded

    # Extract the PKG file using xar (cross-platform alternative to pkgutil)
    echo "Extracting PKG file with xar..."
    xar -xf $src

    # Find and extract Payload files
    for payload in */Payload; do
      if [ -f "$payload" ]; then
        echo "Extracting payload: $payload"
        cd "$(dirname "$payload")"
        gunzip -dc Payload | cpio -i
        cd ..
      fi
    done

    # Find and prepare the BlackHole driver
    find . -name "BlackHole2ch.driver" -type d | head -1 | xargs -I {} cp -R {} ../BlackHole2ch.driver
    cd ..

    runHook postUnpack
  '';

  # No build phase needed - we just package the extracted driver
  dontBuild = true;

  installPhase = ''
        runHook preInstall

        # Create output directory structure
        mkdir -p $out/Library/Audio/Plug-Ins/HAL
        mkdir -p $out/bin

        # Copy the BlackHole driver
        if [ -d "BlackHole2ch.driver" ]; then
          cp -R BlackHole2ch.driver $out/Library/Audio/Plug-Ins/HAL/
        else
          echo "Error: BlackHole2ch.driver not found"
          exit 1
        fi

        # Install the comprehensive CLI tool
        cp ${./blackhole-cli.sh} $out/bin/blackhole
        
        # Replace placeholder with actual package path
        substituteInPlace $out/bin/blackhole \
          --replace "@PACKAGE_PATH@" "$out"
        
        # Make CLI executable
        chmod +x $out/bin/blackhole
        
        # Create legacy compatibility scripts
        cat > $out/bin/blackhole-install << 'EOF'
    #!/bin/bash
    # Legacy compatibility wrapper
    exec "$(dirname "$0")/blackhole" install "$@"
    EOF

        cat > $out/bin/blackhole-uninstall << 'EOF'
    #!/bin/bash
    # Legacy compatibility wrapper  
    exec "$(dirname "$0")/blackhole" uninstall "$@"
    EOF

        cat > $out/bin/blackhole-status << 'EOF'
    #!/bin/bash
    # Status check wrapper
    exec "$(dirname "$0")/blackhole" status "$@"
    EOF

        # Make all scripts executable
        chmod +x $out/bin/blackhole-install
        chmod +x $out/bin/blackhole-uninstall
        chmod +x $out/bin/blackhole-status

        runHook postInstall
  '';

  meta = with lib; {
    description = "BlackHole 2ch - Virtual Audio Loopback Driver for macOS";
    longDescription = ''
      BlackHole is a modern macOS virtual audio loopback driver that allows
      applications to pass audio to other applications with zero additional latency.

      This package provides the 2-channel version of BlackHole.

      IMPORTANT: This package requires manual installation and uninstallation:
      - Install: sudo blackhole-install
      - Uninstall: sudo blackhole-uninstall

      System files are placed in /Library/Audio/Plug-Ins/HAL/ and are NOT
      automatically managed by Nix package management.
    '';
    homepage = "https://existential.audio/blackhole/";
    license = licenses.gpl3;
    platforms = platforms.darwin;
    maintainers = [ ];

    # This is not a typical Nix package as it requires manual system installation
    broken = false;
  };
}
