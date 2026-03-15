# See: https://github.com/nix-community/home-manager/blob/master/modules/programs/vscode.nix
{
  config,
  pkgs,
  lib,
  repoPath,
  ...
}:

let
  extensionsConfig = import ./vscode-extensions.nix { inherit pkgs; };
  inherit (extensionsConfig) collectExtensions;
  inherit (extensionsConfig) programmingLanguages;
in
{
  home.packages = with pkgs; [
    nil
    nixfmt-rfc-style
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    profiles.default.extensions = collectExtensions programmingLanguages.alloy;
  };

  home.file."Library/Application Support/Code/User/settings.json" = lib.mkForce {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/.vscode/settings.json";
    force = true;
  };

  home.file."Library/Application Support/Code/User/keybindings.json" = lib.mkForce {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/.vscode/keybindings.json";
    force = true;
  };

  home.file."Library/Application Support/Code/User/snippets" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/.vscode/snippets";
    force = true;
    recursive = true;
  };

  home.file."Library/Application Support/Code/User/tasks.json" = lib.mkForce {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/.vscode/tasks.json";
    force = true;
  };

  home.file."Library/Application Support/Code/User/prompts" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/.vscode/prompts";
    force = true;
    recursive = true;
  };

  home.file."Library/Application Support/Code/User/mcp.json" = lib.mkForce {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/.vscode/mcp.json";
    force = true;
  };

  home.activation.vscodeVimConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    echo "Setting VSCode Vim Extension configuration..."
    /usr/bin/defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false
    /usr/bin/defaults write com.microsoft.VSCodeInsiders ApplePressAndHoldEnabled -bool false
  '';
}
