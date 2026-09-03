#!/bin/bash
# git-agent-guard: a `git` shim placed FIRST on the agent-sandbox PATH.
#
# Agent sessions are granted read/write on the current project, so a naive
# `git commit` would succeed even though the session's seatbelt already blocks
# the network path to any remote and hides the user's signing identity. This
# shim turns commit/history mutations into a loud failure inside agent
# sessions instead of leaving them to be discovered at push time.
#
# This is friction, not a security boundary: a model executing arbitrary code
# as the user can craft a commit through other means (e.g. invoking the store
# git directly, git mktree/write-tree plumbing, or a trivial C program). The
# real walls are the agents' own permission configuration
# (config/claude/settings.json, config/opencode/opencode.json) and the global
# pre-push signature check in modules/shared/git.nix.
#
# Deployment: copied (NOT symlinked, because a symlink into this repo is not
# readable by the sandbox when the agent runs in another project) to
#   ~/.config/opencode/bin/git   (opencode cloud sessions)
#   ~/.claude/bin/git            (claude sessions)
# and the wrapper puts the directory first on the sandbox PATH. Editing this
# file takes effect after the next darwin-rebuild (home-manager copies it).
#
# The deny list below is the configurable part: edit freely, no Nix involved.

set -eu

# ---------------------------------------------------------------------------
# 1. Resolve the REAL git binary, i.e. the first `git` on PATH that is not
#    this shim's own directory.
# ---------------------------------------------------------------------------
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
real_git=""
IFS=':' read -r -a path_parts <<< "${PATH:-}"
for p in "${path_parts[@]}"; do
  [ -n "$p" ] || continue
  if [ "$(cd "$p" 2>/dev/null && pwd -P)" = "$SELF_DIR" ]; then
    continue
  fi
  if [ -x "$p/git" ]; then
    real_git="$p/git"
    break
  fi
done
if [ -z "$real_git" ]; then
  echo "error: git-agent-guard: could not locate the real git binary on PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Extract the subcommand, skipping git global options. -c, -C and friends
#    consume a following value, which must not be mistaken for the subcommand
#    — `git -c commit.gpgSign=false commit -m ...` must resolve to "commit".
# ---------------------------------------------------------------------------
cmd=""
skip_next=0
for arg in "$@"; do
  if [ "$skip_next" = "1" ]; then
    skip_next=0
    continue
  fi
  case "$arg" in
    -c|-C|--git-dir|--work-tree|--namespace|--exec-path|--config-env|--super-prefix)
      skip_next=1
      continue
      ;;
    --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--config-env=*|--super-prefix=*)
      continue
      ;;
    -*) continue ;;
    *)
      cmd="$arg"
      break
      ;;
  esac
done

# ---------------------------------------------------------------------------
# 3. Inline configuration must not smuggle in aliases:
#      git -c alias.x=commit x
#      git --config-env=alias.x=MY_ENV x
#    Both are rejected outright; --config-env is also useless to a sandbox
#    agent for anything legitimate.
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --config-env* | alias.*=*)
      echo "error: git-agent-guard: inline configuration that sets aliases is not allowed in agent sessions." >&2
      exit 1
      ;;
  esac
done

# Block git writes that create aliases (`git config alias.x ...`). Direct
# edits to .git/config are out of scope for this friction layer.
if [ "$cmd" = "config" ]; then
  for arg in "$@"; do
    case "$arg" in
      alias.*)
        echo "error: git-agent-guard: setting git aliases is not allowed in agent sessions." >&2
        exit 1
        ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# 4. Deny subcommands that create commits, move refs, or rewrite repository
#    state. Intentional conservative superset of the agents' own permission
#    denylists (Claude denies branch/checkout/switch; an agent that merges or
#    rebases is just as autonomous as one that commits directly).
# ---------------------------------------------------------------------------
case "$cmd" in
  commit | push | commit-tree | update-ref | replace | notes | tag \
  | reset | restore | clean | stash | gc | prune | repack | maintenance \
  | filter-branch | merge | rebase | cherry-pick | revert | am | pull \
  | checkout | switch | branch | fast-import)
    echo "error: git-agent-guard: '$cmd' is not allowed in agent sessions." >&2
    echo >&2
    echo "  AI agents may edit files but must not create commits, rewrite" >&2
    echo "  history, or touch branches/refs on their own. Done with your" >&2
    echo "  changes:" >&2
    echo "    git status      # show what changed" >&2
    echo "    git diff        # review" >&2
    echo "  and ask the user to run the git command." >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# 5. Read-only commands agents legitimately need; skipped for the alias check
#    so pre-existing aliases on those names never false-block.
# ---------------------------------------------------------------------------
case "$cmd" in
  status | diff | log | show | grep | fetch | shortlog | blame | whatchanged \
  | rev-parse | rev-list | ls-files | ls-tree | cat-file | for-each-ref \
  | symbolic-ref | verify-commit | verify-tag | version | help | config \
  | clone | init | apply | archive | describe | fsck) ;;
  *)
    # Repository-local aliases: a stale or adversarial `alias.x` for a
    # non-safe subcommand could expand to anything (including `!` shell
    # commands), so refuse rather than let git expand it.
    if [ -n "$cmd" ] && [ -n "$("$real_git" config --get "alias.$cmd" 2>/dev/null || true)" ]; then
      echo "error: git-agent-guard: '$cmd' is a git alias, which agent sessions may not use." >&2
      exit 1
    fi
    ;;
esac

exec "$real_git" "$@"