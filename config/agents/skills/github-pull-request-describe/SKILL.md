---
name: github-pull-request-describe
description: Generate a PR title and description from the committed diff against the default branch. Use when the user asks to draft, write, or prepare a pull request description/body. Does not create the PR.
---

# Pull Request Description

Generate a PR title and description from the diff against the default branch.

## Task

1. Detect the default branch (`git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`, fallback `main`)
2. Run `git fetch origin`, then `git log --oneline origin/<default>..HEAD` and `git diff origin/<default>...HEAD`
3. Draft a PR title and description from committed changes only (ignore working tree)

## Rules

- Title: under 72 characters, imperative mood
- **Why**: the problem / motivation / existing constraints that made this work necessary (1-3 sentences). Describes the situation *before* the fix, not the fix itself.
- **What**: the design decision taken and its reasoning — alternatives considered, chosen approach, rejected options and why (aim for 2-6 sentences of prose, or 2-5 bullets). Do NOT restate facts visible from the diff (changed file names, added function names, line counts, API signatures). Reviewers will read the diff for implementation detail; they need the design thinking from you.
- **References**: linked issues/PRs as bullets (`- #123`), or the single line `N/A` when there are none.
- If `$ARGUMENTS` is provided, use it as additional context.

Boundary rule for Why vs What: "why is this work needed" belongs in Why; "what was decided, among which alternatives, and why that choice" belongs in What.

## Output

Do NOT create the PR. Write the draft to `/tmp/pr-description.md` as the canonical artifact — chat rendering can introduce trailing whitespace invisibly, so the file (not the chat output) is the source of truth. Verify cleanliness and copy to the clipboard:

```sh
grep -nP '[ \t]+$' /tmp/pr-description.md && echo "FAIL: trailing whitespace" || pbcopy < /tmp/pr-description.md
```

Also show the same content in a single fenced code block for in-chat preview (any fence style — triple backticks or tildes — works; the template below uses `~~~`). Do not leave trailing whitespace on any line.

~~~
<title>

## Why
<motivation — 1-3 sentences>

## What
<design approach and reasoning — prose or bullets, not a diff summary>

## References
- <issue/PR>
~~~
