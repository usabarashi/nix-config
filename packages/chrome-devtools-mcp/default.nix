# chrome-devtools-mcp: Google's MCP server for Chrome DevTools, fetched as the
# pre-built npm tarball and wrapped with a pinned Node runtime.
#
# The published npm package is fully bundled by rollup: package.json declares no
# `dependencies` and the tarball ships no `node_modules` (puppeteer-core,
# lighthouse, the MCP SDK, etc. are all inlined into `build/`). So there is
# nothing to resolve at build time -- this follows the repo's `*-bin` convention
# (fixed upstream artifact + fixed hash + wrapper) rather than buildNpmPackage.
#
# Node is required at runtime but never reaches the user's PATH: the wrapper
# invokes `${nodejs_22}/bin/node` from the Nix store and only `chrome-devtools-mcp`
# is exposed in $out/bin.
#
# The whole package root (package.json + build/) is installed, not just build/:
# the entrypoint is ESM by virtue of package.json's `"type": "module"`, so the
# manifest must remain in an ancestor directory or Node would treat the `.js`
# entrypoint as CommonJS and fail on the first `import`.
#
# Runtime browser: drives the system-installed Google Chrome, auto-detected by
# puppeteer-core (no Chrome bundled here). If detection ever fails, point it at
# `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` via the
# server's --executablePath flag or PUPPETEER_EXECUTABLE_PATH.
#
# Update workflow: bump `version`, then update `hash` (the build fails printing
# the correct SRI hash on mismatch), then deploy.
{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs_22,
  cacert,
  makeWrapper,
}:
let
  # Same blacklist as lib/overlays.nix. Node ignores SSL_CERT_FILE unless
  # --use-openssl-ca is set, so the wrapper points it at this bundle.
  # Comodo AAA Services root remains in cacert >= 3.131.1; the emSign roots
  # do not, and buildcatrust rejects unknown blocklist names.
  cacertSecure = cacert.override {
    blacklist = [
      "Comodo AAA Services root"
    ]
    ++ lib.optionals (lib.versionOlder cacert.version "3.131.1") [
      "emSign ECC Root CA - G3"
      "emSign Root CA - C1"
      "emSign ECC Root CA - C3"
    ];
  };
  version = "1.6.0";
  src = fetchurl {
    url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${version}.tgz";
    hash = "sha512-VZX6f/OjQSYhy2BGGRs+y3LsrsAQAz/HwZCWKBLVyST/4r/3zjVEjjVW7gMCVbRDuspnVdcp5hQDPrQ5UFrdZw==";
  };
in
stdenvNoCC.mkDerivation {
  pname = "chrome-devtools-mcp";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  # npm tarballs unpack into a top-level `package/` directory.
  sourceRoot = "package";

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/chrome-devtools-mcp"
    cp -R package.json build "$out/lib/chrome-devtools-mcp/"
    install -Dm644 LICENSE "$out/share/doc/chrome-devtools-mcp/LICENSE"

    makeWrapper "${nodejs_22}/bin/node" "$out/bin/chrome-devtools-mcp" \
      --add-flags "$out/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js" \
      --set SSL_CERT_FILE "${cacertSecure}/etc/ssl/certs/ca-bundle.crt" \
      --set NODE_OPTIONS "--use-openssl-ca"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/chrome-devtools-mcp" --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server that exposes Chrome DevTools (via puppeteer-core) to MCP clients; wraps the pre-bundled npm release with a pinned Node runtime";
    homepage = "https://github.com/ChromeDevTools/chrome-devtools-mcp";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "chrome-devtools-mcp";
    platforms = [ "aarch64-darwin" ];
  };
}
