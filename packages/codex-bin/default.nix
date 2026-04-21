# Codex CLI native binary fetched from GitHub Releases, managed independently of nixpkgs.
# Update workflow: update `version` and `hash` below, then deploy.
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  version = "0.122.0";
  asset = "codex-aarch64-apple-darwin";
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/${asset}.tar.gz";
    hash = "sha256-dOaIXhpY148CSfrtEm62qyIPnONOdiP55BCCVQNdYcw=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "codex-bin";
  inherit version src;
  # The upstream tarball expands to a single binary at archive root.
  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  installPhase = "install -Dm755 ${asset} $out/bin/codex";
  meta = {
    description = "Pre-built Codex CLI native binary (darwin-arm64), version-pinned";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "codex";
    platforms = [ "aarch64-darwin" ];
  };
}
