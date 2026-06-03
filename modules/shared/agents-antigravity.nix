{
  config,
  pkgs,
  repoPath,
  ...
}:

let
  agentSkills = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/skills";
    force = true;
    recursive = true;
  };
in
{
  imports = [ ./agents-common.nix ];

  home.packages = [
    pkgs.customPackages.antigravity-cli-bin
  ];

  # Antigravity CLI (agy) settings - successor to Gemini CLI, reuses ~/.gemini.
  # agy OWNS ~/.gemini/antigravity-cli/settings.json: it persists gcp.project,
  # gcp.location, and trustedWorkspaces there (established by a one-time
  # `agy` interactive login -> "Use a Google Cloud project", token cached in
  # the macOS Keychain). That file must therefore NOT be a read-only Nix
  # symlink. Nix manages only the static assets agy reads.
  home.file = {
    ".gemini/config/mcp_config.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/antigravity/mcp_config.json";
      force = true;
    };
    ".gemini/skills" = agentSkills;
  };
}
