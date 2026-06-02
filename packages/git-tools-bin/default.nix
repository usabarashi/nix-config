# git-tools native binaries fetched from GitHub Releases, managed independently of nixpkgs.
#
# Building from source requires full Xcode (the FoundationModels @Generable macro
# plugin ships only with Xcode), which a Nix sandbox cannot provide, so the
# pre-built release archive is used instead.
#
# Provides: git-commit-message, git-branch-name, git-branch-clean, git-secret-check
#
# Update workflow: update `version` and `hash` below, then deploy.
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  version = "20260602-033259";
  src = fetchurl {
    url = "https://github.com/usabarashi/git-tools/releases/download/build-${version}/git-tools-${version}-macos26-arm64.tar.gz";
    hash = "sha256-FCXdnSYsKcjn7aHNSF7HQpLChjWDBLy4DltL9NiMOvo=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "git-tools-bin";
  inherit version src;
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    for tool in git-commit-message git-branch-name git-branch-clean git-secret-check; do
      install -Dm755 "$tool" "$out/bin/$tool"
    done
    runHook postInstall
  '';
  meta = {
    description = "Pre-built git-tools binaries (darwin-arm64): Git subcommands generating Conventional Commits messages and branch names, cleaning merged branches, and scanning staged changes for secrets via Apple's on-device model";
    homepage = "https://github.com/usabarashi/git-tools";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
}
