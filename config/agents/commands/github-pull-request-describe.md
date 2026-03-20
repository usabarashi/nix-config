# Pull Request Description

Generate a PR title and description from the diff against the default branch.

## Task

1. Detect the default branch (`git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`, fallback `main`)
2. Run `git fetch origin`, then `git log --oneline origin/<default>..HEAD` and `git diff origin/<default>...HEAD`
3. Draft a PR title and description from committed changes only (ignore working tree)

## Rules

- Title: under 72 characters, imperative mood
- Include **Why** (motivation, 1-3 sentences), **What** (bullet points), **References** (issues/PRs or N/A)
- If `$ARGUMENTS` is provided, use it as additional context

## Output

Present in a single code block. Do NOT create the PR.
