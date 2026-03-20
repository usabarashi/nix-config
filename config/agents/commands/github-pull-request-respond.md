# Pull Request Respond

Respond to review comments on the current GitHub Pull Request by fixing code and replying.

## Task

1. Get the PR and its review comments:
   `gh pr view --json number,url,title,reviewDecision` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
2. For each unresolved comment:
   - Code fix needed: fix, commit, reply with full commit hash as GitHub autolink (e.g. "Fixed in abc1234abc1234abc1234abc1234abc1234abc1234")
   - Clarification only: reply with explanation
   - One commit per comment
3. Summarize all changes and replies

## Rules

- Reply only; do not approve, request changes, or submit a review
- Do not push; the user will push manually
- Reply in the same language as the reviewer's comment
