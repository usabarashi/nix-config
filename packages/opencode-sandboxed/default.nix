# Sandboxed opencode CLI wrapping the version-pinned opencode-bin.
#
# Binary version lives in packages/opencode-bin/default.nix.
{
  lib,
  cacert,
  codex-bin,
  coreutils,
  nix,
  opencode-bin,
  stdenv,
  writeShellScriptBin,
  procps,
  ripgrep,
  jq,
  git,
  gh,
  _1password-cli,
  freeTierConfig,
  freeTierModels,
}:
let
  # 1Password CLI is used only in the OUTER (unsandboxed) wrapper context to
  # provision the dedicated GitHub agent PAT. It is deliberately NOT added to
  # the sandbox PATH, and cloud-restricted.sb denies it on the exec list, so
  # the model cannot reach the user's vault session from inside the sandbox.
  opBin = "${_1password-cli}/bin/op";
  ghBin = "${gh}/bin/gh";
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
  # Free-tier PATH: store-resolved components only. Deliberately excludes gh,
  # codex (remote-facing tools the free-tier model must not invoke) and git
  # itself: a low-trust model gets no local git at all rather than a sandbox
  # copy of the guard.
  freeBinPath = lib.makeBinPath [
    procps
    ripgrep
    jq
    coreutils
  ];
in
writeShellScriptBin "opencode" ''
  # git-agent-guard lives as a plain file (config/agents/scripts/), copied by
  # home-manager to ~/.config/opencode/bin/git; this dir must precede the
  # store `git` so agent-spawned `git` hits the deny shim.
  export PATH="$HOME/.config/opencode/bin:${
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
  CODEX_HOME_DIR="$AGENT_CACHE_DIR/second-opinion-${codex-bin.version}"
  AGENT_TMP_DIR=""
  LAUNCH_DIR="$(pwd -P)"
  TARGET_DIR="$LAUNCH_DIR"
  # Drop any inherited nix-guard variables so a caller environment cannot
  # activate the shim in a profile/session that should not have Nix access.
  # Fresh values are exported only in the cloud-restricted branch with a
  # detected flake root (the free-tier branch uses env -i anyway).
  unset AGENT_NIX_REAL_BIN AGENT_NIX_EXPECTED_VERSION AGENT_TARGET_DIR AGENT_TMP_DIR
  HOME_DIR="$HOME"
  FREE_TIER_CONFIG="${freeTierConfig}"
  FREE_TIER_MODELS="${freeTierModels}"
  FREE_BASE="$HOME/.local/share/opencode-free"
  FREE_DATA_DIR="$FREE_BASE/data/opencode"
  FREE_STATE_DIR="$FREE_BASE/state/opencode"
  FREE_AUX_STATE_DIR="$FREE_BASE/state"
  FREE_CACHE_DIR="$FREE_BASE/cache/opencode"
  FREE_CONFIG_DIR="$FREE_BASE/config/opencode"
  FREE_AUTH_FILE="$FREE_DATA_DIR/auth.json"
  FREE_GIT_NAME="opencode-free"
  FREE_GIT_EMAIL="opencode-free@localhost"
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
  # All wrapper options (--seatbelt, --list-seatbelts, --no-sandbox) are
  # parsed here in the leading option region, in ANY order, until a -- or the
  # first non-option argument. Everything after -- belongs to opencode. This
  # ensures the free-tier profile can forbid --no-sandbox regardless of where
  # it appears before --.

  wrapper_done=false
  no_sandbox=false
  while [ "$#" -gt 0 ]; do
      case "''${1}" in
          --)
              # Everything from here belongs to opencode. Keep the `--`
              # literal in the argument stream so the free-tier re-parser can
              # honor the boundary (a model AFTER -- must not satisfy the
              # mandatory-model requirement).
              wrapper_done=true
              break
              ;;
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
          --no-sandbox)
              no_sandbox=true
              shift
              ;;
          *)
              # First non-option argument: stop parsing wrapper options.
              wrapper_done=true
              break
              ;;
      esac
  done

  if [ "$wrapper_done" = "true" ]; then
      set -- "''${@}"
  fi

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

  # --no-sandbox: with the profile now known, enforce the free-tier rule, or
  # honor the bypass for other profiles by executing the raw binary directly
  # with the (already-stripped) remaining arguments.
  if [ "$no_sandbox" = "true" ]; then
      if [ "$SANDBOX_PROFILE_FILE" = "free-tier.sb" ]; then
          echo "Error: --no-sandbox is not permitted with the free-tier seatbelt" >&2
          exit 2
      fi
      exec "$OPENCODE_BIN" "$@"
  fi

  if [ "$SANDBOX_PROFILE_FILE" = "free-tier.sb" ]; then

      # ---------------------------------------------------------------- #
      # Free-tier (low-trust provider) branch.
      #
      # Session contract:
      #  * Credentials: ONLY free-tier static API keys, provisioned outside
      #    the sandbox into a dedicated, sandbox-immutable auth.json. The
      #    profile denies writes to that file; refresh is memory-only (or a
      #    fail-closed re-provision on expiry). No Keychain, gh config, or
      #    .gitconfig is read.
      #  * Environment: env -i allowlist. Only the variables listed below
      #    exist inside the sandbox; SLACK_USER_TOKEN, LIBRARY_API_KEY, any
      #    *_TOKEN/_*KEY, SSH_AUTH_SOCK and caller-supplied OPENCODE_* are
      #    dropped.
      #  * Model: -m/--model is mandatory and must match the versioned
      #    allowlist (exact resolved tuple). free-tier.json additionally
      #    enables only allowed providers and whitelists exact models.
      #  * This is NOT a billing boundary: *:443 is open, so any readable
      #    data can be exfiltrated and paid endpoints reached with a stolen
      #    key. Server-side spending controls (R30) are the real gate.
      # ---------------------------------------------------------------- #

      # 1. Mandatory -m, fail-closed. Model selectors BEFORE `--` are counted;
      #    selectors after `--` are positional data for opencode and must NOT
      #    satisfy the mandatory-model requirement.
      MODEL_ARG=""
      parsed_args=()
      model_region=true
      while [ "$#" -gt 0 ]; do
          case "''${1}" in
              --)
                  model_region=false
                  parsed_args+=("$1")
                  shift
                  ;;
              -m|--model)
                  if [ "$model_region" != "true" ]; then
                      parsed_args+=("$1")
                      shift
                      continue
                  fi
                  if [ "$#" -lt 2 ]; then
                      echo "Error: free-tier requires a model (missing value): $1" >&2
                      exit 2
                  fi
                  if [ -n "$MODEL_ARG" ]; then
                      echo "Error: free-tier rejects duplicate/conflicting model arguments" >&2
                      exit 2
                  fi
                  MODEL_ARG="$2"
                  shift 2
                  ;;
              --model=*)
                  if [ "$model_region" != "true" ]; then
                      parsed_args+=("$1")
                      shift
                      continue
                  fi
                  if [ -n "$MODEL_ARG" ]; then
                      echo "Error: free-tier rejects duplicate/conflicting model arguments" >&2
                      exit 2
                  fi
                  MODEL_ARG="''${1#--model=}"
                  shift
                  ;;
              -m*)
                  if [ "$model_region" != "true" ]; then
                      parsed_args+=("$1")
                      shift
                      continue
                  fi
                  if [ -n "$MODEL_ARG" ]; then
                      echo "Error: free-tier rejects duplicate/conflicting model arguments" >&2
                      exit 2
                  fi
                  MODEL_ARG="''${1#-m}"
                  if [ -z "$MODEL_ARG" ]; then
                      echo "Error: free-tier requires a model (empty -m value)" >&2
                      exit 2
                  fi
                  shift
                  ;;
              *)
                  parsed_args+=("$1")
                  shift
                  ;;
          esac
      done
      if [ -z "$MODEL_ARG" ]; then
          echo "Error: free-tier sessions require an explicit model (-m <provider>/<model>)" >&2
          echo "Allowed providers/models are listed in free-tier-models.json (versioned allowlist)." >&2
          exit 2
      fi
      case "$MODEL_ARG" in
          -*|*'/'|*'//'*|*' '*|*$'\t'*)
              echo "Error: free-tier rejected malformed model selector: $MODEL_ARG" >&2
              exit 2
              ;;
      esac
      MODEL_PROVIDER="''${MODEL_ARG%%/*}"
      MODEL_KEY="''${MODEL_ARG#*/}"
      if [ -z "$MODEL_PROVIDER" ] || [ -z "$MODEL_KEY" ] || [ "$MODEL_PROVIDER" = "$MODEL_ARG" ]; then
          echo "Error: free-tier model must be <provider>/<model>, got: $MODEL_ARG" >&2
          exit 2
      fi
      # Require EXACTLY ONE matching selector entry (regardless of its api_id),
      # then validate that single entry's api_id is a non-empty string.
      MATCH_COUNT="$(jq -r --arg prov "$MODEL_PROVIDER" --arg key "$MODEL_KEY" \
          '[.providers[] | select(.provider_id == $prov) | .models[] | select(.model == $key)] | length' \
          "$FREE_TIER_MODELS" 2>/dev/null || echo ERROR)"
      if [ "$MATCH_COUNT" != "1" ]; then
          echo "Error: model not allowed by free-tier allowlist (must match exactly one entry): $MODEL_ARG (matched: $MATCH_COUNT)" >&2
          exit 2
      fi
      # Record the resolved api_id from the single match; must be a non-empty
      # string.
      MODEL_API_ID="$(jq -r --arg prov "$MODEL_PROVIDER" --arg key "$MODEL_KEY" \
          '[.providers[] | select(.provider_id == $prov) | .models[] | select(.model == $key)] | .[0].api_id' \
          "$FREE_TIER_MODELS" 2>/dev/null)"
      if [ -z "$MODEL_API_ID" ] || [ "$MODEL_API_ID" = "null" ] \
          || [ "$(jq -r --arg prov "$MODEL_PROVIDER" --arg key "$MODEL_KEY" \
              '[.providers[] | select(.provider_id == $prov) | .models[] | select(.model == $key)] | .[0].api_id | type' \
              "$FREE_TIER_MODELS" 2>/dev/null)" != "string" ]; then
          echo "Error: free-tier allowlist entry missing a valid string api_id for: $MODEL_ARG" >&2
          exit 2
      fi
      export FREE_TIER_MODEL_ARG="$MODEL_ARG"
      export FREE_TIER_MODEL_API_ID="$MODEL_API_ID"
      # Forward the VALIDATED model selectors to opencode (they were stripped
      # during parsing); pass both original forms as the validated canonical
      # selector to keep behavior identical to a normal -m invocation.
      parsed_args=("-m" "$MODEL_ARG" "''${parsed_args[@]}")
      set -- "''${parsed_args[@]}"

      # 2. TARGET_DIR guard.
      #    Reject:
      #      * TARGET_DIR == / (the whole filesystem would be granted r/w)
      #      * TARGET_DIR == $HOME (running from home would expose the whole
      #        home tree through the TARGET_DIR r/w grant)
      #      * TARGET_DIR that is an ancestor of $HOME (e.g. /Users)
      #      * overlap with sensitive protected subtrees (~/.config, ~/.ssh,
      #        ~/.claude, dedicated roots, ...) in EITHER direction
      #    Permit ordinary projects located under $HOME (e.g. the nix-config
      #    checkout at /Users/gen/ghq/...).
      reject_target=0
      if [ "$TARGET_DIR" = "/" ]; then
          reject_target=1
      fi
      if [ "$TARGET_DIR" = "$HOME" ]; then
          reject_target=1
      fi
      # TARGET_DIR ancestor of HOME (HOME is under TARGET_DIR)
      case "/$HOME/" in
          "/$TARGET_DIR/"*) reject_target=1 ;;
      esac
      if [ "$reject_target" = "1" ]; then
          echo "Error: free-tier refuses to run from a directory that is or contains your home or the filesystem root: $TARGET_DIR" >&2
          exit 2
      fi
      reject_target=0
      for protected in \
          "$HOME/.config" \
          "$HOME/.local" \
          "$HOME/.ssh" \
          "$HOME/.codex" \
          "$HOME/.claude" \
          "$HOME/.config/opencode" \
          "$FREE_BASE" \
          "/Library/Application Support/opencode"; do
          # "$protected" == "$TARGET_DIR" or "$protected" is under "$TARGET_DIR"
          case "/$protected/" in
              "/$TARGET_DIR/"*) reject_target=1 ;;
          esac
          # "$TARGET_DIR" is under "$protected"
          case "/$TARGET_DIR/" in
              "/$protected/"*) reject_target=1 ;;
          esac
          if [ "$reject_target" = "1" ]; then
              echo "Error: free-tier refuses to run from a protected directory: $TARGET_DIR" >&2
              echo "  conflicts with: $protected" >&2
              exit 2
          fi
          reject_target=0
      done

      # 3. Managed configuration fail-closed (exact 1.18.15 candidates).
      #    Unreadable/unparsable candidates are treated as PRESENT (fail-closed).
      #    We walk each candidate's ancestor directories, skipping components
      #    that do not exist (absence is fine), and require every EXISTING
      #    ancestor to be searchable. An unsearchable existing ancestor means
      #    absence cannot be proven, so we fail closed.
      dir_searchable() {
          local d="''${1:-}"
          while [ -n "$d" ] && [ "$d" != "/" ]; do
              if [ -e "$d" ] || [ -L "$d" ]; then
                  if [ ! -x "$d" ]; then
                      return 1
                  fi
              fi
              d="$(dirname "$d")"
          done
          return 0
      }
      for cand in \
          "/Library/Application Support/opencode/opencode.json" \
          "/Library/Application Support/opencode/opencode.jsonc" \
          "/Library/Managed Preferences/$USER/ai.opencode.managed.plist" \
          "/Library/Managed Preferences/ai.opencode.managed.plist"; do
          if [ -e "$cand" ] || [ -L "$cand" ]; then
              echo "Error: free-tier detected managed OpenCode configuration: $cand" >&2
              echo "  free-tier requires an absent or independently verified managed config (fail-closed)." >&2
              exit 2
          fi
          cand_dir="$(dirname "$cand")"
          if ! dir_searchable "$cand_dir"; then
              echo "Error: free-tier cannot prove managed config absence (unsearchable parent): $cand_dir" >&2
              exit 2
          fi
      done

      # 4. Dedicated free-tier roots (fresh, 0700, no symlink components).
      #    The credential file lives inside FREE_DATA_DIR; free-tier.sb denies
      #    writes to it. Provision auth.json OUTSIDE the sandbox beforehand.
      #    Every component on the credential path is validated BEFORE any
      #    directory creation: no symlinks (including FREE_BASE itself),
      #    numeric UID == invoking UID, auth.json nlink == 1.
      FREE_UID="$(/usr/bin/id -u 2>/dev/null || echo "")"
      if [ -z "$FREE_UID" ]; then
          echo "Error: free-tier cannot determine numeric uid" >&2
          exit 2
      fi
      # Validate FREE_BASE and ALL existing ancestors up to / (skip missing
      # components but keep walking; a symlink at any existing ancestor is
      # rejected even when FREE_BASE itself does not yet exist).
      walk="$FREE_BASE"
      while [ "$walk" != "/" ] && [ -n "$walk" ]; do
          if [ -L "$walk" ]; then
              echo "Error: free-tier base path has a symlink component: $walk" >&2
              exit 2
          fi
          walk="$(dirname "$walk")"
      done
      # Validate the credential subtree (auth.json up to FREE_BASE).
      free_auth_dir="$(dirname "$FREE_AUTH_FILE")"
      walk="$FREE_AUTH_FILE"
      while [ "$walk" != "$FREE_BASE" ] && [ "$walk" != "/" ]; do
          if [ -L "$walk" ]; then
              echo "Error: free-tier credential path has a symlink component: $walk" >&2
              exit 2
          fi
          walk="$(dirname "$walk")"
      done
      if [ -L "$FREE_AUTH_FILE" ]; then
          echo "Error: free-tier auth.json must not be a symlink: $FREE_AUTH_FILE" >&2
          exit 2
      fi
      if [ -L "$FREE_BASE" ]; then
          echo "Error: free-tier base dir must not be a symlink: $FREE_BASE" >&2
          exit 2
      fi
      if ! mkdir -p "$FREE_DATA_DIR" "$FREE_STATE_DIR" "$FREE_CACHE_DIR" "$FREE_CONFIG_DIR"; then
          echo "Error: free-tier failed to create dedicated roots" >&2
          exit 2
      fi
      for d in "$FREE_BASE" "$FREE_DATA_DIR" "$FREE_STATE_DIR" "$FREE_CACHE_DIR" "$FREE_CONFIG_DIR" "$FREE_AUX_STATE_DIR"; do
          if ! chmod 700 "$d" 2>/dev/null; then
              echo "Error: free-tier failed to secure directory mode: $d" >&2
              exit 2
          fi
      done
      if [ ! -f "$FREE_AUTH_FILE" ]; then
          echo "Error: free-tier auth.json not found; provision free-tier credentials before session." >&2
          echo "  expected: $FREE_AUTH_FILE" >&2
          exit 1
      fi
      if [ "$(stat -f%u "$FREE_AUTH_FILE" 2>/dev/null || echo EMPTY)" != "$FREE_UID" ]; then
          echo "Error: free-tier auth.json uid mismatch: $(stat -f%u "$FREE_AUTH_FILE" 2>/dev/null || echo unknown) != $FREE_UID" >&2
          exit 2
      fi
      if [ "$(stat -f%l "$FREE_AUTH_FILE" 2>/dev/null || echo EMPTY)" != "1" ]; then
          echo "Error: free-tier auth.json link count is not 1 (possible hard link): $(stat -f%l "$FREE_AUTH_FILE" 2>/dev/null || echo unknown)" >&2
          exit 2
      fi
      if [ "$(stat -f%u "$free_auth_dir" 2>/dev/null || echo EMPTY)" != "$FREE_UID" ]; then
          echo "Error: free-tier credential dir uid mismatch: $(stat -f%u "$free_auth_dir" 2>/dev/null || echo unknown) != $FREE_UID" >&2
          exit 2
      fi

      # 5. Private per-invocation temp dir (the shared EXIT trap cleans it up).
      TMP_ROOT_FREE="$(cd "''${TMPDIR:-/private/tmp}" && pwd -P)"
      AGENT_TMP_DIR="$(/usr/bin/mktemp -d "''${TMP_ROOT_FREE%/}/opencode-free.XXXXXX")"
      /bin/chmod 700 "$AGENT_TMP_DIR"

      # 6. Local MCP commands (only chrome-devtools in free-tier) are re-linked
      #    from their resolved store paths into the private temp dir, exactly
      #    as the cloud-restricted branch does, so the Seatbelt-permitted PATH
      #    can spawn them.
      FREE_MCP_DIR="$AGENT_TMP_DIR/mcp-bin"
      mkdir "$FREE_MCP_DIR"
      while IFS= read -r mcp_cmd; do
          [ -z "$mcp_cmd" ] && continue
          case "$mcp_cmd" in
              /*) mcp_target="$mcp_cmd" ;;
              *) mcp_target="$(command -v "$mcp_cmd" 2>/dev/null || true)" ;;
          esac
          [ -z "$mcp_target" ] && continue
          mcp_real="$(realpath "$mcp_target" 2>/dev/null || echo "$mcp_target")"
          mcp_name="$(/usr/bin/basename "$mcp_cmd")"
          ln -sfn "$mcp_real" "$FREE_MCP_DIR/$mcp_name"
      done < <(
          jq -r '.mcp // {} | to_entries[] |
              select(.value.type == "local") |
              .value.command[0] // empty' "$FREE_TIER_CONFIG" 2>/dev/null
      )

      # 7. Free-tier PATH: wrapper-built from store-resolved components only.
      #    No gh, no codex, no caller PATH tail. The private mcp-bin dir comes
      #    first so MCP servers spawn through a Seatbelt-permitted path.
      FREE_PATH="${freeBinPath}"
      FREE_PATH="$FREE_MCP_DIR:$FREE_PATH"

      # 8. Immutable minimal config: OPENCODE_CONFIG points at the Nix-store
      #    copy. AGENT_CONFIG_FILE mirrors it (read-only). Commands/tools/
      #    skills are not shipped for the minimal free-tier config, but the
      #    Seatbelt profile references the parent config dir for them, so
      #    point them at the same immutable store directory.
      OPENCODE_CONFIG_PATH="$FREE_TIER_CONFIG"
      AGENT_CONFIG_FILE="$FREE_TIER_CONFIG"
      AGENT_CONFIG_DIR="$(dirname "$FREE_TIER_CONFIG")"
      AGENT_COMMANDS_DIR="$AGENT_CONFIG_DIR"
      AGENT_TOOLS_DIR="$AGENT_CONFIG_DIR"
      AGENT_SKILLS_DIR="$AGENT_CONFIG_DIR"
      AGENT_DATA_DIR="$FREE_DATA_DIR"
      AGENT_STATE_DIR="$FREE_STATE_DIR"
      AGENT_AUX_STATE_DIR="$FREE_AUX_STATE_DIR"
      AGENT_CACHE_DIR="$FREE_CACHE_DIR"
      AGENT_AUTH_FILE="$FREE_AUTH_FILE"
      # (OPENCODE_PURE/DISABLE_* are exported here only so the pre-sandbox
      #  argument-parsing section sees the same policy; they are re-supplied
      #  inside the env -i allowlist in step 9 because env -i discards them.)
      export OPENCODE_PURE=1
      export OPENCODE_DISABLE_PROJECT_CONFIG=1
      export OPENCODE_DISABLE_CLAUDE_CODE=1

      # 9. env -i allowlist. Only these variables exist inside the sandbox.
      #    All caller-supplied tokens/keys/OPENCODE_* are dropped. GIT_CONFIG*,
      #    GIT_CONFIG_GLOBAL/SYSTEM, EMAIL are absent (env -i default).
      #    NOTE: everything exported above (OPENCODE_PURE etc.) would be wiped
      #    by env -i, so they are re-supplied here explicitly.
      SANDBOX_ENV_SPEC=(
          "PATH=$FREE_PATH"
          "HOME=$HOME"
          "TERM=''${TERM:-xterm-256color}"
          "USER=$USER"
          "LOGNAME=$LOGNAME"
          "SHELL=''${SHELL:-/bin/zsh}"
          "TMPDIR=$AGENT_TMP_DIR/"
          "TMP=$AGENT_TMP_DIR"
          "TEMP=$AGENT_TMP_DIR"
          "XDG_DATA_HOME=$FREE_BASE/data"
          "XDG_STATE_HOME=$FREE_BASE/state"
          "XDG_CACHE_HOME=$FREE_BASE/cache"
          "XDG_CONFIG_HOME=$FREE_BASE/config"
          "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
          "OPENCODE_PURE=1"
          "OPENCODE_DISABLE_PROJECT_CONFIG=1"
          "OPENCODE_DISABLE_CLAUDE_CODE=1"
          "OPENCODE_CONFIG=$OPENCODE_CONFIG_PATH"
          "GIT_AUTHOR_NAME=$FREE_GIT_NAME"
          "GIT_AUTHOR_EMAIL=$FREE_GIT_EMAIL"
          "GIT_COMMITTER_NAME=$FREE_GIT_NAME"
          "GIT_COMMITTER_EMAIL=$FREE_GIT_EMAIL"
      )

      # 10. Parameter validation before Seatbelt (R40).
      for p in \
          TARGET_DIR HOME_DIR AGENT_CONFIG_DIR AGENT_CONFIG_FILE \
          AGENT_COMMANDS_DIR AGENT_TOOLS_DIR AGENT_SKILLS_DIR \
          AGENT_DATA_DIR AGENT_STATE_DIR AGENT_AUX_STATE_DIR \
          AGENT_CACHE_DIR AGENT_AUTH_FILE AGENT_TMP_DIR; do
          eval "v=\$$p"
          if [ -z "$v" ]; then
              echo "Error: free-tier empty Seatbelt parameter: $p" >&2
              exit 2
          fi
          case "$v" in
              /*) ;;
              *)
                  echo "Error: free-tier Seatbelt parameter is not absolute: $p = $v" >&2
                  exit 2
                  ;;
          esac
      done

      # 11. Emit the validated model binding BEFORE launch so the smoke suite
      #     can assert the exact expected provider/model/api_id pair. This line
      #     must stay above the sandbox-exec call (it exits on completion).
      echo "Running opencode with macOS Seatbelt (free-tier.sb)" >&2
      echo "  free-tier model: $FREE_TIER_MODEL_ARG (api_id: $FREE_TIER_MODEL_API_ID)" >&2

      # 12. Launch WITHOUT exec so the trap still removes the private temp dir.
      /usr/bin/env -i \
          "''${SANDBOX_ENV_SPEC[@]}" \
          /usr/bin/sandbox-exec -f "$SANDBOX_PROFILE_PATH" \
              -D TARGET_DIR="$TARGET_DIR" \
              -D HOME_DIR="$HOME_DIR" \
              -D AGENT_CONFIG_DIR="$AGENT_CONFIG_DIR" \
              -D AGENT_CONFIG_FILE="$AGENT_CONFIG_FILE" \
              -D AGENT_COMMANDS_DIR="$AGENT_COMMANDS_DIR" \
              -D AGENT_TOOLS_DIR="$AGENT_TOOLS_DIR" \
              -D AGENT_SKILLS_DIR="$AGENT_SKILLS_DIR" \
              -D AGENT_DATA_DIR="$AGENT_DATA_DIR" \
              -D AGENT_STATE_DIR="$AGENT_STATE_DIR" \
              -D AGENT_AUX_STATE_DIR="$AGENT_AUX_STATE_DIR" \
              -D AGENT_CACHE_DIR="$AGENT_CACHE_DIR" \
              -D AGENT_AUTH_FILE="$AGENT_AUTH_FILE" \
              -D AGENT_TMP_DIR="$AGENT_TMP_DIR" \
              "$OPENCODE_BIN" "$@"
      status=$?
      exit "$status"
  fi

  if [ "$SANDBOX_PROFILE_FILE" = "cloud-restricted.sb" ]; then
      # Skip repository-controlled configuration and external plugins so that
      # only the trusted user configuration is in effect. No permission
      # overrides are applied: the user's policy in opencode.json is used
      # as-is, and the Seatbelt profile enforces the physical limits
      # (project directory read/write, read-only /nix/store, HTTPS-only).
      export OPENCODE_DISABLE_PROJECT_CONFIG=1
      export OPENCODE_DISABLE_CLAUDE_CODE=1
      # Pure mode suppresses all external plugins (both config-declared and
      # auto-discovered under .opencode/plugin(s)). User tools under the
      # managed tools/ directory are loaded on a separate path and survive.
      export OPENCODE_PURE=1

      # Resolve the workspace flake root: nearest ancestor of the launch dir
      # containing flake.nix, never above $HOME or "/". Cloud sessions work on
      # the repo flake, so TARGET_DIR (and the seatbelt r/w grant) becomes the
      # flake root. Free-tier keeps TARGET_DIR = the launch dir (it exits in
      # its own branch before this point). Without a flake root, the nix guard
      # env is not exported and the shim fails closed.
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

      # Scrub inherited GitHub credential environment variables. gh gives
      # GH_TOKEN/GITHUB_TOKEN (and the enterprise variants) precedence over
      # stored config, so a personal token left exported in the caller's shell
      # would defeat the dedicated-credential guarantee. The sandboxed process
      # inherits this scrubbed environment.
      unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN

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

      # Private per-invocation temp dir. The root is the per-user system temp dir
      # (never caller TMPDIR): credential staging must not land inside the
      # project tree even when the caller points TMPDIR there.
      TMP_ROOT_RAW="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '%s' "/private/tmp")"
      TMP_ROOT="$(cd "$TMP_ROOT_RAW" && pwd -P)"
      AGENT_TMP_DIR="$(/usr/bin/mktemp -d "''${TMP_ROOT%/}/opencode-cloud.XXXXXX")"
      /bin/chmod 700 "$AGENT_TMP_DIR"
      export TMPDIR="$AGENT_TMP_DIR/"
      export TMP="$AGENT_TMP_DIR"
      export TEMP="$AGENT_TMP_DIR"

      # Nix access: hand the guard shim the pinned nix and ephemeral Nix
      # state/config/cache dirs inside the per-invocation temp tree. Not
      # exported without a flake root, so the `nix` shim fails closed.
      if [ -n "$FLAKE_ROOT" ]; then
          mkdir -p "$AGENT_TMP_DIR/nix/config" "$AGENT_TMP_DIR/nix/state" "$AGENT_TMP_DIR/nix/cache"
          export AGENT_NIX_REAL_BIN="${nix}/bin/nix"
          export AGENT_NIX_EXPECTED_VERSION="${nix.version}"
          export AGENT_TARGET_DIR="$TARGET_DIR"
          export AGENT_TMP_DIR="$AGENT_TMP_DIR"
      fi

      OPENCODE_CONFIG_FILE="$HOME/.config/opencode/opencode.json"
      if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
          echo "Error: OpenCode config not found at $OPENCODE_CONFIG_FILE" >&2
          exit 1
      fi

      # Local MCP servers are resolved by name from PATH. The Seatbelt profile
      # permits reading /nix/store directly, but a PATH hit under
      # /etc/profiles (a symlink to /private/etc/profiles, whose vnode path
      # the profile does not grant) fails at spawn time. Re-link each local
      # MCP command from its resolved Nix store path into the per-invocation
      # private temp dir and put that directory first on PATH so opencode
      # spawns the servers through a path the Seatbelt profile permits. This
      # block runs before sandbox-exec, so resolving the symlink chain is
      # unrestricted. The temp dir is private (0700, created above) and is
      # removed on exit, so no sandbox-writable persistent directory is ever
      # used as a symlink farm across runs.
      MCP_BIN_DIR="$AGENT_TMP_DIR/mcp-bin"
      mkdir "$MCP_BIN_DIR"
      while IFS= read -r mcp_cmd; do
          [ -z "$mcp_cmd" ] && continue
          case "$mcp_cmd" in
              /*) mcp_target="$mcp_cmd" ;;
              *) mcp_target="$(command -v "$mcp_cmd" 2>/dev/null || true)" ;;
          esac
          [ -z "$mcp_target" ] && continue
          mcp_real="$(realpath "$mcp_target" 2>/dev/null || echo "$mcp_target")"
          mcp_name="$(/usr/bin/basename "$mcp_cmd")"
          ln -sfn "$mcp_real" "$MCP_BIN_DIR/$mcp_name"
      done < <(
          jq -r '.mcp // {} | to_entries[] |
              select(.value.type == "local") |
              .value.command[0] // empty' "$OPENCODE_CONFIG_FILE" 2>/dev/null
      )
      export PATH="$MCP_BIN_DIR:$PATH"

      # Side-effect-free informational invocations (--version/--help/-h) skip gh
      # provisioning (no 1Password required) but still run under the seatbelt
      # with the temp dir created above. Only an EXACT leading argument counts:
      # a prompt containing "--help" as data must not bypass provisioning.
      INFO_ARGS=0
      case "''${1:-}" in
          --version|--help|-h) INFO_ARGS=1 ;;
      esac

      # Always bind gh to a fresh, empty config dir inside the ephemeral temp
      # dir, so even the informational path never falls back to a caller-
      # supplied GH_CONFIG_DIR pointing inside a permitted tree.
      GH_AGENT_DIR="$AGENT_TMP_DIR/gh"
      mkdir -p "$GH_AGENT_DIR"
      chmod 700 "$GH_AGENT_DIR"
      export GH_CONFIG_DIR="$GH_AGENT_DIR"

      if [ "$INFO_ARGS" = "0" ]; then
          # Dedicated GitHub agent credential (read-only fine-grained PAT).
          #
          # The wrapper provisions it from 1Password in the OUTER context (this
          # block runs before sandbox-exec) and stages it in the ephemeral
          # per-invocation temp dir as gh's hosts.yml. GH_CONFIG_DIR always
          # points gh at that disposable config; the personal ~/.config/gh,
          # ~/.gitconfig and ~/.config/git are not granted by the seatbelt and
          # inherited GitHub token variables were scrubbed above. The PAT is
          # readable by the model for the duration of the session (same accepted
          # tradeoff as environment variables) and the temp dir is removed when
          # the wrapper exits normally; a forcefully killed wrapper may leave it
          # until the OS reaps the temp directory.
          #
          # `op` is used only here (pinned store path; no caller-PATH fallback —
          # an arbitrary `op` on PATH must never receive the vault reference in
          # the outer context), is not on the sandbox PATH, and is exec-denied
          # by the seatbelt, so the model cannot reach the 1Password vault
          # session from inside. Provisioning FAILS CLOSED: without the
          # dedicated PAT the cloud session refuses to start, unless
          # AGENT_GH_ALLOW_UNAUTHENTICATED=1 (then gh runs unauthenticated).
          # The item reference and GitHub user are overridable via
          # AGENT_GH_OP_REF and AGENT_GH_USER (defaults follow the direnv
          # README convention `op://Private/GitHub .../credential`).
          GH_OP_BIN="${opBin}"
          GH_OP_REF="''${AGENT_GH_OP_REF:-op://Private/GitHub Agent PAT/credential}"
          GH_USER="''${AGENT_GH_USER:-usabarashi}"
          # GitHub logins are 1-39 chars of [A-Za-z0-9-], starting and ending
          # with alphanumeric; anything else would let the override inject YAML
          # keys or produce an unusable account entry.
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
              # GitHub tokens are [A-Za-z0-9_]+; anything else coming back from
              # the 1Password item is treated as malformed. This also prevents
              # field content from injecting additional YAML keys into hosts.yml.
              case "$GH_TOKEN" in
                  ""|*[!A-Za-z0-9_]*)
                      GH_TOKEN=""
                      ;;
                  *)
                      umask 077
                      printf 'github.com:\n    oauth_token: %s\n    user: %s\n    git_protocol: https\n' "$GH_TOKEN" "$GH_USER" > "$GH_AGENT_DIR/hosts.yml"
                      # Verify the pinned gh actually resolves OUR staged token (local lookup
                      # only, no network): capture the token it prints and
                      # require an exact match. A bare success is not enough —
                      # gh falls back to the macOS keyring when the staged
                      # config has no token, which would be a false positive.
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
      -D AGENT_CLAUDE_JSON="$AGENT_STATE_DIR/claude.json" \
      -D AGENT_TMP_DIR="$AGENT_TMP_DIR" \
      "$OPENCODE_BIN" "$@"
  exit "$?"
''
