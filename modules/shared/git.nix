# see: https://github.com/nix-community/home-manager/blob/master/modules/programs/git.nix
{
  config,
  pkgs,
  ...
}:

let
  userName = "usabarashi";
  userEmail = "19676305+usabarashi@users.noreply.github.com";

  # Paths only; the file contents are populated manually because the keys are
  # random data tied to a specific Secure Enclave and not reproducible by Nix.
  signingKeyPath = "${config.xdg.configHome}/git/signing-key.pub";
  allowedSignersPath = "${config.xdg.configHome}/git/allowed_signers";

  preCommitHook = pkgs.writeShellScript "global-pre-commit" ''
    set -eu

    # Run the repository's own pre-commit hook first if present. We must use
    # --git-common-dir (not --git-path hooks/pre-commit) because the latter
    # honors core.hooksPath and would resolve to this script itself, causing
    # infinite recursion / fork bomb.
    git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
    if [ -n "$git_common_dir" ] && [ -x "$git_common_dir/hooks/pre-commit" ]; then
      "$git_common_dir/hooks/pre-commit" "$@"
    fi

    exec ${pkgs.gitleaks}/bin/gitleaks protect --staged --redact --verbose
  '';
in
{
  home.packages = with pkgs; [
    gh
    ghq
    gitleaks
    customPackages.git-tools-bin
  ];

  xdg.configFile."git/hooks/pre-commit".source = preCommitHook;

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = userName;
        email = userEmail;
        signingKey = signingKeyPath;
      };
      core = {
        autocrlf = "input";
        hooksPath = "${config.xdg.configHome}/git/hooks";
      };
      credential.helper = "osxkeychain";

      commit.gpgSign = true;
      tag.gpgSign = true;

      gpg = {
        format = "ssh";
        ssh.allowedSignersFile = allowedSignersPath;
      };

      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
      receive.fsckObjects = true;

      init.defaultBranch = "main";
      pull.ff = "only";
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
