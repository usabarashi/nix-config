# see: https://github.com/nix-community/home-manager/blob/master/modules/programs/ssh.nix
{
  config,
  pkgs,
  ...
}:

let
  extraConfigPath = "~/.ssh/extra_config";
  secretiveSocket = "${config.home.homeDirectory}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";

  # Path only; the file contents are populated manually because the key is
  # random data tied to a specific Secure Enclave and not reproducible by Nix.
  githubAuthKeyPath = "${config.home.homeDirectory}/.ssh/github.pub";
in
{
  home.packages = [ pkgs.secretive ];

  home.sessionVariables = {
    SSH_AUTH_SOCK = secretiveSocket;
  };

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
        extraOptions = {
          IdentityAgent = secretiveSocket;
        };
      };

      "github.com" = {
        identityFile = githubAuthKeyPath;
        identitiesOnly = true;
        user = "git";
      };
    };
  };
}
