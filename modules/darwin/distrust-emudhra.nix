{ lib, pkgs, ... }:
{
  # CVE-2026-111943. nix-darwin's security.pki passes this list through
  # pkgs.cacert.override, which replaces any blacklist set by the cacert
  # overlay, so the same names have to be repeated here. Comodo AAA Services
  # root is still in cacert 3.131.1. The emSign roots are not, and
  # buildcatrust fails on an unknown blocklist name.
  # https://emudhra.we-have-a-problem.com/
  # https://github.com/NixOS/nixpkgs/issues/576485
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
  ]
  ++ lib.optionals (lib.versionOlder pkgs.cacert.version "3.131.1") [
    "emSign ECC Root CA - G3"
    "emSign Root CA - C1"
    "emSign ECC Root CA - C3"
  ];

  # Apple's /etc/ssl/cert.pem is not in the Nix store at eval time, and
  # built-in curl/git/python3/openssl read it without checking revocation.
  # Filter it on each darwin-rebuild. A separate activation script name so
  # this does not collide with netskope-ssl.nix's postActivation.
  # macOS updates can restore the file; the next apply puts the filter back.
  # C1 and C3 are absent from the keychain as of 2026-10-27 (the match is a
  # no-op) but are the other roots NSS 3.131.1 removed.
  system.activationScripts.distrustEmudhraRoots.text = ''
    CERT_PEM=/etc/ssl/cert.pem
    if [ -f "$CERT_PEM" ]; then
      TMP=$(mktemp)
      awk '/^(###|===) /{skip=0}
        /^=== .*\/CN=(AAA Certificate Services|emSign ECC Root CA - G3|emSign Root CA - C1|emSign ECC Root CA - C3)$/{skip=1}
        !skip' "$CERT_PEM" > "$TMP"
      if [ -s "$TMP" ] && ! cmp -s "$TMP" "$CERT_PEM"; then
        cat "$TMP" > "$CERT_PEM"
        echo "distrust-emudhra: updated $CERT_PEM"
      fi
      rm -f "$TMP"
    else
      echo "distrust-emudhra: $CERT_PEM not found" >&2
    fi
  '';
}
