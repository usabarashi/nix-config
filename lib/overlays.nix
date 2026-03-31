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
]
