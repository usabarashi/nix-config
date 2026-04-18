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

2. Run Gemini CLI with three invariants:
   - `GEMINI_SANDBOX=false` (nested sandbox-exec is prohibited on macOS).
   - `--allowed-mcp-server-names ""` and `-e ""` to isolate from the caller's MCP servers and extensions; without this, persona voices (e.g. voicevox) or prior-session state can leak in, including off-topic responses that answer a different question than the one you sent.
   - Redirect output to a tempfile so it survives regardless of retrieval path.

**If Bash supports `run_in_background: true`** (typical case):
```bash
# Bash tool: run_in_background: true, timeout: 120000
TMPFILE=$(mktemp /tmp/gemini-opinion.XXXXXX.log)
GEMINI_SANDBOX=false gemini --allowed-mcp-server-names "" -e "" -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text > "$TMPFILE" 2>&1
```
Wait for completion, then retrieve output. Preferred: `BashOutput` with the returned `shell_id`. If `BashOutput` is not exposed in your environment, `Read` the `$TMPFILE` directly. `TaskOutput` is for Agent/Task tool tasks — do not use it here.

**If `run_in_background` is unavailable** (foreground-only environment, last resort):
```bash
TMPFILE=$(mktemp /tmp/gemini-opinion.XXXXXX.log)
GEMINI_SANDBOX=false gemini --allowed-mcp-server-names "" -e "" -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text > "$TMPFILE" 2>&1 &
PID=$!
```
Poll `$PID` every 10-15s. Hard timeout: 300s. On timeout, `kill $PID` and clean up `$TMPFILE`.

3. Parse output: ignore startup logs, MCP registration/tool-call errors (these may appear inline mid-output, not just before the answer), reasoning traces, and persona/voice styling leaked from the caller's MCP context (e.g. a voicevox persona bleeding into Gemini's reply). Treat the final substantive plain-text block as the answer. If it arrives in a persona voice, extract the content and present it in neutral prose.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Gemini's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `gemini` not found, auth error (`ADC must be`, `gcloud.auth`), network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc to build prompt text safely. This avoids shell escaping and quoting issues for multi-line content. Note that prompts passed via `-p` are still subject to `ARG_MAX`.
