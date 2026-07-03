{
  config,
  pkgs,
  repoPath,
  ...
}:

let
  agentCommands = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/commands";
    force = true;
    recursive = true;
  };
in
{
  imports = [ ./agents-common.nix ];

  home.packages = [
    pkgs.customPackages.opencode-sandboxed
  ];

  # opencode settings (XDG-style location)
  home.file = {
    ".config/opencode/opencode.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/opencode/opencode.json";
      force = true;
    };
    ".config/opencode/commands" = agentCommands;
    ".config/opencode/permissive-open.sb" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/permissive-open.sb";
      force = true;
    };
  };
}
