{ homeDirectory, lib, ... }:

let
  extraDir = "${homeDirectory}/.config/nix-extra";
  extraFlakePath = "${extraDir}/flake.nix";
  extraDefaultPath = "${extraDir}/default.nix";
  hasFlake = builtins.pathExists extraFlakePath;
  hasDefault = builtins.pathExists extraDefaultPath;
  extraFlake = builtins.getFlake "path:${extraDir}";
in
{
  imports =
    if hasFlake && (extraFlake ? homeManagerModule) then
      [ extraFlake.homeManagerModule ]
    else
      lib.optional hasDefault extraDefaultPath;
}
