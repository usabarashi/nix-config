{ ... }:
{
  # Combined CA certificate bundle for Netskope SSL inspection.
  # Requires bootstrap: generate the bundle before first `nix run .#work`.
  # See activation script below for auto-regeneration on subsequent applies.
  #
  # Bootstrap (one-time, before first `nix run .#work`):
  #   security find-certificate -a -p \
  #     /System/Library/Keychains/SystemRootCertificates.keychain \
  #     /Library/Keychains/System.keychain \
  #     > /tmp/nix_ca_combined.pem
  #   cat /tmp/nix_ca_combined.pem \
  #     "/Library/Application Support/Netskope/STAgent/data/nscacert.pem" \
  #     | sudo tee /etc/nix/ca_cert.pem > /dev/null
  #   rm /tmp/nix_ca_combined.pem
  # After bootstrap, `nix run .#work` manages ssl-cert-file and daemon restarts.
  nix.settings."ssl-cert-file" = "/etc/nix/ca_cert.pem";

  # Expose the combined CA bundle to user-space tools (Rust/rustls, Python requests, curl, etc.)
  environment.variables = {
    SSL_CERT_FILE = "/etc/nix/ca_cert.pem";
    NIX_SSL_CERT_FILE = "/etc/nix/ca_cert.pem";
    REQUESTS_CA_BUNDLE = "/etc/nix/ca_cert.pem";
  };

  system.activationScripts.postActivation.text = ''
    # Regenerate combined CA certificate bundle (system CAs + Netskope CA)
    NETSKOPE_CERT="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"
    TARGET="/etc/nix/ca_cert.pem"
    if [ -f "$NETSKOPE_CERT" ]; then
      TMPFILE=$(mktemp)
      trap 'rm -f "$TMPFILE"' EXIT
      if security find-certificate -a -p \
        /System/Library/Keychains/SystemRootCertificates.keychain \
        /Library/Keychains/System.keychain \
        > "$TMPFILE" && [ -s "$TMPFILE" ]; then
        cat "$TMPFILE" "$NETSKOPE_CERT" > "$TARGET"
        echo "Netskope SSL: updated $TARGET"
      else
        echo "Netskope SSL: failed to extract system CAs, leaving $TARGET unchanged" >&2
      fi
      rm -f "$TMPFILE"
    else
      echo "Netskope SSL: $NETSKOPE_CERT not found, skipping"
    fi
  '';
}
