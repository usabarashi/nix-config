{
  flakeInputs,
  ...
}:

{
  # voicevox-cli provides `voicevox-mcp-server`, the MCP server referenced by
  # all four agents (Claude Code, Codex, Antigravity, opencode). Each agents-*.nix
  # imports this module so the runtime dependency is always present whenever any
  # agent is active; buildEnv dedups the package by store path, so listing it from
  # several agents is harmless.
  home.packages = [
    flakeInputs.voicevox-cli
  ];
}
