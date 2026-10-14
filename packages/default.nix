{ pkgs }:

rec {
  chrome-devtools-mcp = pkgs.callPackage ./chrome-devtools-mcp { };
  claude-code-bin = pkgs.callPackage ./claude-code-bin { };
  claude-code-sandboxed = pkgs.callPackage ./claude-code-sandboxed {
    inherit claude-code-bin sandbox-supervisor;
  };
  docker-compose = pkgs.callPackage ./docker-compose { };
  git-tools-bin = pkgs.callPackage ./git-tools-bin { };
  pi-bin = pkgs.callPackage ./pi-bin { };
  pi-sandboxed = pkgs.callPackage ./pi-sandboxed {
    inherit pi-bin chrome-devtools-mcp sandbox-supervisor;
    # Free-tier files are deployed as immutable Nix-store content (not the
    # mutable mkOutOfStoreSymlink used for the normal config). builtins.path
    # snapshots the current files at eval time and gives them a stable store path.
    freeTierConfig = builtins.path {
      name = "pi-free-tier-config";
      path = ../config/pi/free-tier;
    };
  };
  sandbox-supervisor = pkgs.callPackage ./sandbox-supervisor { };
  terminal-notifier = pkgs.callPackage ./terminal-notifier { };
}
