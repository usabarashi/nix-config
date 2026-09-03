# Agent sandbox profiles

Seatbelt (`sandbox-exec`) profiles for agent runtimes. Selected by the
`opencode` and `claude` wrappers via `--seatbelt <name>` (both default to
`cloud-restricted`).

## Profiles

| Profile | Network | Filesystem | Use case |
|---------|---------|------------|----------|
| `cloud-restricted.sb` | Remote TCP 443 + loopback TCP (all ports) | Project + OpenCode/Claude state/cache read-write; OS/Nix runtime and `/nix/store` read-only; everything else denied | Default for opencode and claude (paid cloud models: OpenAI Codex, Claude, normal opencode models) |
| `free-tier.sb` | Remote TCP 443 + loopback TCP (all ports) | Project + dedicated free-tier data/state/cache read-write; immutable free-tier `auth.json` (read-only); NO Keychain, `~/.config/gh`, `~/.gitconfig`, paid auth | opencode free-tier cloud providers (Gemini/Groq/OpenRouter no-cost) |

`strict-closed.sb` and the unrestricted `permissive-open.sb` have both been
removed; there is no network-zero or fully-open profile. For sensitive work use
the deny-default profiles or run without a remote model.

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
  - `gh` uses a **dedicated, read-only GitHub agent PAT** provisioned from
    1Password by the wrapper *outside* the sandbox and staged in the ephemeral
    per-invocation temp dir (`GH_CONFIG_DIR` points at that disposable
    `hosts.yml`). Inherited GitHub token environment variables
    (`GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`,
    `GITHUB_ENTERPRISE_TOKEN`) are scrubbed before launch, and personal git
    configuration (`~/.config/gh`, `~/.gitconfig`, `~/.config/git`) is not
    granted by the profile. On normal exit the temp dir is removed (by the
    wrapper's EXIT trap; for claude, by a tiny C supervisor); a SIGKILLed
    wrapper may leave it behind until the OS cleans the system temp area —
    timing is not guaranteed.
  - **Fail-closed**: if the PAT cannot be provisioned (item missing, `op` not
    signed in, malformed token), the cloud session refuses to start. Set
    `AGENT_GH_ALLOW_UNAUTHENTICATED=1` to continue without GitHub instead.
  - The 1Password CLI (`op` / `op-please` / `op-http-call`) and
    `/usr/bin/security` are **denied on the exec list**, and `op` is absent
    from the sandbox PATH, so the model cannot reach the user's vault session
    or list Keychain items directly. Provisioning happens in the wrapper,
    before `sandbox-exec`, and requires the host `op` CLI to be signed in (the
    same setup the direnv README assumes).
  - **Residual risk (prompt-injection / compromised model):** Keychain and
    `securityd` access remain granted so the pinned Codex binary can retrieve
    its own credential, and Seatbelt applies to the whole process tree — not
    per binary. A compromised model that constructs an alternate `gh` config
    (in a writable location) naming the *personal* account could therefore
    still recover the personal GitHub Keychain item through the permitted
    `gh` binary. The dedicated PAT bounds the *default* and *accidental*
    paths; this deliberate-override path is defense-in-depth only, and the
    same limitation motivated the future option of removing Keychain access
    from this profile altogether (see "Accepted tradeoffs").
  - The Codex credential is imported (C helper, `codex-auth-keyring-import.c`)
    into the login Keychain as a generic-password item whose ACL trusts only
    the pinned Codex binary. `CODEX_HOME` points to an isolated cache dir
    keyed by Codex version.
  - Direct reads of `login.keychain-db` are permitted because
    Security.framework requires it inside a Seatbelt sandbox; the Codex item
    itself remains protected by the application-bound ACL.

### Provisioning the GitHub agent PAT

The default `gh` flow expects a **fine-grained PAT** stored in 1Password at
`op://Private/GitHub Agent PAT/credential` (reference and GitHub user label are
overridable via `AGENT_GH_OP_REF` / `AGENT_GH_USER`).

#### Recommended permission settings

Create the PAT as a **fine-grained PAT** with these settings:

**Repository access**

- **Only select repositories**: the repositories the agent may read (private
  repositories included). Do not grant "All repositories" unless every
  repository is meant to be readable by the agent.

**Repository permissions** — every permission is **Read** at most, never
`Write` / `Maintain` / `Admin`:

| Permission     | Setting (recommended) | Notes                                                        |
|----------------|-----------------------|--------------------------------------------------------------|
| Metadata       | **Read**              | Required for every fine-grained PAT                          |
| Contents       | **Read**              | Repository contents / branches / tags (needed for diffing)   |
| Pull requests  | **Read**              | PR metadata and review comments used by the PR skills        |
| Issues         | **Read**              | Issue cross-references in PR descriptions                    |
| Actions        | **Read**              | Action run status / logs, incl. check-run details (optional) |
| Commit statuses| **Read**              | Commit status of PRs / commits (optional)                   |
| All others     | **No access**         | e.g. Administration, Secrets, Workflows, Webhooks, Environments, Deployments |

**Account permissions**

- All entries **No access** (no SSH signing keys, deploy keys, profile/settings
  writes, organization management, …).

**Notes**

- Fine-grained PATs do **not** have a `Checks` permission (that is a classic-PAT
  scope, `checks:read`). For CI status read either `Actions: Read` (check runs
  for Actions) or `Commit statuses: Read`; neither is required for the core
  read-only flow.
- Set an **expiration** (e.g. 90 days) and rotate periodically. Rotation is a
  single 1Password item update — the wrapper re-reads it on the next launch,
  no Nix rebuild or profile change required.

The host `op` CLI must be signed in before launching opencode; provisioning is
**fail-closed** — if the read fails or the item value is not a well-formed
GitHub token, the session exits with an error unless
`AGENT_GH_ALLOW_UNAUTHENTICATED=1` is set, in which case `gh` runs
unauthenticated with a warning on stderr. Side-effect-free invocations
(`--version`, `--help`) skip provisioning entirely, so they work without a
1Password session.

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

## Claude Code (unified profile)

`claude-code.sb` has been removed; the `claude` wrapper now defaults to
`cloud-restricted.sb`, the same profile opencode uses. The wrapper maps Claude's
paths onto the profile parameters so behavior is preserved:

- `~/.claude` → `AGENT_CONFIG_DIR` (read) and `AGENT_STATE_DIR` /
  `AGENT_AUX_STATE_DIR` (write): settings, skills, commands, agents, scripts
  and the installed seatbelt copies stay read/write.
- `~/.cache/claude` → `AGENT_CACHE_DIR` (read/write).
- `~/.claude.json` → `AGENT_CLAUDE_JSON` (read/write; Claude's global state /
  MCP wiring such as Serena). The opencode wrapper passes an inert path inside
  its own state dir, so this grant does not widen opencode sessions.
- Scratch/temp is redirected to the wrapper's private per-invocation temp dir
  (`AGENT_TMP_DIR`, removed on exit).

Authentication and credentials are the same as opencode: the dedicated,
read-only GitHub agent PAT is provisioned from 1Password into the ephemeral
`GH_CONFIG_DIR` (fail-closed, same env overrides), and inherited GitHub token
environment variables are scrubbed. The 1Password CLI and `/usr/bin/security`
are exec-denied here as well.

## free-tier.sb

Dedicated profile for opencode sessions against **free-tier cloud providers**
(Gemini free tier, Groq no-cost, OpenRouter no-cost models), which are treated
as **low-trust**: they may retain or train on data. The design goal is to hand
such models **no secrets and no identity beyond what the session itself needs**.

### Design

Deny-default, modeled on `cloud-restricted.sb` with the following differences:

- **No Keychain**. `login.keychain-db`, `securityd`, `SecurityServer`,
  `systemkeychaincheck`, Keychain preference/shared-memory allowances are
  absent. Security.framework *code* stays readable (it is not a credential
  store); `trustd` and SystemConfiguration services are kept for HTTPS.
- **No `~/.config/gh/*`, no `~/.gitconfig`.** The wrapper injects a **synthetic
  git identity** (`opencode-free <opencode-free@localhost>`) instead.
- **No paid auth.** `XDG_DATA_HOME`/`STATE_HOME`/`CACHE_HOME`/`CONFIG_HOME`
  are redirected to a **dedicated free-tier root**
  (`~/.local/share/opencode-free/...`) whose `auth.json` is provisioned
  outside the sandbox with **only free-tier static API keys** and is
  **immutable during the session** (the profile denies writes to it).
- **Exec deny + PATH exclusion**: `ssh`, `scp`, `sftp`, `gh`, `curl`, `wget`,
  `nc`, `ncat`, `netcat`, `ftp`, `rsync`, `git-remote-*`, `codex` are denied
  by the Seatbelt exec list **and** excluded from the wrapper-built PATH.
- **Environment scrubbing**: the wrapper rebuilds the environment with
  `env -i` from an explicit allowlist (PATH, HOME, TERM, USER, LOGNAME, SHELL,
  TMPDIR/TMP/TEMP, SSL_CERT_FILE, XDG_*, synthetic GIT_*, and wrapper-owned
  OPENCODE_*). `SLACK_USER_TOKEN`, `LIBRARY_API_KEY`, `SSH_AUTH_SOCK`, and any
  caller-supplied `OPENCODE_CONFIG_CONTENT` / `OPENCODE_PERMISSION` are dropped.
- **Independent config**: `free-tier.json` (deployed as immutable Nix-store
  content) enables only allowed providers, disables paid built-ins
  (`opencode-go`, `anthropic`, `openai`, `llamacpp-local`), whitelists exact
  model IDs, and keeps only the `chrome-devtools` MCP.
- **Mandatory allowlisted `-m`**: the wrapper requires an explicit
  `-m <provider>/<model>` and validates it against the versioned
  `free-tier-models.json` allowlist. Duplicate, malformed, or non-allowlisted
  selectors fail closed before sandbox-exec. The allowlist also carries the
  resolved upstream `api_id` / `sdk` / `base_url` tuple for each allowed model:
  it documents the expected outbound binding, and the smoke suite asserts that
  the actual request uses that tuple. This is a guardrail on the initial
  selector, not a network-level block on later in-session model changes;
  `enabled_providers`/`disabled_providers` in the minimal config constrain the
  provider catalog accordingly.
- **Wrapper option contract**: `--seatbelt`, `--seatbelt=`, `--list-seatbelts`,
  and `--no-sandbox` are wrapper options and are recognized **only in the
  leading option region** (before `--` or the first non-option argument).
  Anything after that boundary is forwarded to opencode inside the Seatbelt.
  `--no-sandbox` in the wrapper region is rejected for `free-tier.sb`
  regardless of order; downstream occurrences cannot disable the sandbox.
  Ordinary opencode options before `--seatbelt` (e.g. `--print-logs`) stop
  wrapper parsing, so always place `--seatbelt` first.
- **Managed config fail-closed**: if `/Library/Application Support/opencode`
  or macOS managed preferences (`ai.opencode.managed.plist`) contain OpenCode
  configuration, the wrapper refuses to launch unless independently verified.
- **TARGET_DIR guard**: refuses to run from `$HOME` or any protected root
  (`~/.config`, `~/.local`, `~/.ssh`, `~/.codex`, `~/.claude`, the dedicated
  free-tier root).

### NOT a billing or exfiltration boundary

`free-tier.sb` is **not** a network firewall and cannot prevent data
exfiltration or paid usage by itself:

- Outbound remote TCP 443 is unrestricted at the Seatbelt level (Seatbelt
  cannot filter by domain), so any executable the model can run **or the model
  itself** can send readable data to any HTTPS destination.
- The exec deny list is **defense in depth only** (renamed copies,
  interpreters, and Chrome can all open HTTPS).
- A provider key placed in the environment would be visible to child
  processes; provider keys live in the immutable `auth.json` instead, but a
  low-trust model with a stolen key could still reach paid endpoints.

The real gates are **server-side spending controls** (R30): for each free-tier
provider account, verify one of (a) billing disabled + hard zero-spend limit,
(b) a server-side key restricted to the exact free models, or (c) a trusted
proxy that enforces provider/model. The `free-tier` profile is **not enabled
on any host** until this is verified and the smoke suite passes.

### Session contract

- Free-tier credentials are provisioned **outside the sandbox** and are
  **immutable during the session** (static API keys; refresh is memory-only,
  or fails closed with re-provisioning on expiry).
- The dedicated credential root is persistent and created securely (0700, no
  symlinks, owner/link-count verified); per-session temporary data lives in
  the private per-invocation temp dir and is removed on exit.