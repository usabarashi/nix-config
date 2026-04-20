# Sandboxed Claude Code CLI wrapping the version-pinned claude-code-bin.
#
# Binary version lives in packages/claude-code-bin/default.nix.
{
  lib,
  claude-code-bin,
  writeShellScriptBin,
  procps,
  ripgrep,
}:
let
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

  CLAUDE_BIN="${claude-code-bin}/bin/claude"

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

  case " $* " in
      *" --version "*|*" --help "*|*" -h "*) ;;
      *)
          echo "Running Claude Code with macOS Seatbelt (permissive-open)" >&2
          ;;
  esac

  exec /usr/bin/sandbox-exec -f "${sandboxProfilePath}" -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" "$CLAUDE_BIN" "$@"
''
