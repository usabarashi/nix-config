# Sandboxed opencode CLI wrapping the version-pinned opencode-bin.
#
# Binary version lives in packages/opencode-bin/default.nix.
{
  lib,
  cacert,
  codex-bin,
  coreutils,
  opencode-bin,
  stdenv,
  writeShellScriptBin,
  procps,
  ripgrep,
  jq,
  git,
  gh,
}:
let
  codexAuthKeyringImport = stdenv.mkDerivation {
    pname = "codex-auth-keyring-import";
    version = "1";
    src = ./codex-auth-keyring-import.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -Wall -Wextra -Werror -Wno-deprecated-declarations -O2 "$src" \
        -framework CoreFoundation \
        -framework Security \
        -o codex-auth-keyring-import
    '';
    installPhase = ''
      install -Dm755 codex-auth-keyring-import \
        "$out/bin/codex-auth-keyring-import"
    '';
  };
in
writeShellScriptBin "opencode" ''
  export PATH="${
    lib.makeBinPath [
      procps
      ripgrep
      jq
      git
      gh
      codex-bin
      coreutils
    ]
  }:$PATH"

  OPENCODE_BIN="${opencode-bin}/bin/opencode"
  SANDBOX_PROFILE_DIR="$HOME/.config/opencode"
  SANDBOX_PROFILE_FILE="cloud-restricted.sb"
  AGENT_CONFIG_DIR="$HOME/.config/opencode"
  AGENT_CONFIG_FILE="$AGENT_CONFIG_DIR/opencode.json"
  AGENT_COMMANDS_DIR="$AGENT_CONFIG_DIR/commands"
  AGENT_TOOLS_DIR="$AGENT_CONFIG_DIR/tools"
  AGENT_SKILLS_DIR="$AGENT_CONFIG_DIR/skills"
  AGENT_STATE_DIR="$HOME/.local/share/opencode"
  AGENT_AUX_STATE_DIR="$HOME/.local/state/opencode"
  AGENT_CACHE_DIR="$HOME/.cache/opencode"
  CODEX_AUTH_FILE="$HOME/.codex/auth.json"
  CODEX_BIN="${codex-bin}/bin/codex"
  CODEX_AUTH_KEYRING_IMPORT="${codexAuthKeyringImport}/bin/codex-auth-keyring-import"
  CODEX_HOME_DIR="$AGENT_CACHE_DIR/codex-second-opinion-${codex-bin.version}"
  AGENT_TMP_DIR=""
  TARGET_DIR="$(pwd -P)"
  export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"

  cleanup_cloud_tmp() {
      if [ -n "$AGENT_TMP_DIR" ]; then
          rm -rf -- "$AGENT_TMP_DIR"
          AGENT_TMP_DIR=""
      fi
  }
  trap cleanup_cloud_tmp EXIT HUP INT TERM

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
      # OpenCode does not provide a merge-safe "disable every MCP" setting.
      # Skip repository-controlled configuration entirely in this mode, then
      # disable every MCP inherited from the trusted user configuration below.
      export OPENCODE_DISABLE_PROJECT_CONFIG=1
      export OPENCODE_DISABLE_CLAUDE_CODE=1
      # Pure mode suppresses all external plugins (both config-declared and
      # auto-discovered under .opencode/plugin(s)). User tools under the
      # managed tools/ directory are loaded on a separate path and survive.
      export OPENCODE_PURE=1

      mkdir -p "$CODEX_HOME_DIR"
      CODEX_HOME_CANONICAL="$(cd "$CODEX_HOME_DIR" && pwd -P)"
      CODEX_KEYRING_HASH="$(printf '%s' "$CODEX_HOME_CANONICAL" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-16)"
      CODEX_KEYRING_ACCOUNT="cli|$CODEX_KEYRING_HASH"
      if ! /usr/bin/security find-generic-password \
          -s "Codex Auth" \
          -a "$CODEX_KEYRING_ACCOUNT" >/dev/null 2>&1; then
          if [ ! -r "$CODEX_AUTH_FILE" ]; then
              echo "Error: Codex auth not found at $CODEX_AUTH_FILE" >&2
              exit 1
          fi
          if ! jq -c . "$CODEX_AUTH_FILE" \
              | "$CODEX_AUTH_KEYRING_IMPORT" \
                  "Codex Auth" \
                  "$CODEX_KEYRING_ACCOUNT" \
                  "$CODEX_BIN"; then
              echo "Error: Failed to initialize the Codex-only Keychain credential" >&2
              exit 1
          fi
      fi
      export OPENCODE_CODEX_HOME="$CODEX_HOME_CANONICAL"
      export OPENCODE_CODEX_OUTER_SANDBOX="cloud-restricted"

      TMP_ROOT="$(cd "''${TMPDIR:-/private/tmp}" && pwd -P)"
      AGENT_TMP_DIR="$(/usr/bin/mktemp -d "''${TMP_ROOT%/}/opencode-cloud.XXXXXX")"
      /bin/chmod 700 "$AGENT_TMP_DIR"
      export TMPDIR="$AGENT_TMP_DIR/"
      export TMP="$AGENT_TMP_DIR"
      export TEMP="$AGENT_TMP_DIR"

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

      # Home Manager may expose these as chained out-of-store symlinks. Pass
      # only the resolved managed inputs instead of allowing their repository.
      AGENT_CONFIG_FILE="$(realpath "$OPENCODE_CONFIG_FILE")"
      AGENT_COMMANDS_DIR="$(realpath "$AGENT_COMMANDS_DIR")"
      AGENT_TOOLS_DIR="$(realpath "$AGENT_TOOLS_DIR")"
      AGENT_SKILLS_DIR="$(realpath "$AGENT_SKILLS_DIR")"
  fi

  case " $* " in
      *" --version "*|*" --help "*|*" -h "*) ;;
      *)
          echo "Running opencode with macOS Seatbelt ($SANDBOX_PROFILE_FILE)" >&2
          ;;
  esac

  /usr/bin/sandbox-exec -f "$SANDBOX_PROFILE_PATH" \
      -D TARGET_DIR="$TARGET_DIR" \
      -D HOME_DIR="$HOME" \
      -D AGENT_CONFIG_DIR="$AGENT_CONFIG_DIR" \
      -D AGENT_CONFIG_FILE="$AGENT_CONFIG_FILE" \
      -D AGENT_COMMANDS_DIR="$AGENT_COMMANDS_DIR" \
      -D AGENT_TOOLS_DIR="$AGENT_TOOLS_DIR" \
      -D AGENT_SKILLS_DIR="$AGENT_SKILLS_DIR" \
      -D AGENT_STATE_DIR="$AGENT_STATE_DIR" \
      -D AGENT_AUX_STATE_DIR="$AGENT_AUX_STATE_DIR" \
      -D AGENT_CACHE_DIR="$AGENT_CACHE_DIR" \
      -D AGENT_TMP_DIR="$AGENT_TMP_DIR" \
      "$OPENCODE_BIN" "$@"
  exit "$?"
''
