{
  config,
  pkgs,
  repoPath,
  flakeInputs,
  ...
}:

let
  # Claude-specific (unlike the config/agents/* bindings below), mirrors how
  # CLAUDE.md and settings.json are sourced from config/claude/ in this file.
  claudeAgents = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/agents";
    force = true;
    recursive = true;
  };
  agentScripts = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/scripts";
    force = true;
    recursive = true;
  };
  agentSkills = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/skills";
    force = true;
    recursive = true;
  };
  agentCommands = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/commands";
    force = true;
    recursive = true;
  };
  # Only cloud-restricted.sb is made available to the claude wrapper (it is the
  # shared default for both agents). Other profiles in config/agents (free-tier)
  # require opencode-specific wrapper env/params and must not be selectable or
  # advertised by `claude --list-seatbelts`.
  seatbeltProfileNames = [ "cloud-restricted.sb" ];
  seatbeltProfiles = builtins.listToAttrs (
    map (name: {
      name = ".claude/${name}";
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
    # Used by config/agents/scripts/notify.sh (symlinked into .claude/scripts).
    # customPackages override: nixpkgs ships Intel-only zip, this builds arm64 from source.
    pkgs.customPackages.terminal-notifier
    # MCP server launched via ~/.claude.json (not Nix-managed); only Claude
    # Code wires serena as an MCP server, so it is owned here.
    flakeInputs.serena
    pkgs.customPackages.claude-code-sandboxed
  ];

  home.file = {
    ".claude/CLAUDE.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/CLAUDE.md";
      force = true;
    };
    ".claude/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/settings.json";
      force = true;
    };
    ".claude/agents" = claudeAgents;
    ".claude/commands" = agentCommands;
    ".claude/scripts" = agentScripts;
    ".claude/skills" = agentSkills;
  }
  // seatbeltProfiles;
}
