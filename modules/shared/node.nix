{
  config,
  repoPath,
  ...
}:

{
  # npm registry routed through Takumi Guard's malicious-package blocking
  # proxy (https://flatt.tech/takumi/features/guard). Anonymous mode --
  # no token required. Applies to npm/pnpm/yarn/npx.
  home.file.".npmrc" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/node/npmrc";
    force = true;
  };
}
