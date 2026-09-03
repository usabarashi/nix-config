#!/usr/bin/env bash
# Global pre-commit hook, installed by modules/shared/git/default.nix under
# core.hooksPath (~/.config/git/hooks/pre-commit). Runs on every commit from
# every repository on this machine.
set -eu

# Cheap early failure: reject commits created with signing disabled via
# config override (`git -c commit.gpgSign=false commit`). Does NOT catch
# `--no-gpg-sign`; that is enforced at push time by the pre-push hook.
if [ "$(git config --bool commit.gpgSign 2>/dev/null || echo false)" != "true" ]; then
  echo "error: commit.gpgSign is not enabled; refusing unsigned commit" >&2
  exit 1
fi

# Run the repository's own pre-commit hook first if present. We must use
# --git-common-dir (not --git-path hooks/pre-commit) because the latter
# honors core.hooksPath and would resolve to this script itself, causing
# infinite recursion / fork bomb.
git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$git_common_dir" ] && [ -x "$git_common_dir/hooks/pre-commit" ]; then
  "$git_common_dir/hooks/pre-commit" "$@"
fi

# gitleaks is declared in home.packages, so it is on PATH in every normal
# shell that invokes git. Fail closed (with guidance) if it is somehow absent.
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "error: gitleaks not found on PATH; cannot run the staged-secret scan." >&2
  echo "  It is installed via home.packages (modules/shared/git/default.nix)." >&2
  exit 1
fi
exec "$(command -v gitleaks)" protect --staged --redact --verbose