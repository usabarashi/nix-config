# Sandboxed Claude Code CLI wrapping the version-pinned claude-code-bin.
#
# Binary version lives in packages/claude-code-bin/default.nix.
{
  lib,
  cacert,
  claude-code-bin,
  writeShellScriptBin,
  stdenv,
  nix,
  procps,
  ripgrep,
  jq,
  git,
  gh,
  _1password-cli,
}:
let
  # Same dedicated-credential provisioning as the opencode wrapper: the 1Password
  # CLI is used only in the OUTER (unsandboxed) context; it is not on the sandbox
  # PATH and cloud-restricted.sb denies it on the exec list.
  opBin = "${_1password-cli}/bin/op";
  ghBin = "${gh}/bin/gh";
  # Minimal supervisor with explicit waitpid(2)/EINTR handling. The wrapper
  # execs it INSTEAD of backgrounding sandbox-exec, which removes the shell
  # signal/wait races (see sandbox-supervisor.c header). It also owns removal of
  # the per-invocation temp dir after the sandboxed agent exits.
  sandboxSupervisor = stdenv.mkDerivation {
    pname = "sandbox-supervisor";
    version = "1";
    src = ./sandbox-supervisor.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -Wall -Wextra -Werror -O2 "$src" -o sandbox-supervisor
    '';
    installPhase = ''
      install -Dm755 sandbox-supervisor "$out/bin/sandbox-supervisor"
    '';
  };
in
writeShellScriptBin "claude" ''
  export DISABLE_AUTOUPDATER=1
  export FORCE_AUTOUPDATE_PLUGINS=1
  export DISABLE_INSTALLATION_CHECKS=1
  export USE_BUILTIN_RIPGREP=0
  export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
  # git-agent-guard is copied to ~/.claude/bin/git by home-manager; this dir
  # must precede the store `git` so agent-spawned `git` hits the deny shim.
  export PATH="$HOME/.claude/bin:${
    lib.makeBinPath [
      procps
      ripgrep
      jq
      git
      gh
    ]
  }:$PATH"

  CLAUDE_BIN="${claude-code-bin}/bin/claude"
  SANDBOX_PROFILE_DIR="$HOME/.claude"
  SANDBOX_PROFILE_FILE="cloud-restricted.sb"
  AGENT_CONFIG_DIR="$HOME/.claude"
  AGENT_CONFIG_FILE="$HOME/.claude/settings.json"
  AGENT_COMMANDS_DIR="$HOME/.claude/commands"
  AGENT_TOOLS_DIR="$HOME/.claude"
  AGENT_SKILLS_DIR="$HOME/.claude/skills"
  AGENT_STATE_DIR="$HOME/.claude"
  AGENT_AUX_STATE_DIR="$HOME/.claude"
  AGENT_CACHE_DIR="$HOME/.cache/claude"
  AGENT_CLAUDE_JSON="$HOME/.claude.json"
  LAUNCH_DIR="$(pwd -P)"
  TARGET_DIR="$LAUNCH_DIR"
  # Drop any inherited nix-guard variables so a caller environment cannot
  # activate the shim in a profile/session that should not have Nix access.
  # The wrapper exports fresh values only for cloud-restricted.sb with a
  # detected flake root.
  unset AGENT_NIX_REAL_BIN AGENT_NIX_EXPECTED_VERSION AGENT_TARGET_DIR AGENT_TMP_DIR
  AGENT_TMP_DIR=""

  cleanup_cloud_tmp() {
      if [ -n "$AGENT_TMP_DIR" ]; then
          rm -rf -- "$AGENT_TMP_DIR"
          AGENT_TMP_DIR=""
      fi
  }
  trap cleanup_cloud_tmp EXIT

  # --no-sandbox: bypass sandbox and execute the binary directly.
  # Useful when invoked from an already-sandboxed context (e.g., Gemini CLI).
  if [ "''${1:-}" = "--no-sandbox" ]; then
      shift
      exec "$CLAUDE_BIN" "$@"
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
      echo "Run 'claude --list-seatbelts' to list installed profiles." >&2
      echo "Please ensure claude configuration is properly installed." >&2
      exit 1
  fi

  # Workspace flake root (cloud-restricted.sb only): nearest ancestor of the
  # launch dir containing flake.nix, never above $HOME or "/". Cloud sessions
  # work on the repo flake, so TARGET_DIR becomes the flake root and the
  # seatbelt grants the whole workspace. Any other/unknown profile keeps
  # TARGET_DIR = the launch directory and no nix guard env is exported.
  FLAKE_ROOT=""
  if [ "$SANDBOX_PROFILE_FILE" = "cloud-restricted.sb" ]; then
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
  fi

  # Side-effect-free informational invocations (--version/--help/-h) must not
  # require 1Password provisioning; they still run under the seatbelt (and get a
  # temp dir for the AGENT_TMP_DIR param), but the gh credential block is
  # skipped. Only an EXACT leading argument counts: a prompt containing
  # "--help" as data must not bypass provisioning.
  INFO_ARGS=0
  case "''${1:-}" in
      --version|--help|-h) INFO_ARGS=1 ;;
  esac

  # Scrub inherited GitHub credential environment variables (same rationale as
  # the opencode wrapper: gh gives GH_TOKEN/GITHUB_TOKEN precedence over config).
  unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN

  # Private per-invocation temp dir. The root is the per-user system temp dir
  # (never caller TMPDIR): credential staging must not land inside the project
  # tree even when the caller points TMPDIR there. cloud-restricted.sb grants
  # read/write only within this directory; TMPDIR redirect keeps Node/git away
  # from other system temp locations.
  TMP_ROOT_RAW="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '%s' "/private/tmp")"
  TMP_ROOT="$(cd "$TMP_ROOT_RAW" && pwd -P)"
  AGENT_TMP_DIR="$(/usr/bin/mktemp -d "''${TMP_ROOT%/}/claude-cloud.XXXXXX")"
  /bin/chmod 700 "$AGENT_TMP_DIR"
  export TMPDIR="$AGENT_TMP_DIR/"
  export TMP="$AGENT_TMP_DIR"
  export TEMP="$AGENT_TMP_DIR"

  # Nix access (cloud-restricted.sb): hand the guard shim the pinned nix and
  # ephemeral Nix state/config/cache dirs inside the per-invocation temp tree.
  # Not exported when there is no flake root, so the `nix` shim fails closed.
  if [ -n "$FLAKE_ROOT" ]; then
      mkdir -p "$AGENT_TMP_DIR/nix/config" "$AGENT_TMP_DIR/nix/state" "$AGENT_TMP_DIR/nix/cache"
      export AGENT_NIX_REAL_BIN="${nix}/bin/nix"
      export AGENT_NIX_EXPECTED_VERSION="${nix.version}"
      export AGENT_TARGET_DIR="$TARGET_DIR"
      export AGENT_TMP_DIR="$AGENT_TMP_DIR"
  fi

  # Always bind gh to a fresh, empty config dir inside the ephemeral temp dir,
  # so even the informational path never falls back to a caller-supplied
  # GH_CONFIG_DIR pointing inside a permitted tree.
  GH_AGENT_DIR="$AGENT_TMP_DIR/gh"
  mkdir -p "$GH_AGENT_DIR"
  chmod 700 "$GH_AGENT_DIR"
  export GH_CONFIG_DIR="$GH_AGENT_DIR"

  if [ "$INFO_ARGS" = "0" ]; then
      # Dedicated GitHub agent credential (read-only fine-grained PAT), identical
      # to the opencode wrapper: provisioned from 1Password in the OUTER context
      # and staged in the ephemeral temp dir as gh's hosts.yml. GH_CONFIG_DIR
      # points gh at the disposable config, so the agent's gh never sees the
      # personal ~/.config/gh (the profile does not grant it). `op` is pinned to
      # the Nix-store path (no caller-PATH fallback), absent from the sandbox
      # PATH, and exec-denied by the seatbelt. Provisioning FAILS CLOSED unless
      # AGENT_GH_ALLOW_UNAUTHENTICATED=1.
      GH_OP_BIN="${opBin}"
      GH_OP_REF="''${AGENT_GH_OP_REF:-op://Private/GitHub Agent PAT/credential}"
      GH_USER="''${AGENT_GH_USER:-usabarashi}"
      # GitHub logins are 1-39 chars of [A-Za-z0-9-], starting and ending with
      # alphanumeric; anything else would let the override inject YAML keys or
      # produce an unusable account entry.
      GH_USER_VALID=0
      case "$GH_USER" in
          ""|*[!A-Za-z0-9-]*|*[-]|[!A-Za-z0-9]*)
              GH_USER_VALID=0
              ;;
          *)
              GH_USER_VALID=1
              ;;
      esac
      if [ "$GH_USER_VALID" = "1" ] && [ "''${#GH_USER}" -gt 39 ]; then
          GH_USER_VALID=0
      fi

      GH_PROVISIONED=0
      if [ "$GH_USER_VALID" = "1" ] && [ -x "$GH_OP_BIN" ]; then
          GH_TOKEN="$("$GH_OP_BIN" read "$GH_OP_REF" 2>/dev/null || true)"
          # GitHub tokens are [A-Za-z0-9_]+; anything else coming back from the
          # 1Password item is treated as malformed (YAML-injection guard).
          case "$GH_TOKEN" in
              ""|*[!A-Za-z0-9_]*)
                  GH_TOKEN=""
                  ;;
              *)
                  umask 077
                  printf 'github.com:\n    oauth_token: %s\n    user: %s\n    git_protocol: https\n' "$GH_TOKEN" "$GH_USER" > "$GH_AGENT_DIR/hosts.yml"
                  # Verify the pinned gh actually resolves OUR staged token (local lookup
                  # only, no network): capture the token it prints and require an
                  # exact match. A bare success is not enough — gh falls back to
                  # the macOS keyring when the staged config has no token, which
                  # would be a false positive.
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
                  ;;
          esac
      fi
      if [ "$GH_PROVISIONED" != "1" ]; then
          if [ "''${AGENT_GH_ALLOW_UNAUTHENTICATED:-0}" = "1" ]; then
              echo "Warning: GitHub agent credential unavailable; gh will be unauthenticated (AGENT_GH_ALLOW_UNAUTHENTICATED=1)." >&2
          else
              echo "Error: could not provision the GitHub agent PAT from 1Password." >&2
              if [ "$GH_USER_VALID" != "1" ]; then
                  echo "  AGENT_GH_USER is not a valid GitHub login: $GH_USER" >&2
              else
                  echo "  op: $GH_OP_BIN" >&2
                  echo "  item: $GH_OP_REF" >&2
              fi
              echo "  Check that the item exists and 'op' is signed in; or set AGENT_GH_ALLOW_UNAUTHENTICATED=1 to continue without GitHub." >&2
              exit 1
          fi
      fi
  fi

  case " $* " in
      *" --version "*|*" --help "*|*" -h "*) ;;
      *)
          echo "Running Claude Code with macOS Seatbelt ($SANDBOX_PROFILE_FILE)" >&2
          ;;
  esac

  # exec the C supervisor so THIS wrapper's PID becomes the supervisor: signals
  # sent to `claude` are forwarded to the sandboxed process without the shell
  # wait/trap races, and the supervisor removes AGENT_TMP_DIR only after the
  # sandboxed agent has actually exited (never while it is still running).
  # The EXIT trap in the wrapper handles abort paths before this exec.
  exec "${sandboxSupervisor}/bin/sandbox-supervisor" \
      --cleanup "$AGENT_TMP_DIR" \
      -- /usr/bin/sandbox-exec -f "$SANDBOX_PROFILE_PATH" \
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
      "$CLAUDE_BIN" "$@"
''
