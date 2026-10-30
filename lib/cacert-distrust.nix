# Single source of truth for the CA roots distrusted after the eMudhra
# intermediate CA key compromise (CVE-2026-111943).
#
# Every consumer of these roots must remove the same set:
#   - the nix-darwin system bundle, /etc/ssl/certs/ca-certificates.crt
#     (modules/darwin/distrust-emudhra.nix; nix-darwin's security.pki already
#     applies the same blacklist, this repo only repeats the policy)
#   - Apple's /etc/ssl/cert.pem (modules/darwin/distrust-emudhra.nix)
#   - the Netskope keychain-derived bundle (modules/darwin/netskope-ssl.nix)
#   - pkgs.cacertSecure, the filtered bundle for packages that embed a bundle
#     path in their output: google-cloud-sdk (lib/overlays.nix) and the Node
#     wrappers (packages/*-sandboxed, packages/chrome-devtools-mcp)
#
# pkgs.cacert itself is deliberately left alone: overriding it globally rebuilds
# every package that only *tests* against it (certifi, requests,
# cargo-auditable -> cargo -> tree-sitter -> neovim), and those rebuilds are not
# in the binary cache.
#
# https://emudhra.we-have-a-problem.com/
# https://github.com/NixOS/nixpkgs/issues/576485
{ lib }:
let
  # NSS 3.131.1 still ships this root: the compromised intermediates carry
  # Sectigo cross-signs that chain to it, so it is only marked "must verify"
  # for server auth instead of being removed. Blacklist it unconditionally.
  always = [ "Comodo AAA Services root" ];

  # Dropped from certdata in NSS 3.131.1. buildcatrust hard-fails when the
  # blocklist names a certificate that is not in certdata
  # (NixOS/nixpkgs#249080), so these may only be listed below that version.
  removedIn = "3.131.1";
  untilRemoved = [
    "emSign ECC Root CA - G3"
    "emSign Root CA - C1"
    "emSign ECC Root CA - C3"
  ];

  # SHA-256 fingerprints of the same certificates, for bundles that do not come
  # from certdata (Apple's /etc/ssl/cert.pem, `security find-certificate`
  # exports). Whole-certificate matching keeps the filter working when the
  # surrounding text format or a CN changes, and cannot hit a same-named but
  # different certificate. Upper case to match `openssl x509 -fingerprint
  # -sha256`. emSign Root CA - G1 is deliberately absent: it is a different,
  # uncompromised root that remains trusted upstream.
  fingerprints = [
    # Comodo AAA Services root (the Sectigo cross-sign anchor)
    "D7:A7:A0:FB:5D:7E:27:31:D7:71:E9:48:4E:BC:DE:F7:1D:5F:0C:3E:0A:29:48:78:2B:C8:3E:E0:EA:69:9E:F4"
    # emSign ECC Root CA - G3 (the compromised hierarchy)
    "86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B"
    # emSign Root CA - C1 (retired alongside the compromise)
    "12:56:09:AA:30:1D:A0:A2:49:B9:7A:82:39:CB:6A:34:21:6F:44:DC:AC:9F:39:54:B1:42:92:F2:E8:C8:60:8F"
    # emSign ECC Root CA - C3 (retired alongside the compromise)
    "BC:4D:80:9B:15:18:9D:78:DB:3E:1D:8C:F4:F9:72:6A:79:5D:A1:64:3C:A5:F1:35:8E:1D:DB:0E:DC:0D:7E:B3"
  ];
  # Blacklist argument for pkgs.cacert and security.pki.caCertificateBlacklist.
  blacklist =
    cacert: always ++ lib.optionals (lib.versionOlder cacert.version removedIn) untilRemoved;
in
{
  inherit blacklist fingerprints;

  # cacert with the distrusted roots removed, exposed as pkgs.cacertSecure.
  # buildcatrust keeps blacklisted roots in the trust-rules bundle as AUX
  # "reject" blocks; OpenSSL honours those, clients that ignore AUX (Go, rustls)
  # do not, so this is not a drop-in equivalent of removing the bytes.
  secure = cacert: cacert.override { blacklist = blacklist cacert; };
}
