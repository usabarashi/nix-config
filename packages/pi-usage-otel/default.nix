# node_modules for config/pi/extensions/usage-otel.
#
# The extension source stays in the Pi extensions tree (an out-of-store symlink
# into this repo, read-only under Seatbelt). npm install cannot run there, so
# the pi wrapper sets PI_USAGE_OTEL_MODULES to this output and the extension
# require()s the OpenTelemetry SDK from it. index.ts and usage.ts are copied
# alongside node_modules so free-tier sessions, which do not load the repo
# extensions directory, can be started with `pi -e <this>/index.ts`.
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
