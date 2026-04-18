---
name: github-pull-request-respond
description: Respond to unreplied review comments on the current GitHub Pull Request. For each comment, either commit a fix and reply with the commit hash, or reply with concrete rationale for keeping the code as-is. Does not approve, request changes, or push.
---

# Pull Request Respond

Respond to review comments on the current GitHub Pull Request by fixing code and replying.

## Task

1. **Detect repo and PR number** from the current branch:
   ```sh
   gh pr view --json number,url,title
   ```

2. **Fetch and identify unreplied comments** in a single API call:
   ```sh
   OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   PR_NUM=$(gh pr view --json number -q .number)
   MY_LOGIN=$(gh api user -q .login)
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments" --paginate --jq "
     ( [.[] | select(.in_reply_to_id == null and .user.login != \"${MY_LOGIN}\") | .id] ) as \$roots |
     ( [.[] | select(.user.login == \"${MY_LOGIN}\" and .in_reply_to_id != null) | .in_reply_to_id] ) as \$replied |
     (\$roots - \$replied) as \$unreplied_ids |
     [.[] | select(.id | IN(\$unreplied_ids[])) | {id, path, line, body}]
   "
   ```
   This returns an array of unreplied comment objects. If the array is empty (`[]`), all comments have been addressed.

3. **For each unreplied comment**:
   - Read the referenced code and understand the reviewer's concern
   - Code fix needed: fix, commit, then reply with full 40-char commit hash
   - No fix needed: reply with concrete rationale for why the current code is correct
   - One commit per fix (multiple minor fixes may share one commit)

4. **Reply via API** (do not use `gh pr review`):
   ```sh
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments/<ROOT_ID>/replies" \
     -f body="<reply text>"
   ```

5. **Summarize** all changes and replies

## Rules

- Reply only; do not approve, request changes, or submit a review
- Do not push; the user will push manually
- Reply in the same language as the reviewer's comment
- Always use `--paginate` when fetching comments (PRs may have 30+ comments)
- Use `git log -1 --format='%H'` to get the full commit hash for GitHub autolink
- Separate the commit hash and any `#NNN` issue/PR reference from surrounding text with an ASCII space or a newline on both sides. In Japanese or other non-space-delimited languages, GitHub's autolink detection will not fire if the hash is adjacent to a non-ASCII character (e.g. `修正しました。deadbeef...` stays as plain text). Safest format: put the hash on its own line.
- Do not reply until all fixes for the current batch are committed

## Caveats

- `gh pr view --json reviewThreads` does NOT work (unsupported field)
- `gh api .../pulls/comments/<id>` returns 404 for comments from pending reviews; use the paginated list endpoint with jq filtering instead
- Follow-up replies from bots (CodeRabbit, Copilot) that acknowledge your fix do not need a response
