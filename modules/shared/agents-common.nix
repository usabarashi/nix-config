{
  flakeInputs,
  ...
}:

{
  # voicevox-cli provides `voicevox-mcp-server`, the MCP server referenced by
  # all four agents (Claude Code, Codex, Antigravity, opencode). It is owned
  # here rather than by any single agent module because no agent has a stronger
  # claim to it than the others.
  #
  # REQUIRED BASE MODULE: import this alongside any agents-*.nix. The per-agent
  # modules configure a voicevox MCP server (config/{claude,codex,antigravity,
  # opencode}) but do NOT carry the package; without this module they evaluate
  # fine yet fail at runtime when `voicevox-mcp-server` is missing from PATH.
  home.packages = [
    flakeInputs.voicevox-cli
  ];
}
