# Minimal process supervisor for the sandbox-exec wrappers (shared by the
# claude and pi wrappers). It forwards HUP/INT/TERM to the supervised child and
# removes the wrapper's private per-invocation temp dir only after the child has
# exited. See sandbox-supervisor.c for the rationale and the signal/race design.
{
  stdenv,
}:
stdenv.mkDerivation {
  pname = "sandbox-supervisor";
  version = "1";
  src = ./sandbox-supervisor.c;
  dontUnpack = true;
  buildPhase = ''
    $CC -Wall -Wextra -Werror -O2 "$src" -o sandbox-supervisor
  '';
  installPhase = ''
    install -Dm755 sandbox-supervisor "$out/bin/sandbox-supervisor"
  '';
}
