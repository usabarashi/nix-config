{
  lib,
  pkgs,
  ...
}:
let
  distrust = import ../../lib/cacert-distrust.nix { inherit lib; };
  # The three GNU-only conveniences below (readlink -f, --reference) are pinned
  # to the same coreutils the activation PATH already puts first, so the script
  # does not depend on which implementation resolves.
  inherit (pkgs) coreutils;
  extraRoots = distrust.extraRoots pkgs;
in
{
  # The pinned nix-darwin already appends the eMudhra roots to whatever is
  # listed here (security.pki builds /etc/ssl/certs/ca-certificates.crt from
  # pkgs.cacert.override { blacklist = caCertificateBlacklist ++ [ ... ]; }), so
  # this repeats upstream instead of covering a gap. It is kept so the policy
  # lives in this repo if upstream ever drops it, and so it cannot drift from
  # lib/overlays.nix.
  # https://emudhra.we-have-a-problem.com/
  # https://github.com/NixOS/nixpkgs/issues/576485
  security.pki.caCertificateBlacklist = distrust.blacklist pkgs.cacert;

  # Apple's /etc/ssl/cert.pem is not built from certdata and is not in the store
  # at eval time. Built-in curl, openssl and python3 read it (without checking
  # revocation) whenever SSL_CERT_FILE does not point elsewhere, so the
  # security.pki bundle does not cover them. Filter it on every activation;
  # macOS updates restore the file and the next apply filters it again.
  #
  # Apple ships the 2021 OpenBSD list, which has no self-signed SSL.com root, so
  # SSL.com / Cloudflare chains (example.com) reach AAA through the cross-signed
  # SSL.com root. Removing AAA alone broke those, so the script also appends the
  # missing self-signed roots from distrust.extraRoots (verified by fingerprint);
  # that keeps AAA distrusted without losing legitimate chains.
  #
  # This is appended to postActivation because nix-darwin only runs the fixed,
  # ordered list of fragment names (modules/system/activation-scripts.nix);
  # a custom activationScripts name such as distrustEmudhraRoots would never
  # execute.
  #
  # The filter matches SHA-256 fingerprints of whole PEM blocks rather than
  # Apple's "### / ===" header text, so it keeps working if that layout changes
  # and leaves unrelated roots (including emSign Root CA - G1) untouched.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    CERT_PEM=/etc/ssl/cert.pem
    DISTRUSTED_FPS="${lib.concatStringsSep " " distrust.fingerprints}"
    REQUIRED_FPS="${lib.concatStringsSep " " distrust.requiredRoots}"
    EXTRA_ROOTS="${extraRoots}"

    if [ ! -f "$CERT_PEM" ]; then
      echo "distrust-emudhra: $CERT_PEM not found, skipping" >&2
    else
      # Blocks, not certificates: a trust-rules bundle carries the same
      # certificate twice, once plain and once as "TRUSTED CERTIFICATE".
      count_cert_blocks() {
        grep -c -e '^-----BEGIN CERTIFICATE-----$' -e '^-----BEGIN TRUSTED CERTIFICATE-----$' "$1" || true
      }

      # Follow a symlinked bundle so the link itself is preserved.
      TARGET=$(${coreutils}/bin/readlink -f "$CERT_PEM") || TARGET=$CERT_PEM
      TMP=$(mktemp "$(dirname "$TARGET")/.cert.pem.XXXXXX") || TMP=""

      if [ -z "$TMP" ]; then
        echo "distrust-emudhra: cannot create a temporary file next to $TARGET" >&2
      else
        removed=0
        unknown=0
        incert=0
        chunk=""
        seen=""
        while IFS= read -r line || [ -n "$line" ]; do
          chunk="$chunk$line"$'\n'
          case "$line" in
            "-----BEGIN CERTIFICATE-----" | "-----BEGIN TRUSTED CERTIFICATE-----")
              incert=1
              continue
              ;;
          esac
          case "$line" in
            "-----END CERTIFICATE-----" | "-----END TRUSTED CERTIFICATE-----") ;;
            *) continue ;;
          esac
          # A block can carry trust rules ("TRUSTED CERTIFICATE"); either
          # wrapper ends the chunk so openssl only ever sees one certificate.
          [ "$incert" -eq 1 ] || continue
          incert=0
          fp=$(printf '%s' "$chunk" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2) || fp=""
          if [ -z "$fp" ]; then
            # Keep what cannot be parsed rather than guessing; checked below.
            unknown=$((unknown + 1))
            printf '%s' "$chunk" >> "$TMP"
          else
            case " $DISTRUSTED_FPS " in
              *" $fp "*)
                removed=$((removed + 1))
                ;;
              *)
                seen="$seen $fp"
                printf '%s' "$chunk" >> "$TMP"
                ;;
            esac
          fi
          chunk=""
        done < "$TARGET"
        # Text after the last certificate.
        printf '%s' "$chunk" >> "$TMP"

        # Restore the self-signed roots that Apple's 2021 bundle lacks; without
        # them, dropping AAA would break SSL.com / Cloudflare chains.
        added=0
        for req in $REQUIRED_FPS; do
          case " $seen " in
            *" $req "*) continue ;;
          esac
          if [ -f "$EXTRA_ROOTS/$req.pem" ]; then
            cat "$EXTRA_ROOTS/$req.pem" >> "$TMP"
            added=$((added + 1))
          else
            echo "distrust-emudhra: no PEM for required root $req in $EXTRA_ROOTS" >&2
          fi
        done

        kept=$(count_cert_blocks "$TMP")
        found=$(count_cert_blocks "$TARGET")

        if [ "$unknown" -gt 0 ]; then
          echo "distrust-emudhra: $unknown of $found certificate(s) in $TARGET could not be parsed and were kept as-is" >&2
        fi

        # Invariant: nothing was lost and nothing but whole certificates was
        # dropped (kept already includes the roots added above).
        if [ "$found" -eq 0 ]; then
          echo "distrust-emudhra: no certificates found in $TARGET, leaving it unchanged" >&2
          rm -f "$TMP"
        elif [ "$removed" -eq 0 ] && [ "$unknown" -eq "$found" ]; then
          # openssl could not read any block: reporting "already filtered" here
          # would claim a guarantee the filter never checked.
          echo "distrust-emudhra: no certificate in $TARGET could be parsed; it was NOT filtered" >&2
          rm -f "$TMP"
        elif [ "$kept" -gt 0 ] && [ "$((kept - added + removed))" -eq "$found" ]; then
          if [ "$removed" -eq 0 ] && [ "$added" -eq 0 ]; then
            echo "distrust-emudhra: $TARGET already has none of the distrusted roots ($kept kept)"
            rm -f "$TMP"
          else
            # The temporary file is root-owned and mode 0600, so the metadata has
            # to match the original before the swap; otherwise the bundle becomes
            # unreadable to non-root clients. Refuse to replace if either fails.
            if ${coreutils}/bin/chmod --reference="$TARGET" "$TMP" 2>/dev/null \
              && ${coreutils}/bin/chown --reference="$TARGET" "$TMP" 2>/dev/null; then
              if mv -f "$TMP" "$TARGET"; then
                echo "distrust-emudhra: $TARGET updated (removed $removed of $found distrusted root(s), added $added required root(s))"
              else
                echo "distrust-emudhra: failed to replace $TARGET, left unchanged" >&2
                rm -f "$TMP"
              fi
            else
              echo "distrust-emudhra: cannot copy mode/ownership onto $TMP, leaving $TARGET unchanged" >&2
              rm -f "$TMP"
            fi
          fi
        else
          echo "distrust-emudhra: filtered bundle looks wrong (kept $kept, removed $removed, added $added of $found), leaving $TARGET unchanged" >&2
          rm -f "$TMP"
        fi
      fi
    fi
  '';
}
