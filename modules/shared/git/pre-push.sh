#!/usr/bin/env bash
# Global pre-push hook, installed by modules/shared/git/default.nix under
# core.hooksPath (~/.config/git/hooks/pre-push). Runs on every push from
# every repository on this machine, before anything is sent to the remote.
#
# Local enforcement boundary: no commit may leave this machine without a
# valid SSH signature (verified against gpg.ssh.allowedSignersFile). This
# catches every bypass at commit time, including `--no-gpg-sign`. The only
# escape hatch is `git push --no-verify`, which cannot be blocked from inside
# hooks — that is what GitHub's "Require signed commits" branch rule exists
# for.
set -eu

# Buffer stdin first: regardless of what the repository's own pre-push hook
# does with it, this hook still needs the same ref-update list.
refs="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/pre-push.XXXXXX")"
trap 'rm -f "$refs"' EXIT
cat > "$refs"

# Run the repository's own pre-push hook first if present. --git-common-dir
# (not --git-path) so core.hooksPath cannot resolve back to this script.
git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$git_common_dir" ] && [ -x "$git_common_dir/hooks/pre-push" ]; then
  "$git_common_dir/hooks/pre-push" "$@" < "$refs"
fi

# Zero OID sized for the repository's object format (SHA-256 repos get 64).
# Relaxing this to a hard-coded 40-char zero would misclassify deletions.
if [ "$(git rev-parse --show-object-format 2>/dev/null || echo sha1)" = "sha256" ]; then
  zeros="0000000000000000000000000000000000000000000000000000000000000000"
else
  zeros="0000000000000000000000000000000000000000"
fi

remote_name="${1:-origin}"
reject() {
  echo "error: refusing to push '$1':" >&2
  shift
  printf '%s\n' "$@" >&2
  exit 1
}

while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$local_sha" = "$zeros" ] && continue # deleting a remote branch

  # Commits being introduced to this remote:
  #  - ref update: everything reachable from the new tip but not the old
  #    remote tip (handles divergent force pushes too)
  #  - new branch: everything reachable from the tip that is not already on
  #    any ref of this remote, so history already pushed via another branch
  #    is not re-verified (and cannot false-positive on imported history)
  if [ "$remote_sha" = "$zeros" ]; then
    range=("$local_sha" --not --remotes="$remote_name")
  else
    range=("$remote_sha..$local_sha")
  fi

  # FAIL CLOSED: if the enumeration itself fails (object missing locally,
  # bad revision, non-commit tip), a "no output" result must never be
  # interpreted as "everything is signed" — refuse the push.
  log_out=''
  if ! log_out=$(git log --format='%G? %H %s' "${range[@]}" 2>&1); then
    reject "$local_ref" "could not verify signatures for $local_ref:" "$log_out"
  fi

  # %G? => G: good / U: good but unknown signer / N: no signature / ...
  # U is rejected too: signing with a key outside allowed_signers is not
  # something we should propagate silently.
  unsigned=$(printf '%s\n' "$log_out" | grep -v '^G ' || true)

  if [ -n "$unsigned" ]; then
    reject "$local_ref" "$unsigned"
  fi
done < "$refs"