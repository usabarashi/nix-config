{
  lib,
  nix-darwin,
  home-manager,
}:

{
  mkDarwinSystem =
    {
      system,
      userName,
      homeModule,
      hostPath,
      repoPath,
      flakeInputs,
    }:
    let
      homeDirectory = "/Users/${userName}";
      hostConfig =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          ids.gids.nixbld = 350; # Use fixed GID instead of runtime detection
          nixpkgs.overlays = import ../lib/overlays.nix;
          nixpkgs.config.allowUnfree = true;
          users.users.${userName} = {
            home = homeDirectory;
            shell = pkgs.zsh;
          };
        };
    in
    nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit userName homeDirectory;
      };
      modules = [
        hostConfig
        hostPath
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.${userName} = homeModule;
          home-manager.extraSpecialArgs = {
            inherit
              repoPath
              userName
              homeDirectory
              flakeInputs
              ;
          };
        }
      ];
    };
}
