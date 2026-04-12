---
name: codex-second-opinion
description: "For non-Codex agents only (Claude, Gemini). Get an independent second opinion from Codex CLI on any decision or question where a second perspective would be valuable. Appropriate triggers: any question with meaningful trade-offs, technical or architectural decisions, comparisons between options. Only invoke when a second perspective would meaningfully change the outcome."
---

# Codex Second Opinion

Get an alternative perspective from Codex CLI on any decision, design, or code.

## Task

0. **Self-Check (CRITICAL)**:
   - **Are you acting as a Codex agent?**
   - **If YES**: **STOP IMMEDIATELY**. Do not proceed. Consulting yourself is redundant and wasteful. Report to the user that you cannot use this skill as a Codex agent.
   - **If NO** (e.g., you are Claude or Gemini): Proceed to step 1.

1. Gather the context for the second opinion:
   - If `$ARGUMENTS` contains a specific question, use it as-is
   - If working on code, include relevant file contents or diff
   - If evaluating a design decision, summarize the options being considered
2. Construct a prompt using the template in the **Prompt Construction** section below
3. Execute Codex CLI using environment-specific handling:
   - **If `codex` is not on PATH**: report the missing dependency to the user and skip
   - **If running in Claude Code** (recommended flow):
     1. Ensure the `Bash` tool schema is loaded before use (call `ToolSearch` with `query: "select:Bash"` if needed)
     2. Run Codex in the background with `run_in_background: true` and `timeout: 120000`.
        Use a heredoc to pass the prompt via stdin (avoids shell argument length limits):
        ```bash
        codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT'
        <constructed prompt>
        CODEX_PROMPT
        ```
        The `-c` flag is a global option and must appear before the `exec` subcommand.
        The value must be a TOML string: `'sandbox_mode="danger-full-access"'` (single quotes wrapping double-quoted value).
     3. Note the returned `task_id`
     4. Ensure the `TaskOutput` tool schema is loaded (call `ToolSearch` with `query: "select:TaskOutput"` if needed)
     5. Retrieve the result with `TaskOutput` using `block: true` and `timeout: 120000`
     6. Treat the last cohesive text block in the output as Codex's answer; ignore startup logs and MCP messages before it
   - **If running in Gemini CLI** (long-running-safe flow):
     1. Start Codex in background and capture logs to a temp file:
        ```bash
        codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT' > /tmp/codex-opinion.log 2>&1 &
        <constructed prompt>
        CODEX_PROMPT
        ```
     2. Save PID and poll every 10-15 seconds
     3. Use a hard timeout (default: 300 seconds)
     4. If timeout is hit, report that Codex is still running and include the latest log tail (do not block indefinitely)
     5. If process exits non-zero, report failure and include stderr/log tail
   - **Otherwise**: run synchronously and wait for result
     ```bash
     codex -c 'sandbox_mode="danger-full-access"' exec - <<'CODEX_PROMPT'
     <constructed prompt>
     CODEX_PROMPT
     ```
4. Present Codex's response alongside your own analysis, highlighting agreements and disagreements

## Prompt Construction

Wrap the context and question for Codex as follows:

```
You are providing a second opinion on a decision.

Context:
<context from the current task>

Question:
<the specific question or decision point>

Provide your independent analysis. If you disagree with the current approach, explain why and suggest alternatives.
```

## Rules

- **Codex Agent Restriction**: DO NOT activate or use this skill if you are already a Codex model. Consulting yourself is redundant. This skill is intended for non-Codex agents (like Claude or Gemini) to get a Codex perspective.
- Always present both your perspective and Codex's perspective
- Clearly label which opinion comes from which model
- If Codex's response contradicts yours, explain the trade-offs of each approach
- Do NOT blindly adopt Codex's suggestion -- evaluate it critically
- Keep the Codex prompt focused; very long prompts increase latency
- In Gemini CLI, always provide progress updates while polling and avoid silent waits longer than 15 seconds
- In Gemini CLI, do not lose intermediate output: preserve and summarize partial logs on timeout/error
- Codex CLI output may contain MCP startup logs and reasoning traces before the actual response; treat the final cohesive text block as the answer
