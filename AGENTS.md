# Nix Config

Personal Nix Flake configuration for macOS using **nix-darwin** + **home-manager**.

## Commands

| Command | Description |
|---------|-------------|
| `nix run .#private` | Build and deploy PRIVATE configuration |
| `nix run .#work` | Build and deploy WORK configuration |
| `nix fmt` | Auto-format all `*.nix` files |
| `nix fmt -- --fail-on-change` | Check formatting without modifying |
| `nix flake check --impure` | Validate flake syntax |
| `nix flake show --impure` | Show current configuration |
| `nix flake update` | Update flake dependencies |

```bash
# Deploy
nix run .#private  # or: nix run .#work

# Build test (without applying)
nix build .#darwinConfigurations.private.system --impure --dry-run
```

## Architecture

```text
flake.nix              Entry point - assembles system (private/work configs)
lib/
  env.nix              Environment variable resolution
  builders.nix         mkDarwinSystem - composes nix-darwin + home-manager
  overlays.nix         Custom package overlays
hosts/                 System-level nix-darwin config per environment
  private/             PRIVATE: system defaults, blackhole, nix-maintenance
  work/                WORK: system defaults, nix-maintenance
home/                  User-level home-manager config per environment
  private/             PRIVATE: personal packages and modules
  work/                WORK: work packages and modules
modules/
  darwin/              nix-darwin modules (blackhole, karabiner, nix-maintenance, nix-settings)
  shared/              home-manager modules (git, terminal, neovim, vscode, llm, ...)
packages/              Custom package definitions
```

### Package Sources

1. Standard nixpkgs packages
2. Custom packages (`packages/`)
3. External flake inputs (voicevox-cli, etc.)

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `CURRENT_USER` | Auto | Via `whoami` |
| `REPOSITORY_PATH` | Auto | Via `pwd` |

## Formatting

- Formatter: `nixfmt-tree` (treefmt wrapper for nixfmt-rfc-style)
- Run `nix fmt -- --fail-on-change` before commit/push
- If validation fails: run `nix fmt`, then re-validate
- Keep formatting-only changes separate from semantic changes

## Operational Notes

- Build requires `--impure` flag for environment variable access
- Weekly maintenance runs automatically via launchd (configured in `modules/darwin/nix-maintenance.nix`):
  home-manager generation cleanup (00:00) -> nix store GC (00:30) -> nix store optimise (01:00)
- If manual `nix-store --gc` fails with "Operation not permitted", run from
  Terminal.app with Full Disk Access enabled
  (System Settings > Privacy & Security > Full Disk Access)
