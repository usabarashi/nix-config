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
    # git-agent-guard: a plain-script git deny shim (config/agents/scripts/),
    # deployed as a COPY because this dir is what the cloud-restricted seatbelt
    # grants read on; a symlink into the repo would be unreadable when opencode
    # runs in a project outside this checkout. Content lives in the script file.
    ".config/opencode/bin/git" = {
      text = builtins.readFile "${repoPath}/config/agents/scripts/git-agent-guard.sh";
      executable = true;
    };
    # nix-agent-guard: same deployment rationale as the git shim. PATH-first
    # `nix` shim that constrains the workspace flake and options (see the
    # script header and config/agents/README.md).
    ".config/opencode/bin/nix" = {
      text = builtins.readFile "${repoPath}/config/agents/scripts/nix-agent-guard.sh";
      executable = true;
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
