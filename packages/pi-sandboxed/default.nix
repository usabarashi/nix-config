# Sandboxed Pi CLI. Runs the version-pinned pi-bin under macOS Seatbelt.
#
# Two profiles are supported, both shared with the claude wrapper:
#   * cloud-restricted.sb (default): paid cloud models. The project directory and
#     Pi's own runtime state are the only writable trees, plus HTTPS/DNS/loopback
#     egress and the Nix daemon.
#   * free-tier.sb: LOW-TRUST free-tier cloud providers (Google/Groq/OpenRouter
#     no-cost). No Keychain, no gh/git config, no Nix access; an independent
#     minimal config and a dedicated, isolated runtime root. Credentials live in
#     a free-tier-only, sandbox-immutable auth.json provisioned outside.
#
# Node.js (with npm) is added to the cloud-restricted sandbox PATH here -- inside
# the wrapper only -- so Pi's package installer can fetch provider extensions
# such as @rahularya01/pi-cursor. It is deliberately NOT a nix-config-wide
# package, and is not exposed in free-tier sessions (which install no packages).
#
# Binary version lives in packages/pi-bin/default.nix.
{
  _1password-cli,
  cacert,
  chrome-devtools-mcp,
  coreutils,
  freeTierConfig,
  gh,
  git,
  jq,
  lib,
  nodejs_22,
  pi-bin,
  procps,
  ripgrep,
  sandbox-supervisor,
  writeShellScriptBin,
}:
let
  # 1Password CLI is used only in the OUTER (unsandboxed) wrapper context to
  # provision the dedicated GitHub agent PAT. It is deliberately NOT on the
  # sandbox PATH, and cloud-restricted.sb denies it on the exec list.
  opBin = "${_1password-cli}/bin/op";
  ghBin = "${gh}/bin/gh";
in
writeShellScriptBin "pi" ''
  export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"

  # git-agent-guard / nix-agent-guard are materialized in ~/.pi/agent/bin by
  # home-manager; this dir precedes the store binaries so agent-spawned git/nix
  # hit the shims. nodejs supplies npm for Pi's package installer and is
  # confined to this wrapper's environment (never the user's PATH). Set before
  # any exec (including --no-sandbox) so package installs always resolve npm.
  export PATH="$HOME/.pi/agent/bin:${
    lib.makeBinPath [
      nodejs_22
      procps
      ripgrep
      jq
      git
      gh
      coreutils
    ]
  }:$PATH"

  PI_BIN="${pi-bin}/bin/pi"
  SANDBOX_PROFILE_DIR="$HOME/.pi/agent"
  SANDBOX_PROFILE_FILE="cloud-restricted.sb"
  # Pi's runtime state (auth.json, sessions, installed packages, logs) is
  # read+write. Its configuration files are out-of-store symlinks into this
  # repo, and Seatbelt matches on the RESOLVED path, so the wrapper realpaths
  # each managed input before launching.
  AGENT_STATE_DIR="$HOME/.pi/agent"
  AGENT_AUX_STATE_DIR="$HOME/.pi/agent"
  AGENT_CACHE_DIR="$HOME/.cache/pi"
  # Inert literal grant the shared profile expects; never created.
  AGENT_CLAUDE_JSON="$HOME/.pi/agent/.claude-json-inert"
  LAUNCH_DIR="$(pwd -P)"
  TARGET_DIR="$LAUNCH_DIR"
  unset AGENT_NIX_REAL_BIN AGENT_NIX_EXPECTED_VERSION AGENT_TARGET_DIR AGENT_TMP_DIR
  AGENT_TMP_DIR=""

  cleanup_cloud_tmp() {
      if [ -n "$AGENT_TMP_DIR" ]; then
          rm -rf -- "$AGENT_TMP_DIR"
          AGENT_TMP_DIR=""
      fi
  }
  trap cleanup_cloud_tmp EXIT

  # --no-sandbox: bypass the Seatbelt and run the binary directly. Needed for
  # flows that require a browser (OAuth `/login`, `cursor` login) and useful
  # from an already-sandboxed context.
  if [ "''${1:-}" = "--no-sandbox" ]; then
      shift
      exec "$PI_BIN" "$@"
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
      echo "Run 'pi --list-seatbelts' to list installed profiles." >&2
      echo "Please ensure Pi configuration is properly installed." >&2
      exit 1
  fi

  # Fresh private per-invocation temp dir (never the caller's TMPDIR).
  TMP_ROOT_RAW="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '%s' "/private/tmp")"
  TMP_ROOT="$(cd "$TMP_ROOT_RAW" && pwd -P)"

  # ------------------------------------------------------------------ #
  # free-tier.sb: low-trust providers. Separate code path (different
  # parameter mapping, env, and roots) from the cloud profile below.
  # ------------------------------------------------------------------ #
  if [ "$SANDBOX_PROFILE_FILE" = "free-tier.sb" ]; then
      FREE_ROOT="$HOME/.local/share/pi-free"
      FREE_AGENT_DIR="$FREE_ROOT/agent"
      FREE_DATA_DIR="$FREE_ROOT/data"
      FREE_CACHE_DIR="$FREE_ROOT/cache"

      # TARGET_DIR guard: refuse the filesystem root, $HOME, any ancestor of
      # $HOME, and overlap (either direction) with sensitive protected trees.
      # `~/.codex` stays protected even though Codex support was removed: the
      # stale state tree is only cleaned up as a manual step, and this guard
      # must not lapse while it can still exist.
      reject=0
      [ "$TARGET_DIR" = "/" ] && reject=1
      [ "$TARGET_DIR" = "$HOME" ] && reject=1
      case "/$HOME/" in "/$TARGET_DIR/"*) reject=1 ;; esac
      if [ "$reject" = "1" ]; then
          echo "Error: free-tier refuses to run from a directory that is or contains your home or the filesystem root: $TARGET_DIR" >&2
          exit 2
      fi
      for protected in \
          "$HOME/.config" \
          "$HOME/.local" \
          "$HOME/.ssh" \
          "$HOME/.pi" \
          "$HOME/.codex" \
          "$HOME/.claude" \
          "$HOME/.cursor" \
          "$FREE_ROOT"; do
          reject=0
          case "/$protected/" in "/$TARGET_DIR/"*) reject=1 ;; esac
          case "/$TARGET_DIR/" in "/$protected/"*) reject=1 ;; esac
          if [ "$reject" = "1" ]; then
              echo "Error: free-tier refuses to run from a protected directory: $TARGET_DIR (conflicts with $protected)" >&2
              exit 2
          fi
      done

      # Dedicated roots: fresh, 0700, no symlink components anywhere on the
      # FREE_ROOT path (a symlinked ancestor would desync the literal Seatbelt
      # params from the resolved filesystem location).
      walk="$FREE_ROOT"
      while [ "$walk" != "/" ] && [ -n "$walk" ]; do
          if [ -L "$walk" ]; then
              echo "Error: free-tier base path has a symlink component: $walk" >&2
              exit 2
          fi
          walk="$(dirname "$walk")"
      done
      unset walk
      mkdir -p "$FREE_AGENT_DIR" "$FREE_DATA_DIR" "$FREE_CACHE_DIR"
      for d in "$FREE_ROOT" "$FREE_AGENT_DIR" "$FREE_DATA_DIR" "$FREE_CACHE_DIR"; do
          if [ -L "$d" ]; then
              echo "Error: free-tier path has a symlink component: $d" >&2
              exit 2
          fi
          chmod 700 "$d" 2>/dev/null || true
      done

      # Independent minimal config (immutable Nix-store content copied in):
      # free-tier provider whitelist + chrome-devtools MCP only. Remove the
      # destinations first so a previous (possibly compromised) session cannot
      # leave a symlink that this copy would follow outside the sandbox.
      rm -f -- "$FREE_AGENT_DIR/settings.json" "$FREE_AGENT_DIR/mcp.json"
      cp -f "${freeTierConfig}/settings.json" "$FREE_AGENT_DIR/settings.json"
      cp -f "${freeTierConfig}/mcp.json" "$FREE_AGENT_DIR/mcp.json"

      # Credentials are provisioned OUTSIDE the sandbox and are immutable during
      # the session (free-tier.sb denies writes to auth.json).
      if [ ! -f "$FREE_AGENT_DIR/auth.json" ]; then
          echo "Error: free-tier auth.json not found: $FREE_AGENT_DIR/auth.json" >&2
          echo "  Provision free-tier provider keys there before running (fail-closed)." >&2
          exit 1
      fi
      FREE_UID="$(/usr/bin/id -u 2>/dev/null || echo "")"
      if [ "$(/usr/bin/stat -f%u "$FREE_AGENT_DIR/auth.json" 2>/dev/null || echo EMPTY)" != "$FREE_UID" ]; then
          echo "Error: free-tier auth.json uid mismatch" >&2
          exit 2
      fi
      if [ "$(/usr/bin/stat -f%l "$FREE_AGENT_DIR/auth.json" 2>/dev/null || echo EMPTY)" != "1" ]; then
          echo "Error: free-tier auth.json link count is not 1" >&2
          exit 2
      fi

      AGENT_TMP_DIR="$(/usr/bin/mktemp -d "''${TMP_ROOT%/}/pi-free.XXXXXX")"
      /bin/chmod 700 "$AGENT_TMP_DIR"

      # Store-resolved tools only; no node (no package installs), no git/gh
      # (free-tier.sb exec-denies their remotes). chrome-devtools-mcp is needed
      # by the free-tier mcp.json and pin its own Node internally.
      FREE_PATH="${chrome-devtools-mcp}/bin:${
        lib.makeBinPath [
          procps
          ripgrep
          jq
          coreutils
        ]
      }"

      case " $* " in
          *" --version "*|*" --help "*|*" -h "*) ;;
          *) echo "Running Pi with macOS Seatbelt (free-tier.sb)" >&2 ;;
      esac

      exec "${sandbox-supervisor}/bin/sandbox-supervisor" --cleanup "$AGENT_TMP_DIR" -- \
          /usr/bin/env -i \
          "PATH=$FREE_PATH" \
          "HOME=$HOME" \
          "TERM=''${TERM:-xterm-256color}" \
          "USER=''${USER:-$LOGNAME}" \
          "LOGNAME=''${LOGNAME:-$USER}" \
          "SHELL=/bin/zsh" \
          "TMPDIR=$AGENT_TMP_DIR/" \
          "TMP=$AGENT_TMP_DIR" \
          "TEMP=$AGENT_TMP_DIR" \
          "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt" \
          "PI_CODING_AGENT_DIR=$FREE_AGENT_DIR" \
          "XDG_DATA_HOME=$FREE_DATA_DIR" \
          "XDG_STATE_HOME=$FREE_ROOT" \
          "XDG_CACHE_HOME=$FREE_CACHE_DIR" \
          /usr/bin/sandbox-exec -f "$SANDBOX_PROFILE_PATH" \
          -D TARGET_DIR="$TARGET_DIR" \
          -D HOME_DIR="$HOME" \
          -D AGENT_CONFIG_DIR="$FREE_AGENT_DIR" \
          -D AGENT_CONFIG_FILE="$FREE_AGENT_DIR/settings.json" \
          -D AGENT_COMMANDS_DIR="$FREE_AGENT_DIR/prompts" \
          -D AGENT_TOOLS_DIR="$FREE_AGENT_DIR/extensions" \
          -D AGENT_SKILLS_DIR="$FREE_AGENT_DIR/skills" \
          -D AGENT_DATA_DIR="$FREE_DATA_DIR" \
          -D AGENT_STATE_DIR="$FREE_AGENT_DIR" \
          -D AGENT_AUX_STATE_DIR="$FREE_AGENT_DIR" \
          -D AGENT_CACHE_DIR="$FREE_CACHE_DIR" \
          -D AGENT_AUTH_FILE="$FREE_AGENT_DIR/auth.json" \
          -D AGENT_TMP_DIR="$AGENT_TMP_DIR" \
          "$PI_BIN" "$@"
  fi

  # ------------------------------------------------------------------ #
  # cloud-restricted.sb (default).
  # ------------------------------------------------------------------ #
  # Managed inputs (fail closed if activation is incomplete). Realpath resolves
  # the out-of-store symlinks into this repo, which is what Seatbelt evaluates.
  require() {
      if [ ! -e "$1" ]; then
          echo "Error: managed path missing: $1" >&2
          exit 1
      fi
      ${coreutils}/bin/realpath "$1"
  }
  AGENT_CONFIG_FILE="$(require "$HOME/.pi/agent/settings.json")"
  AGENT_CONFIG_DIR="$(dirname "$AGENT_CONFIG_FILE")"
  AGENT_COMMANDS_DIR="$(require "$HOME/.pi/agent/prompts")"
  AGENT_TOOLS_DIR="$(require "$HOME/.pi/agent/extensions")"
  AGENT_SKILLS_DIR="$(require "$HOME/.pi/agent/skills")"

  # Workspace flake root: nearest ancestor of the launch dir containing flake.nix,
  # never above $HOME or "/". This becomes TARGET_DIR (the readable/writable
  # project tree) and drives the nix guard.
  FLAKE_ROOT=""
  _d="$LAUNCH_DIR"
  while [ -n "$_d" ] && [ "$_d" != "/" ]; do
      if [ -f "$_d/flake.nix" ]; then
          FLAKE_ROOT="$_d"
          break
      fi
      case "$_d" in
          "$HOME") break ;;
      esac
      _d="$(dirname "$_d")"
  done
  unset _d
  case "$FLAKE_ROOT" in
      "" | / | "$HOME") FLAKE_ROOT="" ;;
  esac
  if [ -n "$FLAKE_ROOT" ]; then
      TARGET_DIR="$FLAKE_ROOT"
  fi

  # Scrub inherited GitHub credential environment variables.
  unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN

  AGENT_TMP_DIR="$(/usr/bin/mktemp -d "''${TMP_ROOT%/}/pi-cloud.XXXXXX")"
  /bin/chmod 700 "$AGENT_TMP_DIR"
  export TMPDIR="$AGENT_TMP_DIR/"
  export TMP="$AGENT_TMP_DIR"
  export TEMP="$AGENT_TMP_DIR"

  # Nix guard shim environment: only with a workspace flake root, otherwise the
  # shim fails closed.
  if [ -n "$FLAKE_ROOT" ]; then
      mkdir -p "$AGENT_TMP_DIR/nix/config" "$AGENT_TMP_DIR/nix/state" "$AGENT_TMP_DIR/nix/cache"
      export AGENT_TARGET_DIR="$TARGET_DIR"
      export AGENT_TMP_DIR="$AGENT_TMP_DIR"
  fi

  # Caches: the Seatbelt denies ~/Library/Caches and ~/.cache, so point XDG
  # tools at the granted cache dir.
  mkdir -p "$AGENT_CACHE_DIR"
  export XDG_CACHE_HOME="$AGENT_CACHE_DIR"
  export TREEFMT_NO_CACHE=1

  # npm config: the sandbox cannot read ~/.npmrc, so pin the Takumi Guard
  # registry proxy and a writable cache here instead of ~/.npm.
  export npm_config_registry="https://npm.flatt.tech/"
  export npm_config_cache="$AGENT_CACHE_DIR/npm"
  export npm_config_update_notifier="false"

  # Local MCP servers are resolved by name from PATH inside the sandbox. A PATH
  # hit under /etc/profiles resolves to a vnode path the profile does not grant,
  # so re-link each configured stdio command from its resolved Nix store path
  # into the private temp dir and put that first on PATH (same as the claude
  # wrapper). Runs before sandbox-exec, so resolving the symlink chain is
  # unrestricted; the temp dir is private (0700) and removed on exit.
  MCP_BIN_DIR="$AGENT_TMP_DIR/mcp-bin"
  mkdir -p "$MCP_BIN_DIR"
  while IFS= read -r mcp_cmd; do
      [ -z "$mcp_cmd" ] && continue
      case "$mcp_cmd" in
          /*) mcp_target="$mcp_cmd" ;;
          *) mcp_target="$(command -v "$mcp_cmd" 2>/dev/null || true)" ;;
      esac
      [ -z "$mcp_target" ] && continue
      mcp_real="$(realpath "$mcp_target" 2>/dev/null || echo "$mcp_target")"
      mcp_name="$(basename "$mcp_cmd")"
      ln -sfn "$mcp_real" "$MCP_BIN_DIR/$mcp_name"
  done < <(jq -r '.mcpServers // {} | to_entries[] | .value.command // empty' "$HOME/.pi/agent/mcp.json" 2>/dev/null)
  export PATH="$MCP_BIN_DIR:$PATH"

  # Always bind gh to a fresh, empty config dir inside the ephemeral temp dir,
  # so even the informational path never falls back to a caller-supplied
  # GH_CONFIG_DIR pointing inside a permitted tree.
  GH_AGENT_DIR="$AGENT_TMP_DIR/gh"
  mkdir -p "$GH_AGENT_DIR"
  chmod 700 "$GH_AGENT_DIR"
  export GH_CONFIG_DIR="$GH_AGENT_DIR"

  # Side-effect-free informational invocations skip PAT provisioning; they still
  # run under the seatbelt with a temp dir. Only an EXACT leading argument counts.
  INFO_ARGS=0
  case "''${1:-}" in
      --version|--help|-h) INFO_ARGS=1 ;;
  esac

  GH_PROVISIONED=0
  if [ "$INFO_ARGS" = "0" ]; then
      # Dedicated GitHub agent credential (read-only fine-grained PAT),
      # provisioned from 1Password in the OUTER context and staged in the
      # ephemeral temp dir as gh's hosts.yml. GH_CONFIG_DIR points gh at that
      # disposable config; the personal ~/.config/gh and ~/.gitconfig are not
      # granted by the profile and inherited GitHub token vars were scrubbed.
      # `op` is pinned to the Nix-store path (no caller-PATH fallback), absent
      # from the sandbox PATH, and exec-denied by the seatbelt. Provisioning
      # FAILS CLOSED unless AGENT_GH_ALLOW_UNAUTHENTICATED=1.
      GH_OP_REF="''${AGENT_GH_OP_REF:-op://Private/GitHub Agent PAT/credential}"
      GH_USER="''${AGENT_GH_USER:-usabarashi}"
      GH_USER_VALID=0
      case "$GH_USER" in
          ""|*[!A-Za-z0-9-]*|*[-]|[!A-Za-z0-9]*) GH_USER_VALID=0 ;;
          *) GH_USER_VALID=1 ;;
      esac
      if [ "$GH_USER_VALID" = "1" ] && [ "''${#GH_USER}" -gt 39 ]; then
          GH_USER_VALID=0
      fi

      if [ "$GH_USER_VALID" = "1" ] && [ -x "${opBin}" ]; then
          GH_TOKEN="$("${opBin}" read "$GH_OP_REF" 2>/dev/null || true)"
          # GitHub tokens are [A-Za-z0-9_]+; anything else from the 1Password
          # item is treated as malformed (YAML-injection guard).
          case "$GH_TOKEN" in
              ""|*[!A-Za-z0-9_]*) GH_TOKEN="" ;;
              *)
                  umask 077
                  printf 'github.com:\n    oauth_token: %s\n    user: %s\n    git_protocol: https\n' "$GH_TOKEN" "$GH_USER" > "$GH_AGENT_DIR/hosts.yml"
                  # Verify the pinned gh resolves OUR staged token (local lookup
                  # only): a bare success is not enough, gh would fall back to the
                  # macOS keyring.
                  GH_RESOLVED_TOKEN="$(
                      GH_CONFIG_DIR="$GH_AGENT_DIR" \
                      GH_TOKEN= GITHUB_TOKEN= \
                      GH_ENTERPRISE_TOKEN= GITHUB_ENTERPRISE_TOKEN= \
                      "${ghBin}" auth token --hostname github.com 2>/dev/null
                  )" || GH_RESOLVED_TOKEN=""
                  if [ -n "$GH_RESOLVED_TOKEN" ] && [ "$GH_RESOLVED_TOKEN" = "$GH_TOKEN" ]; then
                      GH_PROVISIONED=1
                  fi
                  GH_RESOLVED_TOKEN=""
                  GH_TOKEN=""
                  ;;
          esac
      fi

      if [ "$GH_PROVISIONED" != "1" ]; then
          if [ "''${AGENT_GH_ALLOW_UNAUTHENTICATED:-0}" = "1" ]; then
              echo "Warning: GitHub agent credential unavailable; gh will be unauthenticated (AGENT_GH_ALLOW_UNAUTHENTICATED=1)." >&2
          else
              echo "Error: could not provision the GitHub agent PAT from 1Password." >&2
              echo "  op: ${opBin}" >&2
              echo "  item: $GH_OP_REF" >&2
              echo "  Check that the item exists and 'op' is signed in; or set AGENT_GH_ALLOW_UNAUTHENTICATED=1 to continue without GitHub." >&2
              exit 1
          fi
      fi
  fi

  # Git over HTTPS authenticates with the dedicated read-only GitHub PAT, never
  # the personal Keychain credential. Command-scope config (GIT_CONFIG_*) resets
  # the helper list (nixpkgs git sets credential.helper=osxkeychain) and binds
  # github.com to `gh auth git-credential` against the disposable staged config.
  # GIT_TERMINAL_PROMPT=0 plus the askpass scrub prevent a prompt fallback, and
  # GIT_ALLOW_PROTOCOL keeps the exec-allowed HTTP helper from plaintext HTTP.
  if [ "''${GH_PROVISIONED:-0}" = "1" ]; then
      GIT_GH_HELPER="!${ghBin} auth git-credential"
  else
      GIT_GH_HELPER="!false"
  fi
  export GIT_TERMINAL_PROMPT=0
  export GIT_ALLOW_PROTOCOL=https
  # GIT_ASKPASS must be set EMPTY, not unset: when unset, git falls back to
  # core.askPass and SSH_ASKPASS; an empty value disables askpass entirely.
  export GIT_ASKPASS=
  unset GIT_CONFIG_PARAMETERS SSH_ASKPASS
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0=credential.helper
  export GIT_CONFIG_VALUE_0=
  export GIT_CONFIG_KEY_1=credential.https://github.com.helper
  export GIT_CONFIG_VALUE_1="$GIT_GH_HELPER"

  case " $* " in
      *" --version "*|*" --help "*|*" -h "*) ;;
      *)
          echo "Running Pi with macOS Seatbelt ($SANDBOX_PROFILE_FILE)" >&2
          ;;
  esac

  exec "${sandbox-supervisor}/bin/sandbox-supervisor" --cleanup "$AGENT_TMP_DIR" -- \
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
      -D AGENT_CLAUDE_JSON="$AGENT_CLAUDE_JSON" \
      -D AGENT_TMP_DIR="$AGENT_TMP_DIR" \
      "$PI_BIN" "$@"
''
