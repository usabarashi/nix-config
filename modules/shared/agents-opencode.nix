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
  seatbeltEntries = builtins.readDir "${repoPath}/config/agents";
  seatbeltProfileNames = builtins.filter (
    name: pkgs.lib.hasSuffix ".sb" name && seatbeltEntries.${name} != "directory"
  ) (builtins.attrNames seatbeltEntries);
  seatbeltProfiles = builtins.listToAttrs (
    map (name: {
      name = ".config/opencode/${name}";
      value = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/${name}";
        force = true;
      };
    }) seatbeltProfileNames
  );
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
    ".config/opencode/skills" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/skills";
      force = true;
      recursive = true;
    };
    ".config/opencode/tools" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/opencode/tools";
      force = true;
      recursive = true;
    };
  }
  // seatbeltProfiles;
}
