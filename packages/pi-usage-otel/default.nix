# node_modules for config/pi/extensions/usage-otel, which is read-only in the
# sandbox. index.ts and usage.ts are copied so free-tier can use `pi -e`.
{
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "pi-usage-otel";
  version = "0.1.0";

  src = builtins.path {
    name = "pi-usage-otel-src";
    path = ../../config/pi/extensions/usage-otel;
  };

  npmDepsHash = "sha256-nxwYoNdAQQvi5C9JvJLwQMpa1r1w8ESB4Cg5/zPM7JQ=";
  npmFlags = [ "--omit=dev" ];
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp package.json index.ts usage.ts "$out/"
    cp -R node_modules "$out/node_modules"
    runHook postInstall
  '';

  meta.description = "OpenTelemetry SDK node_modules for the Pi usage extension";
}
