# Nix Config

Declarative macOS environment using **nix-darwin** + **home-manager**.
Define your entire development and daily-use software stack as code.

## Quick Start

```bash
# Install Nix (NixOS fork; --enable-flakes is required for `nix run`)
curl --proto '=https' --tlsv1.2 -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes

# Clone and apply
git clone https://github.com/usabarashi/nix-config.git
cd nix-config
nix run .#mac14-9  # or: nix run .#mac14-10
```

## Commands

| Command | Description |
|---------|-------------|
| `nix run .#mac14-9` | Build and apply MAC14,9 configuration |
| `nix run .#mac14-10` | Build and apply MAC14,10 configuration |
| `nix fmt` | Auto-format all Nix files |
| `nix fmt -- --fail-on-change` | Check formatting without modifying |
| `nix flake check --impure` | Validate flake syntax |
| `nix flake update` | Update flake dependencies |
| `nix flake show --impure` | Show current configuration |

### Dry Run

```bash
CURRENT_USER=$(whoami) REPOSITORY_PATH=$(pwd) \
  SERIAL_NUMBER=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}') \
  nix build .#darwinConfigurations.mac14-9.system --impure --dry-run
```

### Manual GC

System store GC runs automatically via launchd (`nix.gc`).
For a full cleanup including Home Manager and user profiles:

```bash
nix shell github:nix-community/home-manager -c home-manager expire-generations now
nix-env --delete-generations old
sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations old
nix-collect-garbage -d && nix-store --gc
```

> On macOS, if GC fails with "Operation not permitted", run from the Terminal app
> with Full Disk Access enabled (System Settings > Privacy & Security > Full Disk Access).

## Extra Packages (optional)

Git-untracked, machine-specific configuration can be added via `~/.config/nix-extra/`.
Copy templates from `config/nix-extra/*.example` and customize.
Supports plain module (`default.nix`) or flake (`flake.nix`) with two optional outputs:

- `homeManagerModule`: user-level packages and settings
- `darwinModule`: system-level settings (e.g. binary cache substituters)

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `CURRENT_USER` | Auto | Detected via `whoami` |
| `REPOSITORY_PATH` | Auto | Detected via `pwd` |
| `SERIAL_NUMBER` | Auto | Detected via `ioreg`; used as the device name. `nix run` derives it (override via the env var), but evaluating a `darwinConfigurations.*` directly requires it |

## Build Requirements

- **Platform**: macOS (Darwin) with Apple Silicon (aarch64)
- **Build flag**: `--impure` (required for environment variable access)
- **Nix**: Flakes enabled

## Vulnerability triage

CI checks this flake in two workflows:

- `Flake Checker` (weekly, and on `flake.lock` changes): fails if the `nixpkgs`
  input is not on a supported branch, is older than 30 days, or is not from the
  NixOS org. `nixpkgs-libffi-fix` is pinned on purpose and is not checked.
- `Security Scan` (weekly, and on `*.nix` / `flake.lock` changes): builds each
  host, generates an SBOM with sbomnix, uploads Grype results to Code Scanning,
  and runs vulnxscan (vulnix + Grype + OSV) as an informational report
  (`vulns.csv` / `vulns.triage.csv` artifacts).

When a CVE shows up:

1. Search the CVE id on the [NixOS Security Tracker](https://tracker.security.nixos.org)
   to find the affected nixpkgs package and the fix, if one is tracked.
2. Check the fixing PR on the [nixpkgs PR tracker](https://nixpk.gs/pr-tracker.html)
   (the PR number is also in the `nix_prs` column of `vulns.triage.csv`) to see
   whether it has landed in `nixpkgs-unstable`, the branch our `nixpkgs` input tracks.
3. If it has landed, run `nix flake update nixpkgs` and rebuild. If not, wait for
   it, or record the decision (false positive, not applicable, waiting on fix)
   in a vulnxscan whitelist with a comment.

## References

- [Nix](https://nixos.org/) | [Manual](https://nixos.org/manual/nix/stable/) | [Installer](https://github.com/NixOS/nix-installer)
- [NixOS Search](https://search.nixos.org/packages) | [NixHub](https://www.nixhub.io/) | [Versions](https://lazamar.co.uk/nix-versions/)
- [home-manager](https://github.com/nix-community/home-manager) | [Manual](https://nix-community.github.io/home-manager/)
- [nix-darwin](https://github.com/LnL7/nix-darwin) | [Options](https://daiderd.com/nix-darwin/manual/)
