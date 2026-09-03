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

  # Hook scripts live as plain files next to this module (git/*.sh), not as
  # Nix-interpolated strings, so the shell code is edited outside Nix.
  # writeScript (no generated shebang) keeps the files' own #!/usr/bin/env
  # bash line and produces an executable store copy.
  preCommitHook = pkgs.writeScript "global-pre-commit" (builtins.readFile ./pre-commit.sh);
  prePushHook = pkgs.writeScript "global-pre-push" (builtins.readFile ./pre-push.sh);
in
{
  home.packages = with pkgs; [
    gh
    ghq
    gitleaks
    customPackages.git-tools-bin
  ];

  xdg.configFile."git/hooks/pre-commit".source = preCommitHook;
  xdg.configFile."git/hooks/pre-push".source = prePushHook;

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