# Codex CLI package fetched from GitHub Releases, managed independently of nixpkgs.
#
# Update workflow: update `version` and `hash` below, then deploy.
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  version = "0.147.0";
  asset = "codex-package-aarch64-apple-darwin";
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/${asset}.tar.gz";
    hash = "sha256-F7KYTrIrYH49DCVyglL8kPUQ5Ha605ptn0XNsapoVDI=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "codex-bin";
  inherit version src;
  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall

    install -Dm755 bin/codex "$out/bin/codex"
    install -Dm755 bin/codex-code-mode-host "$out/bin/codex-code-mode-host"
    install -Dm755 codex-path/rg "$out/codex-path/rg"
    install -Dm755 codex-resources/zsh/bin/zsh "$out/codex-resources/zsh/bin/zsh"
    install -Dm644 codex-package.json "$out/codex-package.json"

    runHook postInstall
  '';
  meta = {
    description = "Pre-built Codex CLI package (darwin-arm64), version-pinned";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "codex";
    platforms = [ "aarch64-darwin" ];
  };
}
