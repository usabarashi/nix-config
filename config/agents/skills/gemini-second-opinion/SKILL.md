---
name: gemini-second-opinion
description: "Use this skill (non-Gemini agents only) to get an independent second opinion from Gemini on any decision or question where a second perspective would be valuable. Appropriate triggers: any question with meaningful trade-offs, personal choices, technical or architectural decisions, comparisons between options. Only invoke when a second perspective would meaningfully change the outcome. Runs Gemini CLI in the background."
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
2. Construct a prompt using the template in the **Prompt Construction** section below
3. Execute Gemini CLI using environment-specific handling:
   - **If `gemini` is not on PATH**: report the missing dependency to the user and skip
   - **If running in Claude Code** (recommended flow):
     1. Ensure the `Bash` tool schema is loaded before use (call `ToolSearch` with `query: "select:Bash"` if needed)
     2. Run Gemini in the background with `run_in_background: true` and `timeout: 60000`:
        ```bash
        gemini -p "<constructed prompt>" -o text 2>&1
        ```
     3. Note the returned `task_id`
     4. Ensure the `TaskOutput` tool schema is loaded (call `ToolSearch` with `query: "select:TaskOutput"` if needed)
     5. Retrieve the result with `TaskOutput` using `block: true` and `timeout: 60000`
     6. Treat the last cohesive text block in the output as Gemini's answer; ignore startup logs and error traces before it
   - **If running in Codex CLI** (long-running-safe flow):
     1. Start Gemini in background and capture logs to a temp file
     2. Save PID and poll every 10-15 seconds
     3. Use a hard timeout (default: 300 seconds)
     4. If timeout is hit, report that Gemini is still running and include the latest log tail (do not block indefinitely)
     5. If process exits non-zero, report failure and include stderr/log tail
   - **Otherwise**: run synchronously and wait for result
     ```bash
     gemini -p "<constructed prompt>" -o text
     ```
4. Present Gemini's response alongside your own analysis, highlighting agreements and disagreements

## Prompt Construction

Wrap the context and question for Gemini as follows:

```
You are providing a second opinion on a decision.

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
- Do NOT blindly adopt Gemini's suggestion — evaluate it critically
- Keep the Gemini prompt focused; very long prompts increase latency and may hit CLI limits
- In Codex CLI, always provide progress updates while polling and avoid silent waits longer than 15 seconds
- In Codex CLI, do not lose intermediate output: preserve and summarize partial logs on timeout/error
- Gemini CLI output may contain startup logs and onboarding messages before the actual response; treat the final cohesive text block as the answer
