{
  config,
  pkgs,
  repoPath,
  ...
}:

{
  home.packages = with pkgs; [
    tmux
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    envExtra = ''
      # Nix
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
      # End Nix

      # Add user tools to PATH
      export PATH=$HOME/bin:$PATH
    '';

    syntaxHighlighting.enable = true;
  };

  home.file = {
    ".config/tmux/tmux.conf" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/tmux/tmux.conf";
    };
  };
}
