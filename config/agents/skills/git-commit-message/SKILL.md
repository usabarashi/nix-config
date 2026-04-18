---
name: git-commit-message
description: Draft a commit message from staged changes. Matches the style of recent commits in the repo, emphasizes why over what, and does not run `git commit`.
---

# Commit Message

Generate a commit message from staged changes.

## Task

1. Run `git diff --staged` and `git log --oneline -20`
2. Draft a commit message matching the style of recent commits

## Rules

- Focus on **why**, not what
- Subject line under 72 characters; add bullet-point body for multiple logical units
- If `$ARGUMENTS` is provided, use it as additional context

## Output

Do NOT run `git commit`. Write the draft to `/tmp/commit-message.md` as the canonical artifact — chat rendering can introduce trailing whitespace invisibly, so the file (not the chat output) is the source of truth. Verify cleanliness and copy to the clipboard:

```sh
grep -nE '[[:blank:]]+$' /tmp/commit-message.md && echo "FAIL: trailing whitespace" || pbcopy < /tmp/commit-message.md
```

Also show the same content in a single fenced code block for in-chat preview. Do not leave trailing whitespace on any line.
