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

Present the proposed message in a code block. Do NOT run `git commit`.
