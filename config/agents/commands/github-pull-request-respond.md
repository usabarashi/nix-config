# Pull Request Respond

Respond to review comments on the current GitHub Pull Request by fixing code and replying.

## Task

1. **Detect repo and PR number** from the current branch:
   ```sh
   gh pr view --json number,url,title,headRefName
   ```

2. **Fetch all review comments** (flat list with thread info):
   ```sh
   OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   PR_NUM=$(gh pr view --json number -q .number)
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments" --paginate
   ```
   Each comment has:
   - `id`: unique comment ID
   - `in_reply_to_id`: parent comment ID (null for root comments, non-null for replies)
   - `user.login`: author
   - `path`, `line`, `body`: location and content

3. **Identify unreplied root comments** using this jq pattern:
   ```sh
   MY_LOGIN=$(gh api user -q .login)
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments" --paginate --jq "
     [.[] | {id: .id, in_reply_to_id: .in_reply_to_id, author: .user.login}] |
     [.[] | select(.in_reply_to_id == null and .author != \"${MY_LOGIN}\") | .id] as \$roots |
     [.[] | select(.author == \"${MY_LOGIN}\" and .in_reply_to_id != null) | .in_reply_to_id] as \$replied |
     [\$roots[] | select(. as \$r | \$replied | any(. == \$r) | not)]
   "
   ```
   This returns an array of unreplied root comment IDs. If empty (`[]`), all comments are addressed.

4. **Fetch full details** of each unreplied comment:
   ```sh
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments" --paginate \
     --jq '.[] | select(.id == <ID>) | {id, path, line, body}'
   ```

5. **For each unreplied comment**:
   - Read the referenced code and understand the reviewer's concern
   - Code fix needed: fix, commit, then reply with full 40-char commit hash
   - No fix needed: reply with concrete rationale for why the current code is correct
   - One commit per fix (multiple minor fixes may share one commit)

6. **Reply via API** (do not use `gh pr review`):
   ```sh
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments/<ROOT_ID>/replies" \
     -f body="<reply text>"
   ```

7. **Summarize** all changes and replies

## Rules

- Reply only; do not approve, request changes, or submit a review
- Do not push; the user will push manually
- Reply in the same language as the reviewer's comment
- Always use `--paginate` when fetching comments (PRs may have 30+ comments)
- Use `git log -1 --format='%H'` to get the full commit hash for GitHub autolink
- Do not reply until all fixes for the current batch are committed

## Caveats

- `gh pr view --json reviewThreads` does NOT work (unsupported field)
- `gh api .../pulls/comments/<id>` returns 404 for comments from pending reviews; use the paginated list endpoint with jq filtering instead
- Follow-up replies from bots (CodeRabbit, Copilot) that acknowledge your fix do not need a response
