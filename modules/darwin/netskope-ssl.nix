{
  lib,
  pkgs,
  ...
}:
let
  distrust = import ../../lib/cacert-distrust.nix { inherit lib; };
  extraRoots = distrust.extraRoots pkgs;
in
{
  # Combined CA certificate bundle for Netskope SSL inspection.
  # Requires bootstrap: generate the bundle before first `nix run .#mac14-10`.
  # See activation script below for auto-regeneration on subsequent applies.
  #
  # Bootstrap (one-time, before first `nix run .#mac14-10`):
  #   security find-certificate -a -p \
  #     /System/Library/Keychains/SystemRootCertificates.keychain \
  #     /Library/Keychains/System.keychain \
  #     > /tmp/nix_ca_combined.pem
  #   cat /tmp/nix_ca_combined.pem \
  #     "/Library/Application Support/Netskope/STAgent/data/nscacert.pem" \
  #     | sudo tee /etc/nix/ca_cert.pem > /dev/null
  #   rm /tmp/nix_ca_combined.pem
  # After bootstrap, `nix run .#mac14-10` manages ssl-cert-file and daemon restarts.
  nix.settings."ssl-cert-file" = "/etc/nix/ca_cert.pem";

  # Expose the combined CA bundle to user-space tools (Rust/rustls, Python requests, curl, etc.)
  # PIP_CERT is the filtered bundle, not /etc/ssl/cert.pem: built-in pip must
  # keep trusting the Netskope inspection CA that this file appends. It only
  # exists after the one-time bootstrap described above; until then pip fails
  # loudly instead of silently using its own root copy.
  environment.variables = {
    SSL_CERT_FILE = "/etc/nix/ca_cert.pem";
    NIX_SSL_CERT_FILE = "/etc/nix/ca_cert.pem";
    REQUESTS_CA_BUNDLE = "/etc/nix/ca_cert.pem";
    PIP_CERT = "/etc/nix/ca_cert.pem";
  };

  system.activationScripts.postActivation.text = ''
    # Regenerate combined CA certificate bundle (system CAs + Netskope CA),
    # excluding the roots distrusted for the eMudhra intermediate CA compromise
    # (CVE-2026-111943, https://github.com/NixOS/nixpkgs/issues/576485).
    # This filters the *macOS* system keychain, which Apple maintains separately
    # from Nix's cacert: the keychain still ships emSign ECC Root CA - G3 and
    # AAA Certificate Services even after NSS dropped or distrusted them.
    # Certificates are matched by SHA-256 fingerprint (lib/cacert-distrust.nix),
    # not by subject, so a renamed CN cannot slip through.
    # Verified 2026-10-27: G3 and AAA present; C1 and C3 absent (no-ops).
    NETSKOPE_CERT="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"
    TARGET="/etc/nix/ca_cert.pem"
    DISTRUSTED_FPS="${lib.concatStringsSep " " distrust.fingerprints}"
    REQUIRED_FPS="${lib.concatStringsSep " " distrust.requiredRoots}"
    EXTRA_ROOTS="${extraRoots}"
    if [ -f "$NETSKOPE_CERT" ]; then
      TMPFILE=$(mktemp)
      CERT_DIR=$(mktemp -d)
      trap 'rm -f "$TMPFILE"; rm -rf "$CERT_DIR"' EXIT
      if security find-certificate -a -p \
        /System/Library/Keychains/SystemRootCertificates.keychain \
        /Library/Keychains/System.keychain \
        > "$TMPFILE" && [ -s "$TMPFILE" ]; then
        cat "$TMPFILE" "$NETSKOPE_CERT" > "$CERT_DIR/combined.pem"
        awk -v dir="$CERT_DIR" '
          /-----BEGIN CERTIFICATE-----/ { n++; if (out) close(out); out = dir "/cert-" n ".pem" }
          out { print > out }
        ' "$CERT_DIR/combined.pem"
        total=0
        removed=0
        seen=""
        : > "$CERT_DIR/filtered.pem"
        for cert in "$CERT_DIR"/cert-*.pem; do
          [ -f "$cert" ] || continue
          total=$((total + 1))
          fp=$(/usr/bin/openssl x509 -noout -fingerprint -sha256 -in "$cert" 2>/dev/null | cut -d= -f2) || fp=""
          if [ -z "$fp" ]; then
            echo "Netskope SSL: cannot parse a keychain certificate, keeping it as-is" >&2
            cat "$cert" >> "$CERT_DIR/filtered.pem"
            continue
          fi
          case " $DISTRUSTED_FPS " in
            *" $fp "*)
              removed=$((removed + 1))
              continue
              ;;
          esac
          seen="$seen $fp"
          cat "$cert" >> "$CERT_DIR/filtered.pem"
        done
        # Same reason as distrust-emudhra.nix: without the self-signed SSL.com
        # roots, dropping AAA would break SSL.com / Cloudflare chains.
        added=0
        for req in $REQUIRED_FPS; do
          case " $seen " in
            *" $req "*) continue ;;
          esac
          if [ -f "$EXTRA_ROOTS/$req.pem" ]; then
            cat "$EXTRA_ROOTS/$req.pem" >> "$CERT_DIR/filtered.pem"
            added=$((added + 1))
          else
            echo "Netskope SSL: no PEM for required root $req in $EXTRA_ROOTS" >&2
          fi
        done
        kept=$(grep -c "BEGIN CERTIFICATE" "$CERT_DIR/filtered.pem" 2>/dev/null || echo 0)
        if [ "$kept" -gt 0 ] && [ "$((kept - added + removed))" -eq "$total" ]; then
          cat "$CERT_DIR/filtered.pem" > "$TARGET"
          echo "Netskope SSL: updated $TARGET (removed $removed of $total certs, added $added required root(s))"
        else
          echo "Netskope SSL: filtered bundle looks wrong (kept $kept, removed $removed, added $added of $total), leaving $TARGET unchanged" >&2
        fi
      else
        echo "Netskope SSL: failed to extract system CAs, leaving $TARGET unchanged" >&2
      fi
      rm -f "$TMPFILE"
      rm -rf "$CERT_DIR"
    else
      echo "Netskope SSL: $NETSKOPE_CERT not found, skipping"
    fi
  '';
}
