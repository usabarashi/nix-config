{
  pkgs,
  userName,
  homeDirectory,
  ...
}:

{
  programs.home-manager.enable = true;
  home = {
    username = userName;
    inherit homeDirectory;
    stateVersion = "26.05";
    enableNixpkgsReleaseCheck = false;
  };

  targets.darwin.copyApps = {
    enable = true;
    enableChecks = true;
  };

  home.packages = with pkgs; [
    discord
    iina
    ripgrep
    slack
    zoom-us
  ];

  imports = [
    ../../modules/darwin/karabiner.nix
    ../../modules/shared/agents.nix
    ../../modules/shared/extra.nix
    ../../modules/shared/gcloud.nix
    ../../modules/shared/git.nix
    ../../modules/shared/llm.nix
    ../../modules/shared/neovim.nix
    ../../modules/shared/node.nix
    ../../modules/shared/ssh.nix
    ../../modules/shared/terminal.nix
    ../../modules/shared/terraform.nix
    ../../modules/shared/vscode.nix
  ];
}
