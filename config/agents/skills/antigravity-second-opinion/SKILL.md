---
name: antigravity-second-opinion
description: "Non-Antigravity agents only. Get an independent second opinion from Antigravity CLI (agy). agy cannot be driven headlessly from a sandboxed agent Bash, so this skill hands the user a ready-to-run command and folds in their pasted reply."
---

# Antigravity Second Opinion

If you ARE the Antigravity CLI (agy), STOP. Tell the user this skill is for non-Antigravity agents only.

## Why this is manual (do not try to script `agy`)

Antigravity CLI (`agy`, the successor to Gemini CLI) **cannot be invoked headlessly** from an
agent's sandboxed Bash. Unlike Gemini CLI — whose `gemini -p` wrote plain text to a pipe — `agy`
fails three independent ways here:

- **No stdout without a TTY.** `agy --print` renders its response only to a terminal; with a
  socket/pipe as stdout it exits 0 and emits **0 bytes**.
- **PTY allocation is prohibited.** The sandbox denies pseudo-terminals, so `script` and `expect`
  both fail with `no more ptys`, and a `forkpty`/`openpty` shim (in any language) hits the same
  kernel block. Do not attempt a Python/Perl/`cc` PTY workaround — they cannot succeed here.
- **Keychain auth is unreachable.** `agy`'s token lives in the macOS Keychain under a
  code-signature ACL; a Bash-launched `agy` reports `You are not logged into Antigravity` even
  when the interactive app is logged in.

So the only reliable path is to have the **user** run `agy` in a real terminal and paste the reply.

## Steps

1. Build a concise second-opinion prompt from `$ARGUMENTS` if provided; otherwise infer the
   question from the current task context. Keep it focused on decision-relevant information.

2. Hand the user a copy-paste command to run in a **real terminal** (Terminal.app / iTerm), where
   `agy` is already logged in. Embed the prompt with a quoted heredoc to avoid shell-escaping
   issues:

   ```bash
   agy --print "$(cat <<'AGY_PROMPT'
   You are providing a second opinion on a decision.

   Context:
   <context from the current task>

   Question:
   <the specific question or decision point>

   Provide your independent analysis. If you disagree with the current approach, explain why and
   suggest alternatives.
   AGY_PROMPT
   )"
   ```

   Tell the user, in one line: "Run this in a normal terminal and paste `agy`'s response back."
   If `agy` has never been logged in, the one-time setup is: run `agy`, choose
   **"Use a Google Cloud project"** (this consumes the existing Workforce Identity Federation ADC;
   establish it first with `gcloud-workforce-auth` if needed), then re-run the command above.

3. When the user pastes `agy`'s reply, present both perspectives (labeled by model), highlight
   agreements and disagreements, and evaluate `agy`'s suggestion critically — do not blindly
   adopt it.

## Error Handling

- If the user cannot or does not want to run `agy`, proceed with your own analysis and say so
  explicitly — do not fabricate a second opinion.
- Never claim to have consulted `agy` unless the user actually pasted its output.
