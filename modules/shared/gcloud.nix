{
  pkgs,
  ...
}:

let
  gcloudWorkforceAuth = pkgs.writeShellApplication {
    name = "gcloud-workforce-auth";
    runtimeInputs = [ pkgs.google-cloud-sdk ];
    text = ''
      : "''${WORKFORCE_POOL_ID:?set WORKFORCE_POOL_ID via direnv}"
      : "''${PROVIDER_ID:?set PROVIDER_ID via direnv}"

      WORKFORCE_LOCATION="''${WORKFORCE_LOCATION:-global}"
      WORKFORCE_PROVIDER="locations/$WORKFORCE_LOCATION/workforcePools/$WORKFORCE_POOL_ID/providers/$PROVIDER_ID"

      GCLOUD_CONFIG_DIR="''${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
      LOGIN_CONFIG_FILE="$GCLOUD_CONFIG_DIR/workforce-login-config.json"

      umask 077
      mkdir -p "$GCLOUD_CONFIG_DIR"

      printf 'Generating login config for %s\n' "$WORKFORCE_PROVIDER"
      gcloud iam workforce-pools create-login-config \
        "$WORKFORCE_PROVIDER" \
        --output-file="$LOGIN_CONFIG_FILE" \
        --activate
      chmod 600 "$LOGIN_CONFIG_FILE"

      gcloud auth login --login-config="$LOGIN_CONFIG_FILE"
      gcloud auth list
    '';
  };
in
{
  home.packages = [
    pkgs.google-cloud-sdk
    gcloudWorkforceAuth
  ];
}
