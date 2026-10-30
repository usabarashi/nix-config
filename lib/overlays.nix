{ oldLibffi }:
let
  cacertDistrust = import ./cacert-distrust.nix;
in
[
  (final: _prev: {
    customPackages = import ../packages { pkgs = final; };
  })

  (_final: prev: {
    lib = prev.lib.extend (
      _libFinal: libPrev: {
        maintainers = libPrev.maintainers // {
          usabarashi = {
            github = "usabarashi";
            githubId = 19676305;
          };
        };
      }
    );
  })

  # https://github.com/NixOS/nixpkgs/issues/541367: the current libffi
  # (apple-source-releases fork) embeds chained-fixups metadata that macOS
  # 27's dyld rejects, aborting any Python ctypes/cffi use (incl. gcloud).
  # Relink just google-cloud-sdk's python3 against the pre-fork libffi from
  # nixpkgs-libffi-fix until the upstream fix reaches nixpkgs-unstable.
  (_final: prev: {
    google-cloud-sdk = prev.google-cloud-sdk.override {
      python314 = prev.python314.override { libffi = oldLibffi; };
    };
  })

  # CVE-2026-111943: remove the roots compromised by (or chained to) the
  # eMudhra intermediate CA leak from every bundle built out of certdata, incl.
  # the cacert.pem that google-cloud-sdk symlinks. See lib/cacert-distrust.nix.
  (_final: prev: {
    cacert = (cacertDistrust { inherit (prev) lib; }).secure prev.cacert;
  })
]
