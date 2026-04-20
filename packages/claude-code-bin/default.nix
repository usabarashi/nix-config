# Claude Code native binary fetched from Google Cloud Storage, managed independently of nixpkgs.
# Requires --impure flag for builtins.fetchurl (no hash verification).
#
# Update workflow: update `version` below, then deploy.
{
  lib,
  stdenvNoCC,
}:
let
  version = "2.1.112";
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
  platformKey = "darwin-arm64";
in
stdenvNoCC.mkDerivation {
  pname = "claude-code-bin";
  inherit version;
  src = builtins.fetchurl "${baseUrl}/${version}/${platformKey}/claude";
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  installPhase = "install -Dm755 $src $out/bin/claude";
  meta = {
    description = "Pre-built Claude Code native binary (darwin-arm64), version-pinned";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "claude";
    platforms = [ "aarch64-darwin" ];
  };
}
