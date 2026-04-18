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

**Pre-choose the output path yourself** (used by both code branches below). Pick a unique literal filesystem path in advance — e.g., `/tmp/gemini-opinion-<unix-timestamp>-<random>.log`, assembled in your working context (not via `mktemp` inside the snippet, because that binds the path to a shell variable you cannot retrieve later). Reuse the exact same literal path verbatim in the Bash invocation and in the follow-up `Read`. This avoids any dependency on a harness-specific output-capture tool (`BashOutput`, task output files, etc.).

**If Bash supports `run_in_background: true`** (typical case):
```bash
# Bash tool: run_in_background: true, timeout: 300000
# Substitute <TMPFILE> with the literal path you chose above.
GEMINI_SANDBOX=false gemini --allowed-mcp-server-names "" -e "" -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text > <TMPFILE> 2>&1
```
Wait for the background task to finish, then `Read <TMPFILE>`. Do NOT add `sleep` / `kill -0` / `pgrep` poll loops — they burn tool-call budget and the harness's completion signal is authoritative. An interim `Read` "to peek at progress" is also unnecessary; the file is incomplete until Gemini exits. **If you are a nested subagent** (running inside an Agent/Task tool), do NOT use this background path — a subagent that ends its turn while Gemini is still running will lose the background task. Use the foreground fallback below instead. After reading, `rm <TMPFILE>`; if the harness denies `rm`, leave the file — `/tmp` is reclaimed by the OS. `TaskOutput` is for Agent/Task tool tasks — do not use it here.

**Foreground fallback** (use when `run_in_background` is unavailable, OR when you are a nested subagent):
```bash
# Bash tool: timeout: 300000
GEMINI_SANDBOX=false gemini --allowed-mcp-server-names "" -e "" -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text > <TMPFILE> 2>&1
```
Bash blocks until Gemini finishes or the tool timeout fires. On return, `Read <TMPFILE>` and then `rm <TMPFILE>`. Do not use `&` + `$!` polling — it adds PID tracking for no benefit once you control the Bash tool timeout. Do NOT use `trap 'rm -f $TMPFILE' EXIT` in any snippet that backgrounds a process — the trap fires when the launching shell exits, deleting the file before the background process writes to it.

3. Parse output: ignore startup logs, MCP registration/tool-call errors (these may appear inline mid-output, not just before the answer), reasoning traces, and persona/voice styling leaked from the caller's MCP context (e.g. a voicevox persona bleeding into Gemini's reply). Treat the final substantive plain-text block as the answer. If it arrives in a persona voice, extract the content and present it in neutral prose.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Gemini's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `gemini` not found, auth error (`ADC must be`, `gcloud.auth`), network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc to build prompt text safely. This avoids shell escaping and quoting issues for multi-line content. Note that prompts passed via `-p` are still subject to `ARG_MAX`.
