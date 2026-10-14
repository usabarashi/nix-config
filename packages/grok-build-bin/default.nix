# Grok Build (`grok`), SpaceXAI's terminal coding agent. Distributed as a
# closed-source, pre-signed Mach-O via x.ai's CLI bucket -- the same artifact
# the official `curl -fsSL https://x.ai/cli/install.sh | bash` fetches.
# Pinned here so `grok`'s self-updater cannot drift the store path out from
# under Nix.
#
# Update workflow: read the current version from the stable channel pointer
#   curl -fsSL https://x.ai/cli/stable
# then update `version` and `hash` (nix store prefetch-file --json <url>).
{
  fetchurl,
  lib,
  stdenvNoCC,
  zstd,
}:
let
  version = "1.0.52";
  platform = "macos-aarch64";
  # Compressed release artifact; the install.sh bucket also serves it from
  # https://x.ai/cli/grok-${version}-${platform}.zst. Use the storage bucket
  # for a stable, non-proxied URL.
  src = fetchurl {
    url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${version}-${platform}.zst";
    hash = "sha256-Rw9apNCnrhxJTjr/6iylmYqMh2fMuOToUgepsuwexcE=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "grok-build-bin";
  inherit version src;
  sourceRoot = ".";
  nativeBuildInputs = [ zstd ];
  # `src` is a single zstd-compressed binary, not a tarball; there is nothing
  # for stdenv's unpackPhase to unpack.
  dontUnpack = true;
  dontBuild = true;
  # Preserve SpaceXAI's code signature; stripping invalidates it and the
  # binary would be killed by the macOS kernel on launch.
  dontStrip = true;
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    zstd -dc "$src" > $out/bin/grok
    chmod 755 $out/bin/grok

    runHook postInstall
  '';
  meta = {
    description = "Pre-built Grok Build CLI (grok, darwin-arm64), version-pinned";
    homepage = "https://x.ai/cli";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "grok";
    platforms = [ "aarch64-darwin" ];
  };
}
