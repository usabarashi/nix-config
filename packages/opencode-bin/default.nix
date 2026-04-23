# opencode (sst/opencode) CLI native binary fetched from GitHub Releases, managed independently of nixpkgs.
#
# Upstream ships rapid releases (often multiple per day); nixpkgs lags significantly.
# Update workflow: update `version` and `hash` below, then deploy.
{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
}:
let
  version = "1.14.22";
  asset = "opencode-darwin-arm64";
  src = fetchurl {
    url = "https://github.com/sst/opencode/releases/download/v${version}/${asset}.zip";
    hash = "sha256-zeqDvk2eEvD7SyFosSLwGj0CQ1k8r07IEEHF5tcX+Po=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "opencode-bin";
  inherit version src;
  sourceRoot = ".";
  nativeBuildInputs = [ unzip ];
  dontBuild = true;
  dontStrip = true;
  installPhase = "install -Dm755 opencode $out/bin/opencode";
  meta = {
    description = "Pre-built opencode (sst/opencode) CLI binary (darwin-arm64), version-pinned";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "opencode";
    platforms = [ "aarch64-darwin" ];
  };
}
