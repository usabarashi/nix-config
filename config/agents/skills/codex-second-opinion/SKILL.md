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
# Redirect output to a file so it survives regardless of BashOutput availability.
TMPFILE=$(mktemp /tmp/codex-opinion.XXXXXX.log)
codex -c 'sandbox_mode="danger-full-access"' exec - > "$TMPFILE" 2>&1 <<'CODEX_PROMPT'
<constructed prompt>
CODEX_PROMPT
```
Wait for completion, then retrieve output. Preferred: `BashOutput` with the returned `shell_id`. If `BashOutput` is not exposed in your environment, `Read` the `$TMPFILE` directly. `TaskOutput` is for Agent/Task tool tasks — do not use it here.

**If `run_in_background` is unavailable** (foreground-only environment, last resort):
```bash
TMPFILE=$(mktemp /tmp/codex-opinion.XXXXXX.log)
codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT' > "$TMPFILE" 2>&1 &
<constructed prompt>
CODEX_PROMPT
PID=$!
```
Poll `$PID` every 10-15s. Hard timeout: 300s. On timeout, `kill $PID` and clean up `$TMPFILE`.

3. Parse output: ignore startup logs, MCP errors, reasoning traces, and trailing metadata (`tokens used`, `session id`, token summary lines). Treat the last substantive plain-text block before those metadata lines as the answer. If the same answer appears twice (once inline, once echoed after metadata), take either occurrence — they are equivalent.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Codex's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `codex` not found, auth error, network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc (`<<'CODEX_PROMPT'`) to pass prompts via stdin. This avoids shell escaping and quoting issues. Codex `exec -` reads from stdin, so this is not subject to `ARG_MAX`.
