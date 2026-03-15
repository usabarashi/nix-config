# see: https://github.com/nix-community/home-manager/blob/master/modules/programs/ssh.nix
{ config, pkgs, ... }:

let
  extraConfigPath = "~/.ssh/extra_config";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    includes = [
      extraConfigPath
    ];

    matchBlocks = {
      "*" = {
        # Default SSH configuration
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
      };

      "github.com" = {
        identityFile = "~/.ssh/github_rsa";
        identitiesOnly = true;
        user = "usabarashi";
      };
    };

  };
}
