{
  config,
  repoPath,
  ...
}:

{
  # Terraform CLI configuration
  # Plugin cache is shared across all workspaces to reduce disk usage
  home.file = {
    ".terraformrc" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/terraform/terraformrc";
    };
  };

  # Create plugin cache directory
  home.activation.terraformPluginCache = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.terraform.d/plugin-cache
  '';
}
