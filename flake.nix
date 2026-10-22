{
  description = "Declarative user environment that eliminates manual setup by defining your entire development and daily-use software stack as code.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      # git+https (not github:) so the flake fetches via the git protocol instead
      # of GitHub's archive/codeload endpoint, which intermittently 404s on
      # SHA-addressed tarball requests. Tracks the renamed nix-darwin/nix-darwin repo.
      url = "git+https://github.com/nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    voicevox-cli = {
      url = "github:usabarashi/voicevox-cli";
    };
    serena = {
      url = "github:oraios/serena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned pre-apple-libffi nixpkgs: google-cloud-sdk's python3 is relinked
    # against this libffi in lib/overlays.nix to work around
    # https://github.com/NixOS/nixpkgs/issues/541367 (libffi trampoline dylib
    # aborts on macOS 27). Deliberately does not follow the main nixpkgs.
    nixpkgs-libffi-fix = {
      url = "github:nixos/nixpkgs/nixos-24.11";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      nix-darwin,
      home-manager,
      flake-utils,
      nixpkgs-libffi-fix,
      ...
    }:
    let
      env = import ./lib/env.nix { };
      mkFlakeInputs =
        system: builtins.mapAttrs (_name: input: input.packages.${system}.default or input) inputs;

      builders = import ./lib/builders.nix {
        inherit
          nix-darwin
          home-manager
          nixpkgs-libffi-fix
          ;
      };

      homeModules = {
        mac14-9 = import ./home/private;
        mac14-10 = import ./home/work;
      };
      hostPaths = {
        mac14-9 = ./hosts/mac14-9;
        mac14-10 = ./hosts/mac14-10;
      };

    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        darwinRebuild = "${nix-darwin.packages.${system}.darwin-rebuild}/bin/darwin-rebuild";
        mkApplyApp = name: {
          type = "app";
          program = toString (
            pkgs.writeShellScript "apply-${name}" ''
              set -euo pipefail
              echo "Applying '${name}' configuration... (sudo password may be required)"
              serial="''${SERIAL_NUMBER:-$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'"' '/IOPlatformSerialNumber/{print $4}')}"
              if [[ ! $serial =~ ^[A-Za-z0-9]+$ ]]; then
                echo "error: no valid hardware serial number (got '$serial')" >&2
                exit 1
              fi
              sudo env \
                CURRENT_USER="''${CURRENT_USER:-$(whoami)}" \
                REPOSITORY_PATH="''${REPOSITORY_PATH:-$(pwd)}" \
                SERIAL_NUMBER="$serial" \
                ${darwinRebuild} switch --flake ".#${name}" --impure "$@"
            ''
          );
        };
      in
      {
        apps = {
          mac14-9 = mkApplyApp "mac14-9";
          mac14-10 = mkApplyApp "mac14-10";
        };

        formatter = pkgs.nixfmt-tree;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nixd
            nixfmt-tree
          ];
        };
      }
    )
    // {
      darwinConfigurations = {
        mac14-9 = builders.mkDarwinSystem {
          system = "aarch64-darwin";
          userName = env.currentUser;
          inherit (env) repoPath serialNumber;
          homeModule = homeModules.mac14-9;
          hostPath = hostPaths.mac14-9;
          flakeInputs = mkFlakeInputs "aarch64-darwin";
        };
        mac14-10 = builders.mkDarwinSystem {
          system = "aarch64-darwin";
          userName = env.currentUser;
          inherit (env) repoPath serialNumber;
          homeModule = homeModules.mac14-10;
          hostPath = hostPaths.mac14-10;
          flakeInputs = mkFlakeInputs "aarch64-darwin";
        };
      };

      nixosConfigurations = { };
    };
}
