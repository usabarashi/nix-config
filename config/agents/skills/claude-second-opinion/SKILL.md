---
name: claude-second-opinion
description: "For non-Claude agents only (Codex, Gemini). Get an external second opinion from Claude CLI on a decision with uncertain trade-offs or multiple viable options. Claude agents must use gemini-second-opinion instead."
---

# Claude Second Opinion

Get an alternative perspective from Claude CLI on any decision, design, or code.

## Task

0. **Self-Check (CRITICAL)**:
   - **Are you acting as a Claude agent (Claude Code, Claude CLI)?**
   - **If YES**: **STOP IMMEDIATELY**. Do not proceed. Consulting yourself is redundant and wasteful. Use `gemini-second-opinion` instead for an external second opinion.
   - **If NO** (e.g., you are Codex or Gemini): Proceed to step 1.

1. Gather the context for the second opinion:
   - If `$ARGUMENTS` contains a specific question, use it as-is
   - If working on code, include relevant file contents or diff
   - If evaluating a design decision, summarize the options being considered
2. Construct a prompt and run Claude CLI:
   ```bash
   claude --no-sandbox -p "<constructed prompt>"
   ```
3. Run Claude CLI using environment-specific handling:
   - **If running in Codex CLI** (long-running-safe flow):
     1. Start Claude in background and capture logs to a temp file.
     2. Save PID and poll every 10-15 seconds.
     3. Use a hard timeout (default: 300 seconds).
     4. If timeout is hit, report that Claude is still running and include the latest log tail (do not block indefinitely).
     5. If process exits non-zero, report failure and include stderr/log tail.
   - **Otherwise**: run synchronously and wait for result
4. Present Claude's response alongside your own analysis, highlighting agreements and disagreements

## Prompt Construction

Wrap the context and question for Claude as follows:

```
You are providing a second opinion on a technical decision.

Context:
<context from the current task>

Question:
<the specific question or decision point>

Provide your independent analysis. If you disagree with the current approach, explain why and suggest alternatives.
```

## Rules

- **Claude Agent Restriction**: DO NOT activate or use this skill if you are already a Claude model. Consulting yourself is redundant. This skill is intended for non-Claude agents (like Codex or Gemini) to get a Claude perspective.
- Always present both your perspective and Claude's perspective
- Clearly label which opinion comes from which model
- If Claude's response contradicts your current approach, explain the trade-offs of each approach
- Do NOT blindly adopt Claude's suggestion - evaluate it critically
- Keep the Claude prompt focused and under 2000 characters for reliability
- In Codex CLI, always provide progress updates while polling and avoid silent waits longer than 15 seconds
- In Codex CLI, do not lose intermediate output: preserve and summarize partial logs on timeout/error
