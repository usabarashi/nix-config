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
    inherit opencode-bin;
  };
}
