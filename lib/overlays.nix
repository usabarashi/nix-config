[
  (final: prev: {
    customPackages = import ../packages { pkgs = final; };
  })

  (final: prev: {
    lib = prev.lib.extend (
      libFinal: libPrev: {
        maintainers = libPrev.maintainers // {
          usabarashi = {
            github = "usabarashi";
            githubId = 19676305;
          };
        };
      }
    );
  })
]
