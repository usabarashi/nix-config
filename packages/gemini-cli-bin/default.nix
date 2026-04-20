# Pre-bundled Gemini CLI fetched from npm, managed independently of nixpkgs.
# Requires --impure flag for builtins.fetchurl (no hash verification).
#
# Update workflow: update `version` below, then deploy.
{
  lib,
  stdenvNoCC,
  nodejs_22,
}:
let
  version = "0.38.2";
in
stdenvNoCC.mkDerivation {
  pname = "gemini-cli-bin";
  inherit version;
  src = builtins.fetchurl "https://registry.npmjs.org/@google/gemini-cli/-/gemini-cli-${version}.tgz";
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/gemini-cli $out/bin
    cp -r ./bundle/. $out/share/gemini-cli/
    printf '#!%s\nexec %s/bin/node --no-warnings=DEP0040 %s/share/gemini-cli/gemini.js "$@"\n' \
      "${stdenvNoCC.shell}" "${nodejs_22}" "$out" > $out/bin/gemini
    chmod +x $out/bin/gemini
    runHook postInstall
  '';
  meta = {
    description = "Pre-bundled Gemini CLI (npm @google/gemini-cli), version-pinned";
    license = lib.licenses.asl20;
    mainProgram = "gemini";
    platforms = lib.platforms.unix;
  };
}
