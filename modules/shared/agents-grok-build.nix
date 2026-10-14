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
  agentCommands = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/commands";
    force = true;
    recursive = true;
  };
in
{
  imports = [ ./agents-common.nix ];

  home.packages = [
    pkgs.customPackages.grok-build-bin
  ];

  # Grok Build (grok) reads user-scoped state from ~/.grok (config.toml,
  # skills/, commands/, ...). Unlike agy's agent-owned settings.json, grok
  # writes back to ~/.grok/config.toml on /settings; the atomic write follows
  # the leaf symlink into this repo, so the managed file is the dotfiles-style
  # source of truth -- the same arrangement as ~/.codex/config.toml.
  home.file = {
    ".grok/config.toml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/grok/config.toml";
      force = true;
    };
    ".grok/commands" = agentCommands;
    ".grok/skills" = agentSkills;
  };
}
