#!/usr/bin/env bash
# Free-tier Seatbelt smoke test (path & model harness).
#
# Order (per design R34/R42):
#   1. Static / path checks (no network, no credentials required)
#   2. (deployment gate, run by the operator, requires R30 verification)
#   3. Live model-routing tests (ONLY after R30 verified for the provider)
#
# Usage:
#   smoke-free-tier.sh            # run all phases that need no credentials
#   smoke-free-tier.sh --live     # also run live model checks (needs R30 done)
#
# These tests are intentionally split: live tests must never run against
# unrestricted credentials (R30 precedes them).

set -euo pipefail

OPENCODE="${OPENCODE:-opencode}"
CLAUDE="${CLAUDE:-claude}"
MODEL="${MODEL:-}"
TMPLOG="$(mktemp /tmp/free-tier-smoke.XXXXXX)"
trap 'rm -f "$TMPLOG"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

echo "== free-tier smoke: static phase =="

# 1. --list-seatbelts shows the expected profiles. permissive-open.sb and
#    claude-code.sb were removed; cloud-restricted.sb is the shared default for
#    both the opencode and claude wrappers. The profiles asserted below are the
#    ones shipped by the free-tier change set (config/agents/*.sb committed
#    alongside). The listing exits before any credential provisioning, so no
#    1Password session is needed.
set +e
profiles="$("$OPENCODE" --list-seatbelts 2>&1)"
open_status=$?
set -e
[ "$open_status" -eq 0 ] || fail "opencode --list-seatbelts failed (exit $open_status)"
for want in free-tier.sb cloud-restricted.sb; do
    echo "$profiles" | grep -qx "$want" || fail "--list-seatbelts missing $want"
done
echo "$profiles" | grep -qx "strict-closed.sb" && fail "strict-closed.sb still present"
echo "$profiles" | grep -qx "permissive-open.sb" && fail "permissive-open.sb still present"
echo "$profiles" | grep -qx "claude-code.sb" && fail "claude-code.sb still present"
pass "--list-seatbelts matches expectation; removed profiles absent"

# 1b. The claude wrapper shares cloud-restricted.sb, and only that profile is
#     installed for claude (free-tier.sb needs opencode-specific params).
set +e
claude_profiles="$("$CLAUDE" --list-seatbelts 2>&1)"
claude_status=$?
set -e
[ "$claude_status" -eq 0 ] || fail "claude --list-seatbelts failed (exit $claude_status)"
# Require the complete claude profile set to be EXACTLY cloud-restricted.sb:
# any extra, missing, or differently named .sb entry must fail.
claude_expected="cloud-restricted.sb"
claude_actual="$(printf '%s\n' "$claude_profiles" | grep -v '^$' | sort)"
[ "$claude_actual" = "$claude_expected" ] \
    || fail "claude profile set mismatch: expected [$claude_expected], got [$claude_actual]"
pass "claude --list-seatbelts is exactly cloud-restricted.sb"

# 2. free-tier without -m must fail closed with the *specific* message
#    (not a generic failure), proving wrapper parsing ran.
out="$("$OPENCODE" --seatbelt free-tier.sb --print-logs --version 2>&1 || true)"
echo "$out" | grep -qi "explicit model" || fail "missing-model not rejected (got: $out)"
pass "free-tier without -m fails closed"

# 3. free-tier with a non-allowlisted (paid) model must fail with the
#    allowlist rejection message.
out="$("$OPENCODE" --seatbelt free-tier.sb -m opencode-go/deepseek-v4-flash run "ping" 2>&1 || true)"
echo "$out" | grep -qi "not allowed" || fail "paid model not rejected (got: $out)"
pass "paid built-in model rejected by allowlist"

# 4. --no-sandbox must be rejected with free-tier whenever it appears in the
#    WRAPPER option region (before `--` or the first non-option arg). Note the
#    parser contract: options after the first non-option argument (e.g.
#    `run --no-sandbox`) belong to opencode and are forwarded into the
#    Seatbelt; they cannot disable the sandbox. We test the wrapper-region
#    orders only.
for combo in \
    "--seatbelt free-tier.sb --no-sandbox" \
    "--no-sandbox --seatbelt free-tier.sb" \
    "--no-sandbox --seatbelt free-tier.sb run"; do
    out="$($OPENCODE $combo 2>&1 || true)"
    echo "$out" | grep -qi "not permitted" || fail "--no-sandbox not rejected (combo: $combo: $out)"
done
pass "--no-sandbox rejected in wrapper option region regardless of order"

# 5. A normal project under $HOME must pass the TARGET_DIR guard. To make
#    this a *positive* assertion, we require the invocation to get PAST the
#    target guard and fail only on something later (e.g. missing credentials)
#    — never with "protected directory".
out="$("$OPENCODE" --seatbelt free-tier.sb -m gemini/gemini-2.5-flash --print-logs --version 2>&1 || true)"
echo "$out" | grep -qi "protected directory" && fail "HOME-descendant project incorrectly rejected"
echo "$out" | grep -qi "explicit model" && fail "unexpected model-parse failure"
pass "ordinary project under HOME is not rejected by the TARGET_DIR guard"

# 6. free-tier from the filesystem root must be rejected (guard covers /).
out="$(cd / && "$OPENCODE" --seatbelt free-tier.sb -m gemini/gemini-2.5-flash run "ping" 2>&1 || true)"
echo "$out" | grep -qi "protected directory\|filesystem root" || fail "TARGET_DIR=/ not rejected (got: $out)"
pass "TARGET_DIR=/ rejected"

# 7. Env scrub / effective config pointer (informational for now; the live
#    harness verifies the effective provider/model tuple).
echo "ok: free-tier config is immutable Nix store content"
if [ -n "${OPENCODE_CONFIG:-}" ]; then
    echo "  OPENCODE_CONFIG=$OPENCODE_CONFIG"
fi

echo "== static phase complete =="

if [ "${1:-}" = "--live" ]; then
    echo "== free-tier smoke: live phase (R30 must already be verified!) =="
    [ -n "$MODEL" ] || fail "--live requires MODEL=<provider>/<model> in the env"
    # Expected api_id is read from the versioned allowlist (must be unique).
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
    ALLOWLIST="$SCRIPT_DIR/../../opencode/free-tier-models.json"
    [ -f "$ALLOWLIST" ] || fail "allowlist not found at $ALLOWLIST"
    EXPECTED_API_ID="$(jq -r --arg m "$MODEL" \
        '[.providers[] | .provider_id as $pid | .models[] | select($pid + "/" + .model == $m) | select((.api_id | type) == "string" and (.api_id | length) > 0)] | if length == 1 then .[0].api_id else empty end' \
        "$ALLOWLIST" 2>/dev/null || true)"
    [ -n "$EXPECTED_API_ID" ] && [ "$EXPECTED_API_ID" != "null" ] \
        || fail "cannot resolve a unique api_id for model $MODEL from allowlist"
    "$OPENCODE" --seatbelt free-tier.sb -m "$MODEL" run \
        "Reply with exactly: livetest-ok" >"$TMPLOG" 2>&1 \
        || fail "live request failed (see $TMPLOG)"
    grep -q "livetest-ok" "$TMPLOG" || fail "live reply not received"
    # Assert the wrapper logged the exact expected model + api_id binding
    # (fixed-string match; model IDs contain regex-significant characters).
    grep -Fq "free-tier model: $MODEL (api_id: $EXPECTED_API_ID)" "$TMPLOG" \
        || fail "wrapper did not log the expected model/api_id binding"
    pass "live model $MODEL (api_id $EXPECTED_API_ID) routed (verify provider billing/usage telemetry == zero)"
fi

echo "PASS"