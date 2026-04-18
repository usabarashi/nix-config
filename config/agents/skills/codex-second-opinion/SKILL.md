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

**Pre-choose the output path yourself** (used by both code branches below). Pick a unique literal filesystem path in advance — e.g., `/tmp/codex-opinion-<unix-timestamp>-<random>.log`, assembled in your working context (not via `mktemp` inside the snippet, because that binds the path to a shell variable you cannot retrieve later). Reuse the exact same literal path verbatim in the Bash invocation and in the follow-up `Read`. This avoids any dependency on a harness-specific output-capture tool (`BashOutput`, task output files, etc.).

**If Bash supports `run_in_background: true`** (typical case):
```bash
# Bash tool: run_in_background: true, timeout: 300000
# Substitute <TMPFILE> with the literal path you chose above.
codex -c 'sandbox_mode="danger-full-access"' exec - > <TMPFILE> 2>&1 <<'CODEX_PROMPT'
<constructed prompt>
CODEX_PROMPT
```
Wait for the background task to finish, then `Read <TMPFILE>`. Do NOT add `sleep` / `kill -0` / `pgrep` poll loops — they burn tool-call budget and the harness's completion signal is authoritative. An interim `Read` "to peek at progress" is also unnecessary; the file is incomplete until Codex exits. **If you are a nested subagent** (running inside an Agent/Task tool), do NOT use this background path — a subagent that ends its turn while Codex is still running will lose the background task. Use the foreground fallback below instead. After reading, `rm <TMPFILE>`; if the harness denies `rm`, leave the file — `/tmp` is reclaimed by the OS. `TaskOutput` is for Agent/Task tool tasks — do not use it here.

**Foreground fallback** (use when `run_in_background` is unavailable, OR when you are a nested subagent):
```bash
# Bash tool: timeout: 300000
codex -c 'sandbox_mode="danger-full-access"' exec - > <TMPFILE> 2>&1 <<'CODEX_PROMPT'
<constructed prompt>
CODEX_PROMPT
```
Bash blocks until Codex finishes or the tool timeout fires. On return, `Read <TMPFILE>` and then `rm <TMPFILE>`. Do not use `&` + `$!` polling — it adds PID tracking for no benefit once you control the Bash tool timeout. Do NOT use `trap 'rm -f $TMPFILE' EXIT` in any snippet that backgrounds a process — the trap fires when the launching shell exits, deleting the file before the background process writes to it.

3. Parse output: ignore startup logs, MCP registration/errors, **MCP tool-call traces** (e.g. `voicevox.text_to_speech`, `serena.find_symbol` — any inline JSON or tool invocation lines from the caller's MCP context leaking into Codex's output, including cases where Codex itself invokes an MCP tool mid-reasoning), reasoning traces, and trailing metadata (`tokens used`, `session id`, token summary). The substantive answer is the main plain-text block; Codex sometimes prints it once inline and echoes it again after metadata. **Tiebreaker when both copies are complete: use the post-metadata echo** — it is Codex's canonical final form.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Codex's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `codex` not found, auth error, network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable.

## Shell Escaping

Use a heredoc (`<<'CODEX_PROMPT'`) to pass prompts via stdin. This avoids shell escaping and quoting issues. Codex `exec -` reads from stdin, so this is not subject to `ARG_MAX`.
