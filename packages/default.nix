{ pkgs }:

rec {
  blackhole-2ch = pkgs.callPackage ./blackhole-2ch { };
  claude-code-bin = pkgs.callPackage ./claude-code-bin { };
  claude-code-sandboxed = pkgs.callPackage ./claude-code-sandboxed {
    inherit claude-code-bin;
  };
  codex-bin = pkgs.callPackage ./codex-bin { };
  docker-compose = pkgs.callPackage ./docker-compose { };
  gemini-cli-bin = pkgs.callPackage ./gemini-cli-bin { };
  gemini-cli-workforce = pkgs.callPackage ./gemini-cli-workforce {
    inherit gemini-cli-bin;
  };
  opencode-bin = pkgs.callPackage ./opencode-bin { };
  opencode-sandboxed = pkgs.callPackage ./opencode-sandboxed {
    inherit opencode-bin;
  };
}
