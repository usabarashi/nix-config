{
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
      extraDir = "${homeDirectory}/.config/nix-extra";
      extraFlakePath = "${extraDir}/flake.nix";
      extraFlake = builtins.getFlake "path:${extraDir}";
      extraDarwinModules =
        if builtins.pathExists extraFlakePath && (extraFlake ? darwinModule) then
          [ extraFlake.darwinModule ]
        else
          [ ];
      hostConfig =
        {
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
      ]
      ++ extraDarwinModules
      ++ [
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            users.${userName} = homeModule;
            extraSpecialArgs = {
              inherit
                repoPath
                userName
                homeDirectory
                flakeInputs
                ;
            };
          };
        }
      ];
    };
}
