# see: https://github.com/nix-community/home-manager/blob/master/modules/programs/git.nix
{ config, pkgs, ... }:

let
  preCommitHook = pkgs.writeShellScript "global-pre-commit" ''
    set -eu

    ${pkgs.gitleaks}/bin/gitleaks protect --staged --redact --verbose

    # Delegate to the repository's own pre-commit hook so per-repo setups keep working.
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
    repo_hook="$git_dir/hooks/pre-commit"
    if [ -x "$repo_hook" ]; then
      exec "$repo_hook"
    fi
  '';

  git-clean = pkgs.writeShellScriptBin "git-clean" ''
    #!/bin/sh

    # Identify merged branches that can be deleted
    BRANCHES_TO_DELETE=$(git branch --merged | grep -v "^\*\|main\|master\|develop")

    # Exit with a message if there are no branches to delete
    if [ -z "$BRANCHES_TO_DELETE" ]; then
      echo "No merged branches to delete! Your repository is clean."
      exit 0
    fi

    # Display the branches that will be deleted
    echo "The following merged branches will be deleted:"
    echo "$BRANCHES_TO_DELETE"

    # Ask for confirmation
    echo -n "Do you want to delete these branches? [y/N]: "
    read ANSWER

    # Only delete if confirmed
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
      echo "$BRANCHES_TO_DELETE" | xargs git branch -d
      echo "Branch cleanup completed successfully!"
    else
      echo "Branch deletion canceled."
    fi
  '';
in
{
  home.packages = with pkgs; [
    gh
    ghq
    gitleaks
    git-clean
  ];

  xdg.configFile."git/hooks/pre-commit".source = preCommitHook;

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "usabarashi";
        email = "19676305+usabarashi@users.noreply.github.com";
      };
      core = {
        autocrlf = "input";
        hooksPath = "${config.xdg.configHome}/git/hooks";
      };
      credential.helper = "osxkeychain";
    };
    ignores = [
      "*~"
      "*.swp"
      ".DS_Store"
      ".direnv"
      ".env"
      ".envrc"
      ".claude/settings.local.json"
      ".serena"
    ];
  };
}
