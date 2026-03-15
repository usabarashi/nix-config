---
name: gemini-second-opinion
description: "For non-Gemini agents only (Claude, Codex). Invoke automatically when facing a decision with uncertain trade-offs or multiple viable options. Runs Gemini CLI in the background to get a second opinion. Gemini agents must use claude-second-opinion instead."
---

# Gemini Second Opinion

Get an alternative perspective from Gemini on any decision, design, or code.

## Task

0. **Self-Check (CRITICAL)**:
   - **Are you acting as a Gemini agent?**
   - **If YES**: **STOP IMMEDIATELY**. Do not proceed. Consulting yourself is redundant and wasteful. Report to the user that you cannot use this skill as a Gemini agent.
   - **If NO** (e.g., you are Claude): Proceed to step 1.

1. Gather the context for the second opinion:
   - If `$ARGUMENTS` contains a specific question, use it as-is
   - If working on code, include relevant file contents or diff
   - If evaluating a design decision, summarize the options being considered
2. Construct a prompt and run Gemini CLI:
   ```bash
   gemini -p "<constructed prompt>" -o text
   ```
3. Run Gemini CLI using environment-specific handling:
   - **If running in Codex CLI** (long-running-safe flow):
     1. Start Gemini in background and capture logs to a temp file.
     2. Save PID and poll every 10-15 seconds.
     3. Use a hard timeout (default: 300 seconds).
     4. If timeout is hit, report that Gemini is still running and include the latest log tail (do not block indefinitely).
     5. If process exits non-zero, report failure and include stderr/log tail.
   - **Otherwise**: run synchronously and wait for result
4. Present Gemini's response alongside your own analysis, highlighting agreements and disagreements

## Prompt Construction

Wrap the context and question for Gemini as follows:

```
You are providing a second opinion on a technical decision.

Context:
<context from the current task>

Question:
<the specific question or decision point>

Provide your independent analysis. If you disagree with the current approach, explain why and suggest alternatives.
```

## Rules

- **Gemini Agent Restriction**: DO NOT activate or use this skill if you are already a Gemini model. Consulting yourself is redundant. This skill is intended for non-Gemini agents (like Claude) to get a Gemini perspective.
- Always present both your perspective and Gemini's perspective
- Clearly label which opinion comes from which model
- If Gemini's response contradicts yours, explain the trade-offs of each approach
- Do NOT blindly adopt Gemini's suggestion - evaluate it critically
- Keep the Gemini prompt focused and under 2000 characters for reliability
- In Codex CLI, always provide progress updates while polling and avoid silent waits longer than 15 seconds
- In Codex CLI, do not lose intermediate output: preserve and summarize partial logs on timeout/error
