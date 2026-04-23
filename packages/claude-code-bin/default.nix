# Claude Code native binary fetched from Google Cloud Storage, managed independently of nixpkgs.
#
# Update workflow: update `version` and `hash` below, then deploy.
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  version = "2.1.118";
  src = fetchurl {
    url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/darwin-arm64/claude";
    hash = "sha256-VOXT9lEJuJxgRvR0QJRNUpBsZi0eUXSPYgpDDSatNmU=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "claude-code-bin";
  inherit version src;
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
