# Nix Config

Declarative macOS environment using **nix-darwin** + **home-manager**.
Define your entire development and daily-use software stack as code.

## Quick Start

```bash
# Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Clone and apply
git clone https://github.com/usabarashi/nix-config.git
cd nix-config
nix run .#private  # or: nix run .#work
```

## Commands

| Command | Description |
|---------|-------------|
| `nix run .#private` | Build and apply PRIVATE configuration |
| `nix run .#work` | Build and apply WORK configuration |
| `nix fmt` | Auto-format all Nix files |
| `nix fmt -- --fail-on-change` | Check formatting without modifying |
| `nix flake check --impure` | Validate flake syntax |
| `nix flake update` | Update flake dependencies |
| `nix flake show --impure` | Show current configuration |

### Dry Run

```bash
nix build .#darwinConfigurations.private.system --impure --dry-run
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

## Local LLM (private only)

The `private` host runs Ollama as a user LaunchAgent for OpenCode backend experimentation.
After first deploy, bootstrap the model once:

```bash
ollama pull qwen3.6:35b-a3b-q4_K_M
ollama create qwen3.6-full -f config/ollama/modelfiles/qwen3.6-full.Modelfile
```

The derivative (`qwen3.6-full`) forces all 41 layers to GPU via
`PARAMETER num_gpu 41`, keeping the M2 Pro 25 GiB Metal budget full-GPU and
avoiding CPU offload on the output layer. OpenCode's model reference in
`config/opencode/opencode.json` points at this derivative tag.

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

## Build Requirements

- **Platform**: macOS (Darwin) with Apple Silicon (aarch64)
- **Build flag**: `--impure` (required for environment variable access)
- **Nix**: Flakes enabled

## References

- [Nix](https://nixos.org/) | [Manual](https://nixos.org/manual/nix/stable/) | [Installer](https://github.com/DeterminateSystems/nix-installer)
- [NixOS Search](https://search.nixos.org/packages) | [NixHub](https://www.nixhub.io/) | [Versions](https://lazamar.co.uk/nix-versions/)
- [home-manager](https://github.com/nix-community/home-manager) | [Manual](https://nix-community.github.io/home-manager/)
- [nix-darwin](https://github.com/LnL7/nix-darwin) | [Options](https://daiderd.com/nix-darwin/manual/)
