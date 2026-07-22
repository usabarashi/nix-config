{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# Antigravity CLI (agy), the Go binary that replaces Gemini CLI.
# Distributed as a closed-source, pre-signed Mach-O via the public GCS bucket;
# the version/url/sha512 are published in the auto-updater manifest at
# https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/darwin_arm64.json
# Pinned here so `agy update` cannot drift the store path out from under Nix.
let
  version = "1.1.5";
  # GCS build ID appended to the version in the bucket path; published alongside
  # `version` in the auto-updater manifest and bumped together with it.
  buildId = "5958982624477184";
  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}/darwin-arm/cli_mac_arm64.tar.gz";
    hash = "sha512-1OM/UqvYpP0JTsOhKzG7G2V8pPsrn4qndAxA/kf1dSZ+sKJNNSY/3dQCdXUBNnAAHJX21cI/39/CzlCYbcY4xA==";
  };
in
stdenvNoCC.mkDerivation {
  pname = "antigravity-cli-bin";
  inherit version src;

  # Tarball contains a single top-level file (./antigravity), so stay in the
  # build dir rather than letting stdenv cd into a (non-existent) source root.
  sourceRoot = ".";
  dontBuild = true;
  # Preserve Google's code signature; stripping invalidates it and the binary
  # would be killed by the macOS kernel on launch.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 antigravity $out/bin/antigravity
    ln -s antigravity $out/bin/agy

    runHook postInstall
  '';

  meta = {
    description = "Antigravity CLI (agy) - Google's Go-based terminal coding agent, successor to Gemini CLI";
    homepage = "https://antigravity.google/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "agy";
  };
}
