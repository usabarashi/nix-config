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
      terminal-notifier
    ]
    ++ [
      flakeInputs.voicevox-cli
      flakeInputs.serena
    ]
    ++ [
      customPackages.antigravity-cli-bin
      customPackages.claude-code-sandboxed
      customPackages.codex-bin
      customPackages.opencode-sandboxed
    ];

  home.file =
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
      ".codex/skills" = agentSkills;

      # Antigravity CLI (agy) settings - successor to Gemini CLI, reuses ~/.gemini.
      # agy OWNS ~/.gemini/antigravity-cli/settings.json: it persists gcp.project,
      # gcp.location, and trustedWorkspaces there (established by a one-time
      # `agy` interactive login -> "Use a Google Cloud project", token cached in
      # the macOS Keychain). That file must therefore NOT be a read-only Nix
      # symlink. Nix manages only the static assets agy reads.
      ".gemini/config/mcp_config.json" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/antigravity/mcp_config.json";
        force = true;
      };
      ".gemini/skills" = agentSkills;

      # opencode settings (XDG-style location)
      ".config/opencode/opencode.json" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/opencode/opencode.json";
        force = true;
      };
      ".config/opencode/permissive-open.sb" = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/permissive-open.sb";
        force = true;
      };
    };
}
