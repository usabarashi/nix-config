# terminal-notifier built from source for arm64-native macOS binaries.
#
# Upstream nixpkgs ships a fetchzip of the alloy/terminal-notifier 2.0.0
# release asset, which is an Intel-only Mach-O. Running it on Apple Silicon
# triggers the macOS 26 "translated via Rosetta" warning. This derivation
# mirrors the approach in NixOS/nixpkgs#515280 — build the julienXX fork
# from source with xcbuildHook so the produced binary matches the host arch.
#
# Remove this override and switch back to pkgs.terminal-notifier once one
# of the upstream PRs (#515280 / #529756) lands.
{
  apple-sdk,
  fetchFromGitHub,
  ibtool,
  lib,
  makeBinaryWrapper,
  stdenv,
  xcbuildHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "terminal-notifier";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "julienXX";
    repo = "terminal-notifier";
    tag = finalAttrs.version;
    hash = "sha256-Hd9cI3R2nQK2deBb5CBYz4DTHAEcO4vzqtA5qZwa1Ao=";
  };

  nativeBuildInputs = [
    ibtool
    makeBinaryWrapper
    xcbuildHook
  ];

  buildInputs = [
    apple-sdk
  ];

  xcbuildFlags = [
    "-target"
    "terminal-notifier"
    "-configuration"
    "Release"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{Applications,bin}
    cp -r Products/Release/terminal-notifier.app $out/Applications/
    makeWrapper \
      $out/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier \
      $out/bin/terminal-notifier \
      --chdir $out/Applications/terminal-notifier.app

    runHook postInstall
  '';

  meta = {
    description = "Send macOS User Notifications from the command-line";
    homepage = "https://github.com/julienXX/terminal-notifier";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "terminal-notifier";
  };
})
