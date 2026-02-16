{
  config,
  pkgs,
  repoPath,
  flakeInputs,
  ...
}:

{
  home.packages =
    with pkgs;
    [
      codex
      terminal-notifier
    ]
    ++ [
      flakeInputs.voicevox-cli
      flakeInputs.serena
    ]
    ++ [
      customPackages.claude-code-sandboxed
      customPackages.gemini-cli-workforce
    ];

  home.file =
    let
      agentScripts = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/scripts";
        force = true;
        recursive = true;
      };
      agentCommands = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/commands";
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

      # Claude Code settings
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
      ".claude/commands" = agentCommands;
      ".claude/skills" = agentSkills;

      # Codex CLI settings
      ".codex/AGENTS.md" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/codex/AGENTS.md";
        force = true;
      };
      ".codex/config.toml" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/codex/config.toml";
        force = true;
      };
      ".codex/commands" = agentCommands;
      ".codex/skills" = agentSkills;

      # Gemini CLI settings
      ".gemini/GEMINI.md" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/gemini/GEMINI.md";
        force = true;
      };
      ".gemini/settings.json" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/gemini/settings.json";
        force = true;
      };
      ".gemini/policies" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/gemini/policies";
        force = true;
      };
      ".gemini/scripts" = agentScripts;
      ".gemini/commands" = agentCommands;
      ".gemini/skills" = agentSkills;

    };
}
