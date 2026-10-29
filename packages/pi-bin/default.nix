# Pi (`pi`), Earendil Works' minimal terminal coding agent, distributed as a
# Bun-compiled standalone Mach-O via GitHub Releases. The official installer
# (`curl -fsSL https://pi.dev/install.sh | sh`) installs the npm package; this
# tarball is the pinned, dependency-free equivalent. Pinned here so
# `pi update --self` cannot drift the store path out from under Nix.
#
# The Bun binary resolves its runtime assets -- theme/, export-html/, and
# photon_rs_bg.wasm -- from the directory of the executable
# (path.dirname(process.execPath)), so the whole release tree is installed
# under libexec and exposed through a thin wrapper. Installing only the binary
# into $out/bin would leave those lookups pointing at the store bin/, which
# holds no assets.
#
# Update workflow: read the current version from GitHub Releases, then update
# `version` and `hash` (nix store prefetch-file --json <url>, or the release's
# SHA256SUMS asset).
{
  fetchurl,
  lib,
  makeWrapper,
  stdenvNoCC,
}:
let
  version = "1.4.0";
  asset = "pi-darwin-arm64.tar.gz";
  src = fetchurl {
    url = "https://github.com/earendil-works/pi/releases/download/v${version}/${asset}";
    hash = "sha256-edmXnXaipa23wo4n6bRGKZKMzQ3J+7aucheGC9Xovl0=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "pi-bin";
  inherit version src;
  sourceRoot = ".";
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  # Preserve the Bun-compiled binary's code signature; stripping invalidates it
  # and the macOS kernel would kill the binary on launch.
  dontStrip = true;
  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec
    cp -R pi $out/libexec/pi
    chmod 755 $out/libexec/pi/pi

    makeWrapper $out/libexec/pi/pi $out/bin/pi

    runHook postInstall
  '';
  meta = {
    description = "Pre-built Pi coding agent CLI (darwin-arm64), version-pinned";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "pi";
    platforms = [ "aarch64-darwin" ];
  };
}
