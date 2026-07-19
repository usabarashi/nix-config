{ userName, repoPath, ... }:

{
  home-manager.users.${userName} = { config, ... }: {
    home.file.".config/karabiner/karabiner.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/karabiner/karabiner.json";
      force = true;
    };
  };
}
