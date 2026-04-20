{ pkgs }:

rec {
  blackhole-2ch = pkgs.callPackage ./blackhole-2ch { };
  claude-code-bin = pkgs.callPackage ./claude-code-bin { };
  claude-code-sandboxed = pkgs.callPackage ./claude-code-sandboxed {
    inherit claude-code-bin;
  };
  docker-compose = pkgs.callPackage ./docker-compose { };
  gemini-cli-bin = pkgs.callPackage ./gemini-cli-bin { };
  gemini-cli-workforce = pkgs.callPackage ./gemini-cli-workforce {
    inherit gemini-cli-bin;
  };
}
