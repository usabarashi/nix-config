#!/usr/bin/env bash
# nix-agent-guard: a `nix` shim placed FIRST on the agent-sandbox PATH.
#
# Purpose
# -------
# Sandboxed agent sessions (cloud-restricted.sb) may talk to the Nix daemon
# (accepted threat model: the sandboxed process gets this trusted macOS
# account's full trusted-user Nix-daemon authority). This shim constrains HOW
# Nix is invoked through normal PATH-based invocation so that accidental or
# "cooperative" misuse does not construct arbitrary Nix expressions or cross
# the workspace boundary.
#
# This is FRICTION, NOT a security boundary: direct execution of the pinned
# nix binary from /nix/store (including with a forged argv[0]), or speaking
# the daemon protocol directly, bypasses this shim entirely. Documented in
# config/agents/README.md.
#
# Policy (v1, curated for Nix 2.34.x):
#   * Subcommands: build, eval, fmt, develop, print-dev-env,
#     flake check, flake show, plus informational --version / --help.
#     `run`, `flake update`, `flake lock`, and everything unknown are denied.
#   * Flake references: omitted, `.`, or `.#attrpath` only. The resolved
#     flake root (walking up from the working directory, not above
#     AGENT_TARGET_DIR) must equal AGENT_TARGET_DIR.
#   * Options: per-subcommand ALLOWLIST. Anything not listed is denied
#     (this rejects --expr/--apply/--option/--store/--override-input/...).
#     Value-taking options (develop's --keep-env-var / --unset-env-var /
#     --set-env-var) must use the space-separated form; `--flag=value` is
#     rejected for them so an extra token cannot smuggle past validation.
#   * --impure is permitted only because every accepted flake reference is
#     the workspace root (dotfiles management requires it).
#   * Lock files are updated by the HUMAN outside the session. Ordinary
#     commands get --no-update-lock-file (and --no-write-lock-file) injected
#     in the Nix-option region, BEFORE any `--command` payload boundary.
#   * Nix configuration/location environment variables are scrubbed and
#     redirected to ephemeral per-invocation directories.
#
# Environment supplied by the wrapper (fail-closed when missing):
#   AGENT_NIX_REAL_BIN          pinned nix binary (absolute /nix/store path)
#   AGENT_NIX_EXPECTED_VERSION  pinned nix version stamp for the option table
#   AGENT_TARGET_DIR            seatbelt project dir (for cloud: the flake root)
#   AGENT_TMP_DIR               private per-invocation temp dir
#
# Deployment: materialized through home-manager as an executable home file
# (store-backed content, like git-agent-guard), not an out-of-store symlink
# into this repo — an out-of-store symlink would be unreadable when the agent
# runs in a project outside this checkout. See the agents-*.nix modules.

set -euo pipefail

die() {
  echo "error: nix-agent-guard: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Wrapper-provided environment, fail-closed.
# ---------------------------------------------------------------------------
NIX_REAL="${AGENT_NIX_REAL_BIN:-}"
TARGET_DIR="${AGENT_TARGET_DIR:-}"
TMP_DIR="${AGENT_TMP_DIR:-}"
EXPECTED_VER="${AGENT_NIX_EXPECTED_VERSION:-}"
if [ -z "$NIX_REAL" ] || [ -z "$TARGET_DIR" ] || [ -z "$TMP_DIR" ] || [ -z "$EXPECTED_VER" ]; then
  die "missing wrapper environment (AGENT_NIX_REAL_BIN / AGENT_TARGET_DIR / AGENT_TMP_DIR / AGENT_NIX_EXPECTED_VERSION)"
fi
case "$TARGET_DIR" in
  /*) ;;
  *) die "AGENT_TARGET_DIR is not absolute: $TARGET_DIR" ;;
esac
if [ ! -x "$NIX_REAL" ]; then
  die "pinned nix binary is not executable: $NIX_REAL"
fi

# ---------------------------------------------------------------------------
# 2. Version gate for the option table. Fail closed on mismatch.
# ---------------------------------------------------------------------------
# `nix --version` prints "nix (Nix) 2.34.7": the version is field 3.
ACTUAL_VER="$("$NIX_REAL" --version 2>/dev/null | awk '{print $3}')" || ACTUAL_VER=""
if [ -z "$ACTUAL_VER" ]; then
  die "could not read pinned nix version"
fi
case "$ACTUAL_VER" in
  "$EXPECTED_VER"*) ;;
  *)
    die "pinned nix version $ACTUAL_VER does not match the guard option-table stamp $EXPECTED_VER; update nix-agent-guard.sh"
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Scrub untrusted Nix configuration and redirect state to the ephemeral
#    per-invocation temp tree (nix-only; other processes are not affected).
#    System config (/etc/nix/nix.conf) is still read and supplies
#    experimental-features and trusted keys.
# ---------------------------------------------------------------------------
unset NIX_CONFIG NIX_USER_CONF_FILES NIX_CONF_DIR NIX_PATH 2>/dev/null || true
unset NIX_CONFIG_HOME NIX_STATE_HOME NIX_CACHE_HOME NIX_DATA_HOME 2>/dev/null || true
unset NIX_REGISTRY XDG_CONFIG_DIRS 2>/dev/null || true
export NIX_REMOTE=daemon
export NIX_CONFIG_HOME="$TMP_DIR/nix/config"
export NIX_STATE_HOME="$TMP_DIR/nix/state"
export NIX_CACHE_HOME="$TMP_DIR/nix/cache"
mkdir -p "$NIX_CONFIG_HOME" "$NIX_STATE_HOME" "$NIX_CACHE_HOME"

# ---------------------------------------------------------------------------
# 4. Argument grammar.
# ---------------------------------------------------------------------------
ATTRPATH_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'

# is_flake_ref <arg>: 0 if the arg is an accepted installable spelling.
is_flake_ref() {
  local a="$1"
  case "$a" in
    ".")
      return 0
      ;;
    ".#"*)
      case "${a#.#}" in
        "" | *" "*) return 1 ;;
      esac
      if [[ ! "${a#.#}" =~ $ATTRPATH_RE ]]; then
        return 1
      fi
      [ -n "${a#.#}" ] || return 1
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# flake_root_from <dir>: prints the nearest ancestor of <dir> that contains a
# regular flake.nix, stopping (without printing) if it gets above TARGET_DIR
# or finds no flake.
flake_root_from() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/flake.nix" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    if [ "$d" = "$TARGET_DIR" ]; then
      # Do not walk above the seatbelt project boundary.
      return 1
    fi
    local parent
    parent="$(dirname "$d")"
    [ "$parent" = "$d" ] && break
    d="$parent"
  done
  return 1
}

# validate_workspace_flake: the current directory must be inside TARGET_DIR
# and the enclosing flake root must be exactly TARGET_DIR.
validate_workspace_flake() {
  local cwd parents root
  cwd="$(pwd -P 2>/dev/null)" || die "cannot resolve working directory"
  case "$cwd/" in
    "$TARGET_DIR"/* | "$TARGET_DIR") ;;
    *) die "working directory is outside the workspace: $cwd" ;;
  esac
  root="$(flake_root_from "$cwd")" || die "no flake.nix found within the workspace ($TARGET_DIR); launch from the flake root"
  [ "$root" = "$TARGET_DIR" ] || die "flake root $root is not the workspace root $TARGET_DIR"
}

# validate_target_path <path>: for `nix fmt <path>` style arguments. The path
# must resolve inside TARGET_DIR. Rejects only path components exactly equal to
# ".." and canonicalizes through the nearest existing ancestor (realpath) so an
# in-workspace symlink pointing outside cannot pass this check. When realpath
# exists but fails, fail closed; if it is unavailable, fall back to the lexical
# path (the seatbelt remains the real filesystem boundary).
validate_target_path() {
  local arg="$1" comp cur real
  IFS='/' read -r -a comps <<< "$arg"
  for comp in "${comps[@]}"; do
      [ "$comp" = ".." ] && die "path escapes the workspace: $arg"
  done
  case "$arg" in
    /*) cur="$arg" ;;
    *) cur="$(pwd -P)/$arg" ;;
  esac
  # Normalize: walk up to the nearest existing ancestor (a dangling symlink
  # counts as an endpoint so it is canonicalized and rejected, not reduced to
  # its parent), then canonicalize it.
  while [ "$cur" != "/" ] && [ ! -e "$cur" ] && [ ! -L "$cur" ]; do
    cur="$(dirname "$cur")"
  done
  if command -v realpath >/dev/null 2>&1; then
    real="$(realpath "$cur" 2>/dev/null)" || die "cannot canonicalize path: $arg"
  else
    real="$cur"
  fi
  case "$real" in
    "$TARGET_DIR" | "$TARGET_DIR"/*) ;;
    *) die "path is outside the workspace: $arg" ;;
  esac
}

# option_allowed <cmd> <flag>: 0 if flag is on the per-command allowlist.
option_allowed() {
  local cmd="$1" flag="$2"
  case "$cmd:$flag" in
    build:--no-link | build:--impure | build:--help)
      return 0
      ;;
    eval:--raw | eval:--json | eval:--impure | eval:--help)
      return 0
      ;;
    fmt:--help)
      return 0
      ;;
    develop:--command | develop:-c | develop:--ignore-env | develop:--keep-env-var \
      | develop:--unset-env-var | develop:--set-env-var | develop:--impure | develop:--help)
      return 0
      ;;
    print-dev-env:--json | print-dev-env:--impure | print-dev-env:--help)
      return 0
      ;;
    flake-check:--impure | flake-check:--help | flake-show:--impure | flake-show:--json | flake-show:--help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# consume_value <cmd> <flag>: print "consume" if the flag takes one value.
flag_takes_value() {
  case "${1:-}:${2:-}" in
    develop:--keep-env-var | develop:--unset-env-var)
      printf '%s\n' one
      ;;
    develop:--set-env-var)
      printf '%s\n' two
      ;;
    *)
      printf '%s\n' none
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 5. Dispatch.
# ---------------------------------------------------------------------------
out=()
if [ "$#" -eq 0 ]; then
  die "REPL mode is not allowed; pass an explicit subcommand"
fi

case "$1" in
  --version | --help | -h)
    if [ "$#" -ne 1 ]; then
      die "$1 does not accept additional arguments"
    fi
    out=("$1")
    exec -a nix "$NIX_REAL" "${out[@]}"
    ;;
esac

CMD="$1"
shift

case "$CMD" in
  build | eval | develop | print-dev-env)
    validate_workspace_flake
    ;;
  fmt)
    validate_workspace_flake
    ;;
  flake)
    [ "$#" -ge 1 ] || die "nix flake requires exactly one of: check, show"
    case "$1" in
      check | show) ;;
      *) die "nix flake subcommand '$1' is not allowed; only check and show are" ;;
    esac
    validate_workspace_flake
    ;;
  *)
    die "subcommand '$CMD' is not allowed in agent sessions (allowed: build, eval, fmt, develop, print-dev-env, flake check, flake show)"
    ;;
esac

# Per-command option allowlist key for option_allowed/flag_takes_value.
CKEY="$CMD"
[ "$CMD" = "flake" ] && CKEY="flake-$1"

# Commands that accept the lock-policy flags. `nix fmt` evaluates the
# workspace flake to obtain its formatter and supports the lock options, so it
# also gets the flags (lock files are human-managed exclusively).
LOCK_FLAGS=0
case "$CMD" in
  build | eval | fmt | develop | print-dev-env) LOCK_FLAGS=1 ;;
  flake) LOCK_FLAGS=1 ;;
esac

out=("$CMD")
if [ "$CMD" = "flake" ]; then
  out+=("$1")
  shift
fi
if [ "$LOCK_FLAGS" = "1" ]; then
  out+=(--no-update-lock-file --no-write-lock-file)
fi

installables=0
payload_started=0
options_ended=0

# append_operand: validate and append a positional operand. After `--` the
# same validation applies — options are not options there.
append_operand() {
    local operand="$1"
    if [ "$CMD" = "fmt" ]; then
        validate_target_path "$operand"
        out+=("$operand")
        return 0
    fi
    if [ "$CKEY" = "flake-check" ] || [ "$CKEY" = "flake-show" ]; then
        # flake check/show take a flake URL, not an installable attrpath:
        # only `.` (or omitted) is accepted, at most one.
        [ "$operand" = "." ] || die "nix flake takes only '.' as a positional reference"
        installables=$((installables + 1))
        [ "$installables" -le 1 ] || die "nix flake accepts at most one positional reference"
        out+=("$operand")
        return 0
    fi
    if ! is_flake_ref "$operand"; then
        die "installable '$operand' is not allowed (only '.', '.#attrpath', or omitted workspace refs)"
    fi
    installables=$((installables + 1))
    case "$CMD" in
        eval | print-dev-env | develop)
            [ "$installables" -le 1 ] || die "$CMD accepts at most one installable"
            ;;
    esac
    out+=("$operand")
}

while [ "$#" -gt 0 ]; do
    arg="$1"
    shift

    if [ "$payload_started" = "1" ]; then
        # `nix develop --command ...`: everything after the boundary belongs
        # to the child command. Preserved verbatim, never parsed.
        out+=("$arg")
        continue
    fi

    if [ "$options_ended" = "1" ]; then
        append_operand "$arg"
        continue
    fi

    case "$arg" in
        --)
            # End of options: subsequent tokens are operands (installables
            # for non-fmt commands, formatter paths for fmt). A dash-prefixed
            # token after `--` is an operand, not an option.
            out+=("$arg")
            options_ended=1
            ;;
        -*)
            flag="${arg%%=*}"
            has_eq=0
            case "$arg" in
                *=*) has_eq=1 ;;
            esac
            if ! option_allowed "$CKEY" "$flag"; then
                die "option '$flag' is not allowed for '$CMD' in agent sessions"
            fi
            case "$flag" in
                --command | -c)
                    if [ "$CMD" != "develop" ]; then
                        die "'$flag' is only allowed for nix develop"
                    fi
                    out+=("$arg")
                    payload_started=1
                    continue
                    ;;
            esac
            # Value-taking options must use the space form; the `=form` is
            # rejected so `--set-env-var=NAME VALUE` cannot smuggle an extra
            # token past validation.
            if [ "$has_eq" = "1" ] && [ "$(flag_takes_value "$CKEY" "$flag")" != "none" ]; then
                die "option '$arg' must use the space-separated form"
            fi
            out+=("$arg")
            if [ "$has_eq" = "0" ]; then
                case "$(flag_takes_value "$CKEY" "$flag")" in
                    one)
                        [ "$#" -ge 1 ] || die "option '$flag' requires a value"
                        out+=("$1")
                        shift
                        ;;
                    two)
                        [ "$#" -ge 2 ] || die "option '$flag' requires two values"
                        out+=("$1" "$2")
                        shift 2
                        ;;
                esac
            fi
            ;;
        *)
            append_operand "$arg"
            ;;
    esac
done

exec -a nix "$NIX_REAL" "${out[@]}"