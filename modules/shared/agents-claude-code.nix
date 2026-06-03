{
  config,
  pkgs,
  repoPath,
  flakeInputs,
  ...
}:

let
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
in
{
  home.packages =
    with pkgs;
    [
      # Used by config/agents/scripts/notify.sh (symlinked into .claude/scripts).
      terminal-notifier
    ]
    ++ [
      # MCP server launched via ~/.claude.json (not Nix-managed); only Claude
      # Code wires serena as an MCP server, so it is owned here.
      flakeInputs.serena
    ]
    ++ [
      customPackages.claude-code-sandboxed
    ];

  home.file = {
    ".claude/permissive-open.sb" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/permissive-open.sb";
      force = true;
    };
    ".claude/CLAUDE.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/CLAUDE.md";
      force = true;
    };
    ".claude/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/settings.json";
      force = true;
    };
    ".claude/scripts" = agentScripts;
    ".claude/skills" = agentSkills;
  };
}
