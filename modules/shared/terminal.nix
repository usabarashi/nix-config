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

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = {
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

      initContent = ''
        git-find() {
          local selected
          selected=$(ghq list | fzf --query "$*") || return 1
          cd "$(ghq root)/$selected"
        }

        git-find-widget() {
          BUFFER="git-find ''${(q)LBUFFER}"
          zle accept-line
        }
        zle -N git-find-widget
        bindkey '^G' git-find-widget
      '';

      syntaxHighlighting.enable = true;
    };
  };

  home.file = {
    ".config/tmux/tmux.conf" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/tmux/tmux.conf";
    };
  };
}
