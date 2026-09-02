# Agent sandbox profiles

Seatbelt (`sandbox-exec`) profiles for agent runtimes. Selected by the
`opencode` wrapper via `--seatbelt <name>` (default: `cloud-restricted`).

## Profiles

| Profile | Network | Filesystem | Use case |
|---------|---------|------------|----------|
| `cloud-restricted.sb` | Remote TCP 443 + loopback TCP (all ports) | Project + OpenCode state/cache read-write; OS/Nix runtime and `/nix/store` read-only; everything else denied | Default: cloud models (OpenAI Codex, etc.) |
| `strict-closed.sb` | None | Project only, plus OS/Nix runtime and devices | Sensitive repositories; no network |
| `permissive-open.sb` | Unrestricted | Unrestricted (project + home) | Legacy dev mode; **not** for remote/cloud models |

## cloud-restricted.sb

Deny-default profile:

- **Filesystem**: `TARGET_DIR` (the agent's working directory), OpenCode
  config/state/cache dirs are read-write (state/cache) or read-only (config).
  `/nix/store` and OS runtimes are read-only. Everything else (home directory,
  `~/.ssh`, `~/.codex`, …) is denied.
- **Network**: outbound remote TCP port 443 only, plus unrestricted
  loopback TCP (`localhost:*`) so local MCP servers (VoiceVox engine, Chrome
  DevTools, Slack) can reach their peers. `gh` and `curl` are executable
  (other remote-capable tools such as `ssh`/`wget`/`git-remote-https` are
  denied by execute-list). Note this does not prevent arbitrary executables
  from sending data over HTTPS.
- **Authentication**:
  - `gh` authenticates via the login Keychain (keyring), so only
    `~/.config/gh/hosts.yml` and `config.yml` metadata files are readable.
  - The Codex credential is imported (C helper, `codex-auth-keyring-import.c`)
    into the login Keychain as a generic-password item whose ACL trusts only
    the pinned Codex binary. `CODEX_HOME` points to an isolated cache dir
    keyed by Codex version.
  - Direct reads of `login.keychain-db` are permitted because
    Security.framework requires it inside a Seatbelt sandbox; the Codex item
    itself remains protected by the application-bound ACL.

### Accepted tradeoffs

- **Environment variables are visible to the model.** The wrapper preserves
  the calling environment, and with `permission.bash = "allow"` the model's
  shell commands inherit it. Secrets such as `LIBRARY_API_KEY` and
  `SLACK_USER_TOKEN` are therefore readable by the model and theoretically
  transmissible over the permitted HTTPS egress. Accepted for friction-free
  Auto mode. Do not add secrets to the environment if that is unacceptable.
- **Any localhost TCP service is reachable.** Loopback TCP is open on all
  ports so that VoiceVox, Chrome DevTools, and the local llama.cpp provider
  work, which means any password-less service listening locally can also be
  contacted by the model or MCP subprocesses. Acceptable because none of these
  local peers typically hold remote credentials; document any service that
  does before enabling it.
- **Chrome DevTools MCP.** The profile grants read access to the
  `/Applications/Google Chrome.app` bundle; `--isolated --headless` runs Chrome
  against a temporary user-data directory inside the wrapper's private temp
  dir. End-to-end browser automation (launch → page → DevTools protocol)
  should be validated once under the actual profile before relying on it.

## strict-closed.sb

No network at all. Grants the OS/Nix runtime, the project directory, and
standard devices. Intended for reviewing sensitive repositories where the
model must not contact any remote service.

## permissive-open.sb

Legacy profile with broad access. Kept for development flows that predate the
restricted profiles; prefer `cloud-restricted` unless bypassing the sandbox is
explicitly intended.
