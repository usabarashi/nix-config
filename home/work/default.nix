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
    stateVersion = "25.11";
  };

  targets.darwin.copyApps = {
    enable = true;
    enableChecks = true;
  };

  home.packages = with pkgs; [
    _1password-cli
    gmailctl
  ];

  imports = [
    ../../modules/darwin/karabiner.nix
    ../../modules/shared/agents.nix
    ../../modules/shared/container.nix
    ../../modules/shared/extra.nix
    ../../modules/shared/git.nix
    ../../modules/shared/neovim.nix
    ../../modules/shared/ssh.nix
    ../../modules/shared/terminal.nix
    ../../modules/shared/terraform.nix
    ../../modules/shared/vscode.nix
  ];
}
