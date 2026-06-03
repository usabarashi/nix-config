{
  pkgs,
  flakeInputs,
  ...
}:

{
  # MCP servers referenced by all four agents (Claude Code, Codex, Antigravity,
  # opencode). Each agents-*.nix imports this module so the runtime dependencies
  # are always present whenever any agent is active; buildEnv dedups packages by
  # store path, so listing them from several agents is harmless.
  #
  # - voicevox-cli provides `voicevox-mcp-server`.
  # - chrome-devtools-mcp provides `chrome-devtools-mcp` (Node hidden in the Nix
  #   store; only this command reaches PATH). Drives the system Google Chrome.
  home.packages = [
    flakeInputs.voicevox-cli
    pkgs.customPackages.chrome-devtools-mcp
  ];
}
