# Gemini CLI bundle fetched from npm, managed independently of nixpkgs.
#
# Update workflow: update `version` and `hash` below, then deploy.
{
  fetchurl,
  lib,
  stdenvNoCC,
  nodejs_22,
}:
let
  version = "0.41.2";
  src = fetchurl {
    url = "https://registry.npmjs.org/@google/gemini-cli/-/gemini-cli-${version}.tgz";
    hash = "sha256-iA1FpPhnluwh2GMISpkyAlHJoqSWlBmpLzMTvVQkYBg=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "gemini-cli-bin";
  inherit version src;
  dontBuild = true;
  dontStrip = true;
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
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "gemini";
    platforms = lib.platforms.unix;
  };
}
