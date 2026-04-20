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
   - **Isolated `HOME`** to prevent MCP servers, IDE companion integration, and persona/voice extensions from deadlocking Gemini in the non-TTY Bash subshell. Gemini CLI 0.38.2+ spawns MCP children and opens an IDE-companion socket on startup that hang indefinitely in Claude Code's Bash sandbox (no PTY; `openpty` is prohibited). The older `--allowed-mcp-server-names ""` / `-e ""` approach is now rejected by 0.38.2 as an invalid policy rule (`mcpName is required if specified (cannot be empty)`). An isolated `HOME` with a minimal `settings.json` is the only reliable way to run Gemini headlessly from Claude Code Bash; it also prevents persona voices and prior-session state from leaking into the response.
   - Redirect output to a tempfile so it survives regardless of retrieval path.

**Pre-choose the output path yourself** (used by both code branches below). Pick a unique literal filesystem path in advance — e.g., `/tmp/gemini-opinion-<unix-timestamp>-<random>.log`, assembled in your working context (not via `mktemp` inside the snippet, because that binds the path to a shell variable you cannot retrieve later). Reuse the exact same literal path verbatim in the Bash invocation and in the follow-up `Read`. This avoids any dependency on a harness-specific output-capture tool (`BashOutput`, task output files, etc.). Pick a similarly unique literal path for the isolated `HOME` directory — e.g., `/tmp/gemini-skill-home-<unix-timestamp>-<random>`.

### Isolated HOME preamble

Inline this block before the `gemini` call. It inherits the user's real `security.auth` from `~/.gemini/settings.json` (so Vertex AI / API-key / OAuth all work), while disabling MCP, IDE, preview features, prompt completion, and hooks. Requires `jq` on PATH.

```bash
ISO=<ISOLATED_HOME>   # literal path you chose, e.g. /tmp/gemini-skill-home-1776644000-abc
mkdir -p "$ISO/.gemini" "$ISO/.config/gcloud"
cp "$HOME/.gemini/oauth_creds.json" "$ISO/.gemini/" 2>/dev/null || true
cp "$HOME/.config/gcloud/application_default_credentials.json" "$ISO/.config/gcloud/" 2>/dev/null || true
{ cat "$HOME/.gemini/settings.json" 2>/dev/null || echo '{}'; } | jq '
  del(.hooks, .includeDirectories)
  | .tools = { sandbox: false }
  | .ide = { enabled: false }
  | .mcpServers = {}
  | .general = ((.general // {}) + { previewFeatures: false, enablePromptCompletion: false })
  | .privacy = { usageStatisticsEnabled: false }
' > "$ISO/.gemini/settings.json"
```

**If Bash supports `run_in_background: true`** (typical case):
```bash
# Bash tool: run_in_background: true, timeout: 300000
# Substitute <TMPFILE> and <ISOLATED_HOME> with the literal paths you chose above.
ISO=<ISOLATED_HOME>
# ... (inline the Isolated HOME preamble here) ...
HOME="$ISO" GEMINI_SANDBOX=false gemini -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text < /dev/null > <TMPFILE> 2>&1
rm -rf "$ISO"
```
Wait for the background task to finish, then `Read <TMPFILE>`. Do NOT add `sleep` / `kill -0` / `pgrep` poll loops — they burn tool-call budget and the harness's completion signal is authoritative. An interim `Read` "to peek at progress" is also unnecessary; the file is incomplete until Gemini exits. **If you are a nested subagent** (running inside an Agent/Task tool), do NOT use this background path — a subagent that ends its turn while Gemini is still running will lose the background task. Use the foreground fallback below instead. After reading, `rm <TMPFILE>`; if the harness denies `rm`, leave the file — `/tmp` is reclaimed by the OS. `TaskOutput` is for Agent/Task tool tasks — do not use it here.

**Foreground fallback** (use when `run_in_background` is unavailable, OR when you are a nested subagent):
```bash
# Bash tool: timeout: 300000
ISO=<ISOLATED_HOME>
# ... (inline the Isolated HOME preamble here) ...
HOME="$ISO" GEMINI_SANDBOX=false gemini -p "$(cat <<'GEMINI_PROMPT'
<constructed prompt>
GEMINI_PROMPT
)" -o text < /dev/null > <TMPFILE> 2>&1
rm -rf "$ISO"
```
Bash blocks until Gemini finishes or the tool timeout fires. On return, `Read <TMPFILE>` and then `rm <TMPFILE>`. Do not use `&` + `$!` polling — it adds PID tracking for no benefit once you control the Bash tool timeout. Do NOT use `trap 'rm -f $TMPFILE' EXIT` in any snippet that backgrounds a process — the trap fires when the launching shell exits, deleting the file before the background process writes to it.

Always close stdin with `< /dev/null`. Without it, Gemini may block waiting for additional prompt input appended via stdin.

3. Parse output: ignore startup logs, MCP registration/tool-call errors (these may still appear inline in the relaunched-heap phase), reasoning traces, and persona/voice styling that somehow still leaked in. Treat the final substantive plain-text block as the answer. If it arrives in a persona voice, extract the content and present it in neutral prose.

4. Present both perspectives (labeled by model), highlight agreements and disagreements. Evaluate Gemini's suggestion critically — do not blindly adopt it.

## Error Handling

On any failure — `gemini` not found, auth error (`ADC must be`, `gcloud.auth`), network error, or timeout — report the reason to the user and proceed with your own analysis only. Discard partial output on timeout as unreliable. Always `rm -rf "$ISO"` on error paths too.

Specific failure modes:
- `ADC must be external_account, authorized_user, or external_account_authorized_user` — the ADC file was not copied into the isolated `HOME`. Verify `~/.config/gcloud/application_default_credentials.json` exists on the real `HOME`.
- `Invalid policy rule: mcpName is required if specified (cannot be empty)` — you passed `--allowed-mcp-server-names ""` or `-e ""`. Remove those flags; this skill uses isolated `HOME` for isolation, not flags.
- Timeout with 0 bytes output — the isolated `HOME` was not applied, or its `settings.json` still has `ide.enabled: true` / non-empty `mcpServers`. Double-check the preamble was inlined verbatim.
- `jq: command not found` or empty `settings.json` — ensure `jq` is installed and on PATH in the harness you are running under, or replace the `jq` pipeline with an equivalent `python3 -c` / inline heredoc snippet.

## Shell Escaping

Use a heredoc to build prompt text safely. This avoids shell escaping and quoting issues for multi-line content. Note that prompts passed via `-p` are still subject to `ARG_MAX`.
