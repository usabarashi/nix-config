{ pkgs }:

rec {
  antigravity-cli-bin = pkgs.callPackage ./antigravity-cli-bin { };
  chrome-devtools-mcp = pkgs.callPackage ./chrome-devtools-mcp { };
  claude-code-bin = pkgs.callPackage ./claude-code-bin { };
  claude-code-sandboxed = pkgs.callPackage ./claude-code-sandboxed {
    inherit claude-code-bin;
  };
  codex-bin = pkgs.callPackage ./codex-bin { };
  docker-compose = pkgs.callPackage ./docker-compose { };
  git-tools-bin = pkgs.callPackage ./git-tools-bin { };
  opencode-bin = pkgs.callPackage ./opencode-bin { };
  opencode-sandboxed = pkgs.callPackage ./opencode-sandboxed {
    inherit codex-bin opencode-bin;
    # Free-tier files are deployed as immutable Nix-store content (R44): not
    # the mutable mkOutOfStoreSymlink used for the normal config. builtins.path
    # snapshots the current file at eval time and gives it a stable store path.
    freeTierConfig = builtins.path {
      name = "free-tier.json";
      path = ../config/opencode/free-tier.json;
    };
    freeTierModels = builtins.path {
      name = "free-tier-models.json";
      path = ../config/opencode/free-tier-models.json;
    };
  };
  terminal-notifier = pkgs.callPackage ./terminal-notifier { };
}
