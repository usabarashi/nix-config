{
  config,
  pkgs,
  repoPath,
  ...
}:

{
  imports = [ ./agents-common.nix ];

  home.packages = [
    pkgs.customPackages.opencode-sandboxed
  ];

  # opencode settings (XDG-style location)
  home.file = {
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
