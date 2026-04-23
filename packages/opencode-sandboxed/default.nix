# Sandboxed opencode CLI wrapping the version-pinned opencode-bin.
#
# Binary version lives in packages/opencode-bin/default.nix.
{
  lib,
  opencode-bin,
  writeShellScriptBin,
  procps,
  ripgrep,
  jq,
}:
let
  sandboxProfilePath = "\${HOME}/.config/opencode/permissive-open.sb";
in
writeShellScriptBin "opencode" ''
  export PATH="${
    lib.makeBinPath [
      procps
      ripgrep
      jq
    ]
  }:$PATH"

  OPENCODE_BIN="${opencode-bin}/bin/opencode"

  # --no-sandbox: bypass sandbox and execute the binary directly.
  # Useful when invoked from an already-sandboxed context.
  if [ "''${1:-}" = "--no-sandbox" ]; then
      shift
      exec "$OPENCODE_BIN" "$@"
  fi

  if [ ! -f "${sandboxProfilePath}" ]; then
      echo "Error: Sandbox policy not found at ${sandboxProfilePath}" >&2
      echo "Please ensure agent configuration is properly installed." >&2
      exit 1
  fi

  case " $* " in
      *" --version "*|*" --help "*|*" -h "*) ;;
      *)
          echo "Running opencode with macOS Seatbelt (permissive-open)" >&2
          ;;
  esac

  exec /usr/bin/sandbox-exec -f "${sandboxProfilePath}" -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" "$OPENCODE_BIN" "$@"
''
