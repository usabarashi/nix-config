# Sandboxed opencode CLI wrapping the version-pinned opencode-bin.
#
# Binary version lives in packages/opencode-bin/default.nix.
{
  lib,
  cacert,
  codex-bin,
  opencode-bin,
  writeShellScriptBin,
  procps,
  ripgrep,
  jq,
  git,
}:
writeShellScriptBin "opencode" ''
  export PATH="${
    lib.makeBinPath [
      procps
      ripgrep
      jq
      git
      codex-bin
    ]
  }:$PATH"

  OPENCODE_BIN="${opencode-bin}/bin/opencode"
  SANDBOX_PROFILE_DIR="$HOME/.config/opencode"
  SANDBOX_PROFILE_FILE="cloud-restricted.sb"
  AGENT_CONFIG_DIR="$HOME/.config/opencode"
  AGENT_STATE_DIR="$HOME/.local/share/opencode"
  AGENT_AUX_STATE_DIR="$HOME/.local/state/opencode"
  AGENT_CACHE_DIR="$HOME/.cache/opencode"
  CODEX_AUTH_FILE="$HOME/.codex/auth.json"
  CODEX_HOME_DIR="$AGENT_CACHE_DIR/codex-second-opinion"
  export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"

  # --no-sandbox: bypass sandbox and execute the binary directly.
  # Useful when invoked from an already-sandboxed context.
  if [ "''${1:-}" = "--no-sandbox" ]; then
      shift
      exec "$OPENCODE_BIN" "$@"
  fi

  case "''${1:-}" in
      --seatbelt)
          if [ "$#" -lt 2 ]; then
              echo "Error: --seatbelt requires a .sb file name" >&2
              exit 2
          fi
          SANDBOX_PROFILE_FILE="$2"
          shift 2
          ;;
      --seatbelt=*)
          SANDBOX_PROFILE_FILE="''${1#--seatbelt=}"
          shift
          ;;
      --list-seatbelts)
          found=0
          for profile_path in "$SANDBOX_PROFILE_DIR"/*.sb; do
              [ -e "$profile_path" ] || continue
              printf '%s\n' "''${profile_path##*/}"
              found=1
          done
          if [ "$found" -eq 0 ]; then
              echo "No Seatbelt profiles found in $SANDBOX_PROFILE_DIR" >&2
              exit 1
          fi
          exit 0
          ;;
  esac

  case "$SANDBOX_PROFILE_FILE" in
      *.sb)
          case "$SANDBOX_PROFILE_FILE" in
              */*)
                  echo "Error: --seatbelt accepts a file name, not a path" >&2
                  exit 2
                  ;;
          esac
          ;;
      *)
          echo "Error: Seatbelt profile must have a .sb extension: $SANDBOX_PROFILE_FILE" >&2
          exit 2
          ;;
  esac

  SANDBOX_PROFILE_PATH="$SANDBOX_PROFILE_DIR/$SANDBOX_PROFILE_FILE"
  if [ ! -f "$SANDBOX_PROFILE_PATH" ]; then
      echo "Error: Sandbox policy not found at $SANDBOX_PROFILE_PATH" >&2
      echo "Run 'opencode --list-seatbelts' to list installed profiles." >&2
      echo "Please ensure agent configuration is properly installed." >&2
      exit 1
  fi

  if [ "$SANDBOX_PROFILE_FILE" = "cloud-restricted.sb" ]; then
      mkdir -p "$CODEX_HOME_DIR"
      ln -sfn "$CODEX_AUTH_FILE" "$CODEX_HOME_DIR/auth.json"
      export CODEX_HOME="$CODEX_HOME_DIR"
      export OPENCODE_CODEX_OUTER_SANDBOX="cloud-restricted"
      OPENCODE_CONFIG_FILE="$HOME/.config/opencode/opencode.json"
      if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
          echo "Error: OpenCode config not found at $OPENCODE_CONFIG_FILE" >&2
          exit 1
      fi
      OPENCODE_CONFIG_CONTENT="$(
          jq -c '
              {
                  autoshare: false,
                  permission: {
                      bash: "ask",
                      edit: "ask",
                      webfetch: "deny",
                      external_directory: "deny"
                  },
                  mcp: (
                      (.mcp // {})
                      | with_entries(.value = { enabled: false })
                  ),
                  agent: (
                      (.agent // {})
                      | with_entries(
                          .value = {
                              permission: {
                                  bash: "ask",
                                  edit: "ask",
                                  webfetch: "deny",
                                  external_directory: "deny"
                              }
                          }
                      )
                  )
              }
          ' "$OPENCODE_CONFIG_FILE"
      )"
      export OPENCODE_CONFIG_CONTENT
  fi

  case " $* " in
      *" --version "*|*" --help "*|*" -h "*) ;;
      *)
          echo "Running opencode with macOS Seatbelt ($SANDBOX_PROFILE_FILE)" >&2
          ;;
  esac

  exec /usr/bin/sandbox-exec -f "$SANDBOX_PROFILE_PATH" \
      -D TARGET_DIR="$(pwd)" \
      -D HOME_DIR="$HOME" \
      -D AGENT_CONFIG_DIR="$AGENT_CONFIG_DIR" \
      -D AGENT_STATE_DIR="$AGENT_STATE_DIR" \
      -D AGENT_AUX_STATE_DIR="$AGENT_AUX_STATE_DIR" \
      -D AGENT_CACHE_DIR="$AGENT_CACHE_DIR" \
      -D CODEX_AUTH_FILE="$CODEX_AUTH_FILE" \
      "$OPENCODE_BIN" "$@"
''
