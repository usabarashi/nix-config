---
name: github-pull-request-respond
description: Respond to unreplied review comments on the current GitHub Pull Request. For each comment, either commit a fix, push, and reply with the commit hash, or reply with concrete rationale for keeping the code as-is. Does not approve or request changes.
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
     ( [.[] | select(.in_reply_to_id == null and .user?.login != \"${MY_LOGIN}\") | .id] ) as \$roots |
     ( [.[] | select(.user?.login == \"${MY_LOGIN}\" and .in_reply_to_id != null) | .in_reply_to_id] ) as \$replied |
     (\$roots - \$replied) as \$unreplied_ids |
     [.[] | select(.id | IN(\$unreplied_ids[])) | {id, user: (.user?.login // \"ghost\"), user_type: (.user?.type // \"\"), path, line, body}]
   "
   ```
   This returns an array of unreplied comment objects. If the array is empty (`[]`), all comments have been addressed. The `user` and `user_type` fields are required by Step 5's `@<login>` rule and bot/ghost check — keep both in the projection. The trailing `?` in `.user?.login` / `.user?.type` is jq's error-suppression operator (not JavaScript-style optional chaining); combined with the `"ghost"` / `""` defaults via `//`, it keeps the pipeline safe when GitHub returns `null` for `.user` (deleted account) — a bare `.user.login` against `null` would crash jq with `Cannot index null with "login"`. Default fallbacks: missing login → `"ghost"`, missing user type → `""`.

3. **For each unreplied comment**:
   - **Verify the reviewer's claim against actual codebase behavior.** Read the referenced code, check runtime state (symlinks, logs, etc.), and confirm the concern is valid before acting. Reviewers — including automated ones — can be incorrect. Do not assume the reviewer is right without evidence.
   - Read the referenced code and understand the reviewer's concern
   - Code fix needed: fix and commit. Capture the full 40-char hash **immediately after each commit**, labeled by the comment ID it addresses (e.g. `HASH_<commentID>=$(git log -1 --format='%H')`). Do NOT defer hash capture to after the loop — `git log -1` always points at the most recent commit, so deferring loses every earlier hash in the batch.
   - No fix needed: prepare concrete rationale for why the current code is correct, citing the evidence gathered during verification
   - One commit per fix (multiple minor fixes may share one commit; if multiple comments share a commit, label the same hash under each comment's ID)

4. **Push all commits for this batch** before replying so the hashes are reachable from GitHub:
   ```sh
   git push
   ```
   On push failure:
   - STOP immediately. Do not call any reply API with a hash that is not on the remote.
   - Do NOT run `git push --force`, `git push --force-with-lease`, `git reset --hard`, or any other history-rewriting command on your own — they can silently overwrite a teammate's work.
   - Surface the raw error to the user, then offer read-only diagnostics. Start with `git fetch && git status -sb` to confirm whether an upstream is configured (a missing upstream is a common cause when pushing a new branch for the first time, and `@{u}` errors when no upstream is set). When an upstream exists, follow up with `git log --oneline HEAD..@{u}` and the reverse to inspect divergence. The user investigates and decides how to recover; do not enumerate recovery commands on their behalf.

5. **Reply via API** (do not use `gh pr review`):
   ```sh
   gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}/comments/<ROOT_ID>/replies" \
     -f body="<reply text>"
   ```
   Address the reviewer with `@<login>` at the top of the reply so they get notified. Skip the mention when (a) `user_type == "Bot"` (mirrors the API's `.user.type` field, surfaced as `user_type` in Step 2's projection) — bots are not notified by mentions, and the `[bot]` suffix on the login is unreliable as a marker because GitHub returns the bare login `Copilot` (no suffix) for the Copilot reviewer while still setting `.user.type == "Bot"`; or (b) the login is exactly `ghost` — this is the GitHub placeholder for a deleted account, and mentioning it would notify an unrelated real user named `ghost`. Reply itself is still required for bots (including Copilot) — only the leading mention is omitted.

6. **Summarize** all changes and replies

## Rules

- Reply only; do not approve, request changes, or submit a review
- Push committed fixes before replying so the referenced commit hash is reachable from GitHub
- Reply in the same language as the reviewer's comment
- Always use `--paginate` when fetching comments (PRs may have 30+ comments)
- Use `git log -1 --format='%H'` to get the full commit hash for GitHub autolink
- Separate the commit hash and any `#NNN` issue/PR reference from surrounding text with an ASCII space or a newline on both sides. In Japanese or other non-space-delimited languages, GitHub's autolink detection will not fire if the hash is adjacent to a non-ASCII character (e.g. `修正しました。deadbeef...` stays as plain text). Safest format: put the hash on its own line.
- Do not reply until all fixes for the current batch are committed AND pushed

## Caveats

- `gh pr view --json reviewThreads` does NOT work (unsupported field)
- `gh api .../pulls/comments/<id>` returns 404 for comments from pending reviews; use the paginated list endpoint with jq filtering instead
- Follow-up replies from bots (CodeRabbit, Copilot) that acknowledge your fix do not need a response
