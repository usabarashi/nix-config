{ userName, repoPath, ... }:

{
  home-manager.users.${userName}.home.file.".config/karabiner/karabiner.json" = {
    source = builtins.path { path = "${repoPath}/config/karabiner/karabiner.json"; };
    force = true;
  };
}
