# Sandboxed Claude Code CLI with pre-built binary.
# Binary is fetched from Google Cloud Storage, managed independently from nixpkgs.
# Requires --impure flag for builtins.fetchurl (no hash verification).
#
# Update workflow: update `version` below, then deploy.
{
  lib,
  stdenvNoCC,
  writeShellScriptBin,
  procps,
  ripgrep,
}:
let
  version = "2.1.112";
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
  platformKey = "${stdenvNoCC.hostPlatform.node.platform}-${stdenvNoCC.hostPlatform.node.arch}";

  claudeBin = stdenvNoCC.mkDerivation {
    pname = "claude-code-bin";
    inherit version;
    src = builtins.fetchurl "${baseUrl}/${version}/${platformKey}/claude";
    dontUnpack = true;
    dontBuild = true;
    dontStrip = true;
    __noChroot = stdenvNoCC.hostPlatform.isDarwin;
    installPhase = "install -Dm755 $src $out/bin/claude";
    meta = {
      license = lib.licenses.unfree;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
    };
  };

  sandboxProfilePath = "\${HOME}/.claude/permissive-open.sb";
in
writeShellScriptBin "claude" ''
  export DISABLE_AUTOUPDATER=1
  export FORCE_AUTOUPDATE_PLUGINS=1
  export DISABLE_INSTALLATION_CHECKS=1
  export USE_BUILTIN_RIPGREP=0
  export PATH="${
    lib.makeBinPath [
      procps
      ripgrep
    ]
  }:$PATH"

  CLAUDE_BIN="${claudeBin}/bin/claude"

  # --no-sandbox: bypass sandbox and execute the binary directly.
  # Useful when invoked from an already-sandboxed context (e.g., Gemini CLI).
  if [ "''${1:-}" = "--no-sandbox" ]; then
      shift
      exec "$CLAUDE_BIN" "$@"
  fi

  if [ ! -f "${sandboxProfilePath}" ]; then
      echo "Error: Sandbox policy not found at ${sandboxProfilePath}" >&2
      echo "Please ensure claude configuration is properly installed." >&2
      exit 1
  fi

  case "$*" in
      *--version*|*--help*|*-h*) ;;
      *)
          echo "Running Claude Code with macOS Seatbelt (permissive-open)" >&2
          ;;
  esac

  exec /usr/bin/sandbox-exec -f "${sandboxProfilePath}" -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" "$CLAUDE_BIN" "$@"
''
