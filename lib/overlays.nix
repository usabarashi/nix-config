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
  (final: prev: {
    google-cloud-sdk = prev.google-cloud-sdk.override {
      python314 = prev.python314.override { libffi = oldLibffi; };
      # gcloud symlinks ${cacert}/etc/ssl/certs/ca-bundle.crt into its own tree,
      # so it consumes the bundle as a file and cannot be steered with
      # SSL_CERT_FILE. It is the only package in this closure whose output
      # references cacert (nix-store -q --referrers nss-cacert-3.131.1).
      cacert = final.cacertSecure;
    };
  })

  # CVE-2026-111943: the eMudhra intermediates chain to Comodo AAA Services
  # root, which cacert 3.131.1 still ships. Expose a bundle with the distrusted
  # roots as a separate attribute instead of overriding pkgs.cacert: a global
  # override changes the hash of every package that merely *tests* against
  # cacert (python3.14-certifi, requests, cargo-auditable -> cargo ->
  # tree-sitter -> neovim), and those rebuilds are not in the binary cache.
  # Most TLS clients read the filtered system bundle through SSL_CERT_FILE /
  # NIX_SSL_CERT_FILE anyway (nix-darwin's security.pki applies the same
  # blacklist), so only packages that embed a cacert path need this.
  (_final: prev: {
    cacertSecure = (cacertDistrust { inherit (prev) lib; }).secure prev.cacert;
  })
]
