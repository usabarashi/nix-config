{
  config,
  repoPath,
  ...
}:

{
  # npm registry routed through Takumi Guard's malicious-package blocking
  # proxy (https://flatt.tech/takumi/features/guard). Anonymous mode --
  # no token required. ~/.npmrc covers npm/pnpm/npx (pnpm reads npm-style
  # config); yarn berry ignores ~/.npmrc and is configured via ~/.yarnrc.yml
  # below.
  home.file.".npmrc" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/node/npmrc";
    force = true;
  };

  # Yarn berry does not read ~/.npmrc, so the registry proxy and release-age
  # gate must be restated here for yarn to honor them.
  home.file.".yarnrc.yml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/node/yarnrc.yml";
    force = true;
  };
}
