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
    pkgs.customPackages.codex-bin
  ];

  home.file = {
    ".codex/AGENTS.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/codex/AGENTS.md";
      force = true;
    };
    ".codex/config.toml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/codex/config.toml";
      force = true;
    };
    ".codex/skills" = agentSkills;
  };
}
