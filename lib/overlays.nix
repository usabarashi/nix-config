{ oldLibffi }:
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

  # CVE-2026-111943: eMudhra intermediate keys were compromised. NSS 3.131.1
  # drops the emSign roots, but Comodo AAA Services root (the Sectigo
  # cross-sign anchor) is still in that certdata. buildcatrust fails on a
  # blocklist name that is not in certdata (NixOS/nixpkgs#249080), so the
  # emSign names are included only while cacert is older than 3.131.1.
  # https://emudhra.we-have-a-problem.com/
  # https://github.com/NixOS/nixpkgs/issues/576485
  (_final: prev: {
    cacert = prev.cacert.override {
      blacklist = [
        "Comodo AAA Services root"
      ]
      ++ prev.lib.optionals (prev.lib.versionOlder prev.cacert.version "3.131.1") [
        "emSign ECC Root CA - G3"
        "emSign Root CA - C1"
        "emSign ECC Root CA - C3"
      ];
    };
  })
]
