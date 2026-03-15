{ pkgs }:

{
  blackhole-2ch = pkgs.callPackage ./blackhole-2ch { };
  claude-code-sandboxed = pkgs.callPackage ./claude-code-sandboxed { };
  docker-compose = pkgs.callPackage ./docker-compose { };
  gemini-cli-workforce = pkgs.callPackage ./gemini-cli-workforce { };
}
