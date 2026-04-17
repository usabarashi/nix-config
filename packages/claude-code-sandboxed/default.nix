# Sandboxed Claude Code CLI with pre-built binary.
# Binary is fetched from Google Cloud Storage, managed independently from nixpkgs.
# Requires --impure flag for builtins.fetchurl (no hash verification).
#
# Update workflow: update `version` below, then deploy.
{
  lib,
  stdenvNoCC,
  makeBinaryWrapper,
  procps,
  ripgrep,
}:
let
  stdenv = stdenvNoCC;
  version = "2.1.112";
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
  platformKey = "${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}";

  sandboxProfilePath = "\${HOME}/.claude/permissive-open.sb";
  errorMessages = {
    profileNotFound = "Error: Sandbox policy not found at ${sandboxProfilePath}";
    installationNote = "Please ensure claude configuration is properly installed.";
  };
  sandboxNotice = "Running Claude Code with macOS Seatbelt (permissive-open)";
in
stdenv.mkDerivation {
  pname = "claude-code-sandboxed";
  inherit version;

  src = builtins.fetchurl "${baseUrl}/${version}/${platformKey}/claude";

  dontUnpack = true;
  dontBuild = true;
  __noChroot = stdenv.hostPlatform.isDarwin;
  dontStrip = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    # Install the binary as claude-unwrapped
    install -Dm755 $src $out/bin/claude-unwrapped

    # Wrap with environment variables
    wrapProgram $out/bin/claude-unwrapped \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${
        lib.makeBinPath [
          procps
          ripgrep
        ]
      }

    # Create sandbox wrapper script
    cat > $out/bin/claude <<'WRAPPER'
    #!/usr/bin/env bash
    CLAUDE_BIN="CLAUDE_BIN_PLACEHOLDER"

    # --no-sandbox: bypass sandbox and execute the binary directly.
    if [ "''${1:-}" = "--no-sandbox" ]; then
        shift
        exec "$CLAUDE_BIN" "$@"
    fi

    # Check if sandbox profile exists
    SANDBOX_PROFILE="SANDBOX_PROFILE_PLACEHOLDER"
    if [ ! -f "$SANDBOX_PROFILE" ]; then
        echo "PROFILE_NOT_FOUND_PLACEHOLDER" >&2
        echo "INSTALLATION_NOTE_PLACEHOLDER" >&2
        exit 1
    fi

    # Show sandbox mode if not using --version or help flags
    case "$*" in
        *--version*|*--help*|*-h*) ;;
        *)
            echo "SANDBOX_NOTICE_PLACEHOLDER" >&2
            ;;
    esac

    # Execute claude with sandbox
    exec /usr/bin/sandbox-exec -f "$SANDBOX_PROFILE" -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" "$CLAUDE_BIN" "$@"
    WRAPPER
    chmod +x $out/bin/claude

    substituteInPlace $out/bin/claude \
      --replace-fail 'CLAUDE_BIN_PLACEHOLDER' "$out/bin/claude-unwrapped" \
      --replace-fail 'SANDBOX_PROFILE_PLACEHOLDER' '${sandboxProfilePath}' \
      --replace-fail 'PROFILE_NOT_FOUND_PLACEHOLDER' '${errorMessages.profileNotFound}' \
      --replace-fail 'INSTALLATION_NOTE_PLACEHOLDER' '${errorMessages.installationNote}' \
      --replace-fail 'SANDBOX_NOTICE_PLACEHOLDER' '${sandboxNotice}'

    runHook postInstall
  '';

  meta = {
    description = "Sandboxed Claude Code CLI with pre-built binary";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "claude";
  };
}
