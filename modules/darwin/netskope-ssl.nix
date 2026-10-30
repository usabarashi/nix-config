_: {
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
  # keep trusting the Netskope inspection CA that this file appends.
  environment.variables = {
    SSL_CERT_FILE = "/etc/nix/ca_cert.pem";
    NIX_SSL_CERT_FILE = "/etc/nix/ca_cert.pem";
    REQUESTS_CA_BUNDLE = "/etc/nix/ca_cert.pem";
    PIP_CERT = "/etc/nix/ca_cert.pem";
  };

  system.activationScripts.postActivation.text = ''
    # Regenerate combined CA certificate bundle (system CAs + Netskope CA),
    # excluding roots distrusted for the eMudhra intermediate CA compromise
    # (CVE-2026-111943, https://github.com/NixOS/nixpkgs/issues/576485).
    # This filters the *macOS* system keychain, which Apple maintains separately
    # from Nix's cacert. nix-darwin's security.pki blacklist is version-gated on
    # pkgs.cacert >= 3.131.1 (NSS dropped the emSign roots), but Apple's root
    # store still ships emSign ECC Root CA - G3 and AAA Certificate Services.
    # Keep these entries until the keychain itself no longer contains them.
    # Verified 2026-10-27: G3 and AAA present; C1 and C3 absent (no-ops).
    NETSKOPE_CERT="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"
    TARGET="/etc/nix/ca_cert.pem"
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
        : > "$CERT_DIR/filtered.pem"
        for cert in "$CERT_DIR"/cert-*.pem; do
          [ -f "$cert" ] || continue
          total=$((total + 1))
          subject=$(/usr/bin/openssl x509 -noout -subject -in "$cert" 2>/dev/null) || {
            cat "$cert" >> "$CERT_DIR/filtered.pem"
            continue
          }
          case "$subject" in
            *"CN=AAA Certificate Services"* | \
            *"CN=emSign ECC Root CA - G3"* | \
            *"CN=emSign Root CA - C1"* | \
            *"CN=emSign ECC Root CA - C3"*)
              removed=$((removed + 1))
              continue
              ;;
          esac
          cat "$cert" >> "$CERT_DIR/filtered.pem"
        done
        kept=$(grep -c "BEGIN CERTIFICATE" "$CERT_DIR/filtered.pem" 2>/dev/null || echo 0)
        if [ "$kept" -gt 0 ] && [ "$((kept + removed))" -eq "$total" ]; then
          cat "$CERT_DIR/filtered.pem" > "$TARGET"
          echo "Netskope SSL: updated $TARGET (removed $removed distrusted root(s) of $total)"
        else
          echo "Netskope SSL: filtered bundle looks wrong (kept $kept of $total certs), leaving $TARGET unchanged" >&2
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
