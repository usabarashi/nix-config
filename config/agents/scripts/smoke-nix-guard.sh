#!/usr/bin/env bash
# nix-agent-guard smoke test: parser/policy harness (no Nix daemon required).
#
# Validates the PATH `nix` guard shim (config/agents/scripts/nix-agent-guard.sh)
# against a mock nix binary so the accepted/denied grammar can be exercised
# anywhere, including CI or a machine without Nix. The seatbelt-side and
# daemon-side verification is host-level and covered separately:
#   * socket grant + /etc/nix read  -> two-host live seatbelt probe
#   * pinned vs installed nix       -> compare "${pkgs.nix}" --version with
#                                      the installed daemon client
#
# Usage: smoke-nix-guard.sh            (no credentials, no network)

set -euo pipefail

GUARD="${GUARD:-$(cd "$(dirname "$0")" && pwd -P)/nix-agent-guard.sh}"
if [ ! -f "$GUARD" ]; then
    echo "FAIL: guard script not found: $GUARD" >&2
    exit 1
fi

TMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
TMP="$(mktemp -d "$TMP_BASE/nix-guard-smoke.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# --- mock nix ---------------------------------------------------------------
cat > "$TMP/mock-nix" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "nix (Nix) 2.34.7"; exit 0; fi
printf 'argv='; printf '<%s>' "$@"; printf '\n'
printf 'env.NIX_CONFIG=%s\n' "${NIX_CONFIG-<unset>}"
printf 'env.NIX_CONFIG_HOME=%s\n' "${NIX_CONFIG_HOME-<unset>}"
printf 'env.NIX_REMOTE=%s\n' "${NIX_REMOTE-<unset>}"
MOCK
chmod +x "$TMP/mock-nix"

# --- fake workspace flake ----------------------------------------------------
mkdir -p "$TMP/ws"
printf '{ outputs = { }; }\n' > "$TMP/ws/flake.nix"

export AGENT_NIX_REAL_BIN="$TMP/mock-nix"
export AGENT_NIX_EXPECTED_VERSION="2.34.7"
export AGENT_TARGET_DIR="$TMP/ws"
export AGENT_TMP_DIR="$TMP/xdg"
mkdir -p "$AGENT_TMP_DIR"

run_guard() { (cd "$TMP/ws" && bash "$GUARD" "$@") 2>"$TMP/err"; }
expect_allow() {
    local desc="$1"; shift
    set +e
    out="$(run_guard "$@")"
    st=$?
    set -e
    [ "$st" -eq 0 ] || fail "$desc (exit $st): $(cat "$TMP/err")"
    pass "$desc"
}
expect_deny() {
    local desc="$1"; shift
    set +e
    out="$(run_guard "$@")"
    st=$?
    set -e
    [ "$st" -ne 0 ] || fail "$desc unexpectedly allowed: $out"
    pass "$desc (denied)"
}
expect_contains() {
    local desc="$1" needle="$2"; shift 2
    set +e
    out="$(run_guard "$@")"
    st=$?
    set -e
    [ "$st" -eq 0 ] || fail "$desc (exit $st): $(cat "$TMP/err")"
    echo "$out" | grep -qF "$needle" || fail "$desc: output missing '$needle': $out"
    pass "$desc"
}

echo "== nix-agent-guard smoke =="

# Informational
out="$(run_guard --version)"; pass "--version allowed"
expect_deny "--version with trailing operands" --version extra
expect_deny "REPL (no args)"
expect_deny "unknown global option before subcommand" --option
expect_deny "unknown subcommand (run)" run .#mac14-9
expect_deny "flake update" flake update
expect_deny "flake lock" flake lock
expect_deny "flake metadata" flake metadata

# Allowed core commands
expect_allow "build .#formatter --no-link" build .#formatter --no-link
expect_allow "build darwinConfigurations" build .#darwinConfigurations.aarch64-darwin.mac14-9.system --no-link
expect_allow "eval --json" eval .#formatter --json
expect_allow "fmt (bare)" fmt
expect_allow "fmt ./flake.nix" fmt ./flake.nix
expect_allow "flake check" flake check
expect_allow "flake show --json" flake show --json
expect_allow "develop with --command payload" develop .#devShells.aarch64-darwin.default --command true
expect_allow "build --impure (workspace root only)" build --impure .#formatter --no-link
expect_allow "--no-link only" build .#formatter --no-link

# Lock flags are injected in the Nix-option region, BEFORE --command payload.
out="$(run_guard develop .#devShells.aarch64-darwin.default --command echo hi)"
echo "$out" | grep -qF 'argv=<develop><--no-update-lock-file><--no-write-lock-file><.#devShells.aarch64-darwin.default><--command><echo><hi>' \
    || fail "develop lock-flags/payload ordering wrong: $out"
pass "develop lock flags inserted before --command; payload verbatim"
echo "$out" | grep -qF 'env.NIX_CONFIG=<unset>' || fail "NIX_CONFIG not scrubbed: $out"
echo "$out" | grep -qF 'env.NIX_REMOTE=daemon' || fail "NIX_REMOTE not forced: $out"
echo "$out" | grep -qF "env.NIX_CONFIG_HOME=$AGENT_TMP_DIR/nix/config" \
    || fail "NIX_CONFIG_HOME not redirected: $out"
pass "env scrub + NIX_*_HOME redirection"

# Denied shapes
expect_deny "external installable nixpkgs#hello" build nixpkgs#hello
expect_deny "path: installable" build path:/tmp/evil
expect_deny "store-path installable" build /nix/store/foo
expect_deny "nested ./subdir# flake" build ./subdir#formatter
expect_deny "--expr eval" eval --expr '1+1'
expect_deny "--apply eval" eval .#a --apply 'x: x'
expect_deny "--file" build -f default.nix
expect_deny "--option" build --option allow-import-from-derivation true .#x
expect_deny "--store" build --store /tmp/evil .#x
expect_deny "--override-input" build --override-input nixpkgs /tmp/x .#x
expect_deny "--inputs-from" eval --inputs-from /tmp/x .#a
expect_deny "--update-input" flake check --update-input nixpkgs
expect_deny "--recreate-lock-file" build --recreate-lock-file .#x
expect_deny "--output-lock-file" build --output-lock-file /tmp/lock .#x
expect_deny "two eval installables" eval .#a .#b
expect_deny "two develop installables" develop .#a .#b --command true
expect_deny "fmt path outside workspace" fmt /etc/passwd
expect_deny "orphaned --command for build" build --command true
expect_deny "global -v verbose" -v build .#x
expect_deny "unknown short option" build -x .#x
expect_deny "profile install" profile install
expect_deny "nix flake subcommand garbage" flake garbage

# Version gate
AGENT_NIX_EXPECTED_VERSION="9.9.9" run_guard --version >/dev/null 2>&1 \
    && fail "version mismatch was not rejected"
pass "version-gate fails closed on stamp mismatch"

# fmt value-form and -- boundary
expect_allow "fmt with -- and a path" fmt -- ./flake.nix
expect_deny "fmt -- with outside path" fmt -- /etc/passwd

# Staged-review additions: --impure for flake check/show (documented workflow)
expect_allow "flake check --impure" flake check --impure
expect_allow "flake show --impure" flake show --impure
# `--` really ends option parsing: dash tokens after `--` are operands
expect_deny "build -- --help (dash operand after --)" build -- --help
expect_deny "develop -- --command payload (dash operand after --)" develop -- --command true
# =form of a value-taking option is rejected
expect_deny "develop --set-env-var=name value (eq + extra token)" develop --set-env-var=A B --command true
expect_allow "develop --set-env-var A B --command true (space form)" develop --set-env-var A B --command true
# flake check/show accept only '.' (or omitted) as positional
expect_deny "flake check .#attr installable" flake check .#formatter
expect_deny "flake check two positionals" flake check . .
expect_deny "flake show two positionals after --" flake show -- . .

# fmt receives the same lock-policy flags as every other flake command
out="$(run_guard fmt)"
echo "$out" | grep -qF 'argv=<fmt><--no-update-lock-file><--no-write-lock-file>' \
    || fail "fmt does not receive lock flags: $out"
pass "fmt receives lock flags"

# A stale/inherited NIX env cannot activate the shim (fail-closed on bad pin)
set +e
AGENT_NIX_REAL_BIN="$TMP/no-such-nix" run_guard --version >/dev/null 2>&1
st=$?
set -e
[ "$st" -ne 0 ] || fail "shim accepted a nonexistent pinned nix path"
pass "nonexistent pinned nix fails closed"

echo "== all nix-agent-guard smoke cases passed =="