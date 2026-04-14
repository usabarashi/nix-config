---
name: gemini-second-opinion
description: "Non-Gemini agents only. Get an independent second opinion from Gemini CLI on decisions with meaningful trade-offs."
---

# Gemini Second Opinion

If you are a Gemini agent, STOP. Tell the user this skill is for non-Gemini agents only.

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

2. Run Gemini CLI. Always set `GEMINI_SANDBOX=false` (nested sandbox-exec is prohibited on macOS):

**If `run_in_background` and `TaskOutput` are available**:
```bash
# Bash tool: run_in_background: true, timeout: 120000
GEMINI_SANDBOX=false gemini -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text 2>&1
```
Then retrieve with `TaskOutput` (`block: true`, `timeout: 120000`).

**Otherwise** (tmpfile + poll):
```bash
TMPFILE=$(mktemp /tmp/gemini-opinion.XXXXXX.log)
GEMINI_SANDBOX=false gemini -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text > "$TMPFILE" 2>&1 &
PID=$!
```
Poll `$PID` every 10-15s. Hard timeout: 300s. On timeout, `kill $PID` and clean up `$TMPFILE`.

3. Parse output: ignore startup logs, MCP errors, and reasoning traces before the final text. Treat the last plain-text block as the answer.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Gemini's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `gemini` not found, auth error (`ADC must be`, `gcloud.auth`), network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc to build prompt text safely. This avoids shell escaping and quoting issues for multi-line content. Note that prompts passed via `-p` are still subject to `ARG_MAX`.
