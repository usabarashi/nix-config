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

**If `run_in_background` and `TaskOutput` are available**:
```bash
# Bash tool: run_in_background: true, timeout: 120000
codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT' 2>&1
<constructed prompt>
CODEX_PROMPT
```
Then retrieve with `TaskOutput` (`block: true`, `timeout: 120000`).

**Otherwise** (tmpfile + poll):
```bash
TMPFILE=$(mktemp /tmp/codex-opinion.XXXXXX.log)
trap "rm -f $TMPFILE" EXIT
codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT' > "$TMPFILE" 2>&1 &
<constructed prompt>
CODEX_PROMPT
```
Poll PID every 10-15s. Hard timeout: 300s.

3. Parse output: ignore startup logs, MCP errors, and reasoning traces before the final text. Treat the last plain-text block as the answer.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Codex's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `codex` not found, auth error, network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc (`<<'CODEX_PROMPT'`) to pass prompts via stdin. This avoids shell argument length limits and escaping issues.
