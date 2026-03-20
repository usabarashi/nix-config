# Pull Request Respond

Respond to review comments on the current GitHub Pull Request by fixing code and replying.

## Task

1. Get the PR and its review threads (including resolved state):
   `gh pr view --json number,url,title,reviewDecision,reviewThreads`
2. For each comment in an unresolved review thread (`isResolved == false`):
   - Code fix needed: fix, commit, reply with full commit hash (use `git log -1 --format='%H'` to get the 40-character hash for GitHub autolink)
   - No fix needed: reply with concrete rationale for why the current code is correct
   - One commit per comment
   - Do not reply until all fixes are committed
3. Summarize all changes and replies

## Rules

- Reply only; do not approve, request changes, or submit a review
- Do not push; the user will push manually
- Reply in the same language as the reviewer's comment
