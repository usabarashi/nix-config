---
name: codex-second-opinion
description: "Non-Codex agents only. Get an independent second opinion from Codex CLI on decisions with meaningful trade-offs."
---

# Codex Second Opinion

If you are a Codex agent, STOP. Tell the user this skill is for non-Codex agents only.

## Steps

1. Build a concise prompt from `$ARGUMENTS` if provided; otherwise infer the question from the current task context. Keep it focused on decision-relevant information:

```
You are providing a second opinion on a decision.

Context:
<context from the current task>

Question:
<the specific question or decision point>

Provide your independent analysis. If you disagree with the current approach, explain why and suggest alternatives.
```

2. Run Codex CLI. Always set `sandbox_mode="danger-full-access"` (nested sandbox-exec is prohibited on macOS):

**If Bash supports `run_in_background: true`** (typical case):
```bash
# Bash tool: run_in_background: true, timeout: 120000
# Echo the tempfile path so it is retrievable via BashOutput;
# Codex output itself is redirected to the file.
TMPFILE=$(mktemp /tmp/codex-opinion.XXXXXX.log)
echo "TMPFILE=$TMPFILE"
codex -c 'sandbox_mode="danger-full-access"' exec - > "$TMPFILE" 2>&1 <<'CODEX_PROMPT'
<constructed prompt>
CODEX_PROMPT
echo "EXIT=$?"
```
Retrieve in two steps: (a) `BashOutput` with the returned `shell_id` — use it to capture the echoed `TMPFILE=...` path and to confirm completion via the `EXIT=` line; it will NOT contain Codex's output because stdout/stderr are redirected to the file. (b) `Read` the concrete `TMPFILE` path for the actual answer. After reading, delete the file with `rm "<tmpfile>"` (keep it only when debugging). `TaskOutput` is for Agent/Task tool tasks — do not use it here.

**If `run_in_background` is unavailable** (foreground-only environment, last resort):
```bash
TMPFILE=$(mktemp /tmp/codex-opinion.XXXXXX.log)
echo "TMPFILE=$TMPFILE"
codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT' > "$TMPFILE" 2>&1 &
<constructed prompt>
CODEX_PROMPT
PID=$!
echo "PID=$PID"
```
Capture the echoed `TMPFILE` and `PID` from the foreground output; subsequent tool calls need the concrete values. Poll with `kill -0 <PID>` every 10-15s. Hard timeout: 300s. On timeout, `kill <PID>` and `rm <TMPFILE>`. On success, `Read <TMPFILE>` then `rm <TMPFILE>`. Do NOT use `trap 'rm -f $TMPFILE' EXIT` in the launching shell — the trap fires when that Bash invocation exits, deleting the file before the background process writes to it.

3. Parse output: ignore startup logs, MCP errors, reasoning traces, and trailing metadata (`tokens used`, `session id`, token summary lines). Treat the last substantive plain-text block before those metadata lines as the answer. If the same answer appears twice (once inline, once echoed after metadata), take either occurrence — they are equivalent.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Codex's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `codex` not found, auth error, network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc (`<<'CODEX_PROMPT'`) to pass prompts via stdin. This avoids shell escaping and quoting issues. Codex `exec -` reads from stdin, so this is not subject to `ARG_MAX`.
