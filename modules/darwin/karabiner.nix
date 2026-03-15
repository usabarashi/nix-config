{
  config,
  repoPath,
  ...
}:

{
  home.file.".config/karabiner/karabiner.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/karabiner/karabiner.json";
    force = true;
  };
}
