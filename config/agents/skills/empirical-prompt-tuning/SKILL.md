---
name: empirical-prompt-tuning
description: A method for iteratively improving agent-facing text instructions (skill / slash command / task prompt / CLAUDE.md section / code-generation prompt) by having an unbiased executor run them, then evaluating from both sides (executor self-report + instruction-side metrics). Loop until improvement plateaus. Use right after creating or significantly revising a prompt or skill, or when you suspect that an agent's failure to behave as expected stems from ambiguity on the instruction side.
---

# Empirical Prompt Tuning

The author of a prompt cannot judge its quality. The clearer it feels to the writer, the more often another agent stumbles over it. **Have an unbiased executor actually run it, evaluate from both sides, and iterate** — that is the core of this skill. Do not stop until improvement plateaus.

## When to use

- Right after creating or significantly revising a skill / slash command / task prompt
- When an agent does not behave as expected and you want to attribute the cause to instruction-side ambiguity
- When hardening high-importance instructions (frequently used skills, prompts at the core of automation)

When not to use:
- One-off, throwaway prompts (the evaluation cost is not worth it)
- When the goal is not improving success rate but reflecting the writer's subjective preference

## Workflow

0. **Iteration 0 — alignment check between description and body** (static, no dispatch)
   - Read the trigger / use cases the frontmatter `description` claims
   - Read the scope the body actually covers
   - If they diverge, fix description or body to match before proceeding to iter 1
   - Example: detect cases like `description` saying "navigation / form filling / data extraction" while the body only contains a `npx playwright test` CLI reference
   - If you skip this, the subagent will "reinterpret" the body to match the description, and accuracy comes out fine even though the skill does not actually meet the requirements (false positive)

1. **Baseline preparation**: fix the target prompt and prepare the following two:
   - **Evaluation scenarios**, 2 to 3 (1 median + 1 to 2 edge). Tasks that could realistically occur, simulating situations where the target prompt is actually applied.
   - **Requirements checklist** (for accuracy calculation). For each scenario, list 3 to 7 items the deliverable must satisfy. Accuracy % = items satisfied / total items. Fix this in advance (do not move it later).
2. **Bias-free read**: have a "blank" executor read the instructions. **Dispatch a fresh subagent** via the Agent tool. Do not settle for self-rereading (it is structurally impossible to view text you just wrote objectively). When running multiple scenarios in parallel, place multiple Agent tool calls in a single message. For environments where dispatch is unavailable, see the "Environment constraints" section.
3. **Execution**: hand the subagent a prompt that follows the **subagent invocation contract** below and have it run the scenario. The executor produces an implementation or output, then returns a self-report at the end.
4. **Two-sided evaluation**: from the returned result, record the following.
   - **Executor self-report** (extracted from the body of the subagent's report): ambiguities / discretionary completions / spots where template application got stuck
   - **Instruction-side metrics** (judgement rules are defined in this section as the single source of truth; other places reference back here):
     - Success/failure: success (○) only when **all** items tagged `[critical]` are ○. If even one is × or partial, it is failure (×). Labels are binary, ○ / × only.
     - Accuracy (achievement rate of the requirements checklist, as %. ○ = full mark, × = 0, partial = 0.5; sum and divide by total items)
     - Step count (use the `tool_uses` value in the usage metadata returned by the Agent tool as is. Include Read / Grep — do not exclude them.)
     - Duration (`duration_ms` from the Agent tool usage metadata)
     - Retry count (how many times the subagent redid the same judgement. Extracted from the subagent's self-report; not measurable on the instruction side.)
     - **On failure, add a one-liner under "ambiguities" in the presentation format saying which `[critical]` item dropped** (for cause tracking)
   - The requirements checklist must contain **at least one** `[critical]`-tagged item (with zero, the success judgement becomes vacuous). Do not add or remove `[critical]` after the fact.
5. **Apply diff**: introduce the minimal edit that closes the ambiguities into the prompt. One theme per iteration (multiple related edits are fine; unrelated edits go to the next iteration).
6. **Re-evaluate**: dispatch a new subagent and run 2 → 5 again (do not reuse the same agent: it has learned from the previous improvement). Increase parallelism only if iterations stop producing improvement.
7. **Convergence check**: rough rule — stop when "two consecutive iterations show zero new ambiguities AND metric improvement below the threshold (see below)". For high-importance prompts, require three consecutive.

## Evaluation axes

| Axis | How to take it | Meaning |
|---|---|---|
| Success/failure | Whether the executor produced the intended deliverable (binary) | Minimum bar |
| Accuracy | What % of the requirements the deliverable met | Degree of partial success |
| Step count | Number of tool calls / decision steps the executor used | Indicator of instruction waste |
| Duration | Executor's `duration_ms` | Proxy for cognitive load |
| Retry count | How many times the same judgement was redone | Signal of instruction ambiguity |
| Ambiguities (self-reported) | Listed by the executor as bullet points | Qualitative material for improvement |
| Discretionary completions (self-reported) | Decisions not specified in the instructions | Surfacing of implicit specs |

**Weighting**: qualitative (ambiguities, discretionary completions) is primary; quantitative (duration, step count) is secondary. Chasing only time reduction makes the prompt overly thin.

### Qualitative interpretation of `tool_uses`

Looking only at accuracy hides skill-level problems. Using `tool_uses` as a **relative value across scenarios** reveals structural defects:

- If one scenario is **3-5x or more** of the others, that skill leans toward a **decision-tree index with low self-containedness**. The executor is being forced into references descent.
- Typical example: all scenarios show `tool_uses` of 1-3, but one scenario shows 15+ → the skill lacks an inline recipe for that scenario, and the executor is sweeping across `references/`.
- Remedy: in iter 2, add a "minimal complete example inline" or "guidance on when to read references" near the top of SKILL.md, and `tool_uses` drops sharply.

Even at 100% accuracy, a `tool_uses` skew is grounds to trigger iter 2. "Judging only by accuracy and stopping" tends to miss structural defects.

## Subagent invocation contract

The prompt handed to the executor takes the following structure. This is the input contract for "two-sided evaluation".

```
You are an executor reading <target prompt name> with a blank slate.

## Mode
empirical  # change to "structural" for textual consistency check only (see "Environment constraints: Structural review mode")

## Target prompt
<paste the full body of the target prompt, or specify the path to Read>

## Scenario
<one paragraph describing the scenario's situation>

## Requirements checklist (items the deliverable must satisfy)
1. [critical] <item that belongs to the minimum bar>
2. <regular item>
3. <regular item>
...

## Task
1. Follow the target prompt to execute the scenario and produce the deliverable.
2. On finish, reply using the report structure below.

## Report structure
- Deliverable: <output or summary of execution result>
- Requirement satisfaction: ○ / × / partial (with reason) for each item
- Ambiguities: spots in the target prompt where you got stuck or wording you struggled to interpret (bullets)
- Discretionary completions: spots not specified in the instructions where you filled in based on your own judgement (bullets)
- Retries: how many times you redid the same judgement, and why
```

> Judgement rules are defined as the single source of truth in "Workflow 4. Two-sided evaluation / Instruction-side metrics". At least one [critical] is required.

The caller extracts the self-report portion from the report and pulls `tool_uses` / `duration_ms` from the Agent tool's usage metadata to fill in the evaluation axes table.

## Environment constraints

In environments where dispatching a fresh subagent is not possible (already running as a subagent, the Agent tool is disabled, etc.), this skill **does not apply**.
- Alternative 1: ask the user of the parent session to launch a separate Claude Code session and run it
- Alternative 2: skip the evaluation and explicitly report to the user "empirical evaluation skipped: dispatch unavailable"
- **NG**: substituting self-rereading (bias creeps in, so the evaluation result cannot be trusted)

**Structural review mode**: when you only want to check **textual consistency and clarity** of a skill / prompt rather than empirical evaluation, switch into structural review mode explicitly. State "this round is structural review mode: textual consistency check, not execution" in the request prompt to the subagent. This way the subagent does not fall into the skip behaviour from the environment-constraints section and can return a static review. Structural review supplements, not substitutes, empirical evaluation (it cannot count toward consecutive-clear judgement).

## Stopping criteria

- **Convergence (stop)**: two consecutive rounds satisfying **all** of:
  - New ambiguities: 0
  - Accuracy improvement vs. previous: +3 percentage points or less (saturation, like 5% → 8%)
  - Step-count change vs. previous: within ±10% (or ±1 step, whichever is larger)
  - Duration change vs. previous: within ±15%
  - **Overfitting check**: at convergence, add one previously-unused hold-out scenario and evaluate. If accuracy drops 15 percentage points or more from the recent average, that is overfitting. Go back to baseline scenario design and add edge cases.
- **Divergence (suspect the design)**: if 3+ iterations fail to reduce new ambiguities → the prompt's design direction itself may be wrong. Stop patching and rewrite the structure.
- **Resource cutoff**: when importance and improvement cost no longer balance, stop (the call to ship at 80%).

## Presentation format

Record and present each iteration to the user in this form:

```
## Iteration N

### Changes (diff vs. previous)
- <one-line description of the edit>

### Results (per scenario)
| Scenario | Success/Failure | Accuracy | steps | duration | retries |
|---|---|---|---|---|---|
| A | ○ | 90% | 4 | 20s | 0 |
| B | × | 60% | 9 | 41s | 2 |

### Ambiguities (newly observed this round)
- <Scenario B>: [critical] item N was × — <one-line reason for the drop>   # always include on failure
- <Scenario B>: <other observation, one line>
- <Scenario A>: (none new)

### Discretionary completions (newly observed this round)
- <Scenario B>: <what was filled in>

### Next edit
- <minimal edit, one line>

(Convergence: X consecutive clears / Y rounds remaining to stop)
```

## Red flags (watch for rationalization)

| The rationalization that surfaces | The reality |
|---|---|
| "Rereading it myself produces the same effect" | You cannot "objectively view" text you just wrote. Always dispatch a fresh subagent. |
| "One scenario is enough" | One scenario overfits. Two minimum, three preferred. |
| "Zero ambiguities once is the end" | It can be coincidence. Confirm with two consecutive rounds. |
| "Let's crush multiple ambiguities at once" | You lose track of what worked. One theme per iteration. |
| "Let's split related minor edits one-per-iteration too" | The opposite trap. "One theme" is a semantic unit. 2-3 related minor edits in a single iter is fine. Splitting too far makes iter count explode. |
| "Metrics look good, ignore the qualitative feedback" | Time reduction can also signal thinning. Qualitative is primary. |
| "It is faster to rewrite from scratch" | If 3+ rounds fail to reduce ambiguities, that is the right call. Before that point it is escapism. |
| "Let's reuse the same subagent" | It has learned the previous improvement. Dispatch fresh every time. |

## Common failures

- **Scenario too easy / too hard**: neither produces signal. One median plus one edge from real usage situations.
- **Looking only at metrics**: chasing only time reduction strips out important explanation and makes the prompt brittle.
- **Too many changes per iteration**: you lose track of "which of those edits worked". One edit, one iteration.
- **Tuning scenarios to match the edits**: making scenarios easier so ambiguities appear to be resolved → backwards.

## Related

- `superpowers:writing-skills` — TDD approach for skill creation. Essentially the same as this skill's "subagent baseline → edit → re-run" loop.
- `retrospective-codify` — codifying lessons after a task. Use this skill during prompt development; use `retrospective-codify` after a task ends.
- `superpowers:dispatching-parallel-agents` — etiquette for running multiple scenarios in parallel.
