# direnv Configuration

This directory contains global direnv configuration templates.

## Files

- `direnvrc.template` - Global direnv configuration template for extensions and common functions

## Setup

### 1. Copy Global direnv Configuration

```bash
cp config/direnv/direnvrc.template ~/.config/direnv/direnvrc
```

## Secret Retrieval Methods

Below are several methods you can use in `direnvrc` to retrieve secrets. Choose one per variable.

### Option A: 1Password CLI (`op`)

Requires [1Password CLI](https://developer.1password.com/docs/cli/) with sign-in configured.

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="$(op read 'op://Private/GitHub Personal Access Token/credential')"
```

The secret reference format is `op://<vault>/<item>/<field>`. Adjust vault, item, and field names to match your 1Password setup.

### Option B: macOS Keychain (`security`)

Uses the built-in macOS Keychain via `security find-generic-password`.

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="$(security find-generic-password -a "$(whoami)" -s 'GitHub Personal Access Token' -w)"
```

**Prerequisite:** Add the secret to your keychain first:

```bash
security add-generic-password -a "$(whoami)" -s 'GitHub Personal Access Token' -w
```

Omitting the value after `-w` prompts for interactive input, avoiding shell history exposure.

| Flag | Description |
|------|-------------|
| `-a` | Account name (user) |
| `-s` | Service name (used as lookup key) |
| `-w` | Print password only (for retrieval) / password value (for storage) |

### Option C: SOPS (`sops`)

Uses [sops](https://github.com/getsops/sops) to read a single field from an encrypted file. Requires an age key (or other supported backend) configured beforehand.

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="$(sops -d --extract '["github"]["token"]' ~/.config/sops/secrets.enc.yaml)"
```

The `--extract` argument uses bracket-based path syntax matching the YAML structure (e.g. `["github"]["token"]` for a top-level `github` key with a nested `token` field). Adjust the path and file location to match your setup.

**Prerequisite:** Generate an age key, point sops at it, then create and encrypt the secrets file:

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
export SOPS_AGE_RECIPIENTS="$(age-keygen -y ~/.config/sops/age/keys.txt)"
sops ~/.config/sops/secrets.enc.yaml  # opens $EDITOR; save as plain YAML, sops encrypts on write
```

Persist `SOPS_AGE_KEY_FILE` (and optionally `SOPS_AGE_RECIPIENTS`) in your shell init or a global `direnvrc` so the one-liner above works without per-shell setup. Back up `~/.config/sops/age/keys.txt` securely — losing it makes every encrypted file unrecoverable.

### Option D: Manual

Paste the value directly into the `.envrc` file. Least secure — avoid for shared machines.

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token-here"
```

## Usage

This template provides global direnv configuration that is loaded before every `.envrc` file. It allows you to define custom functions and extensions that will be available across all your projects.
