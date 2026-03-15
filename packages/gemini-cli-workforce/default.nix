{
  lib,
  stdenv,
  gemini-cli,
  google-cloud-sdk,
  writeShellScriptBin,
}:

let
  globalLocation = "global";
  geminiWrapper = writeShellScriptBin "gemini" ''
    GEMINI_BIN="${gemini-cli}/bin/gemini"
    GCLOUD_BIN_DIR="${google-cloud-sdk}/bin"
    GCLOUD_BIN="$GCLOUD_BIN_DIR/gcloud"
    export PATH="$GCLOUD_BIN_DIR:$PATH"
    export GOOGLE_CLOUD_LOCATION="${globalLocation}"
    export GOOGLE_GENAI_USE_VERTEXAI="true"
    unset GOOGLE_API_KEY GEMINI_API_KEY
    CRED_PATH=""

    ensure_gcloud_login() {
      if [ -n "''${GOOGLE_WIF_LOGIN_CONFIG:-}" ]; then
        if [ ! -f "$GOOGLE_WIF_LOGIN_CONFIG" ]; then
          echo "Error: GOOGLE_WIF_LOGIN_CONFIG not found: $GOOGLE_WIF_LOGIN_CONFIG" >&2
          exit 1
        fi
        if ! "$GCLOUD_BIN" auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | grep -q .; then
          "$GCLOUD_BIN" auth login --login-config="$GOOGLE_WIF_LOGIN_CONFIG"
        fi
      fi
    }

    ensure_adc() {
      if [ ! -x "$GCLOUD_BIN" ]; then
        echo "Error: gcloud is required to create/refresh Application Default Credentials." >&2
        exit 1
      fi

      if [ -f "$CRED_PATH" ]; then
        if "$GCLOUD_BIN" auth application-default print-access-token >/dev/null 2>&1; then
          return 0
        fi
      fi

      ensure_gcloud_login
      if [ -n "''${GOOGLE_WIF_LOGIN_CONFIG:-}" ]; then
        "$GCLOUD_BIN" auth application-default login --login-config="$GOOGLE_WIF_LOGIN_CONFIG"
      else
        "$GCLOUD_BIN" auth application-default login
      fi
    }

    DEFAULT_ADC_PATH="$HOME/.config/gcloud/application_default_credentials.json"
    if [ -n "''${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
      # Explicit credentials: allow service_account in addition to federated types
      CRED_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
      if [ ! -f "$CRED_PATH" ]; then
        echo "Error: GOOGLE_APPLICATION_CREDENTIALS not found: $CRED_PATH" >&2
        exit 1
      fi
      if ! grep -Eq '"type"[[:space:]]*:[[:space:]]*"(external_account|authorized_user|external_account_authorized_user|service_account)"' "$CRED_PATH" 2>/dev/null; then
        echo "Error: GOOGLE_APPLICATION_CREDENTIALS must be external_account, authorized_user, external_account_authorized_user, or service_account." >&2
        exit 1
      fi
    else
      # Default ADC: reject service_account keys to prevent accidental long-lived key usage
      CRED_PATH="$DEFAULT_ADC_PATH"
      export GOOGLE_APPLICATION_CREDENTIALS="$CRED_PATH"
      ensure_adc
      if ! grep -Eq '"type"[[:space:]]*:[[:space:]]*"(external_account|authorized_user|external_account_authorized_user)"' "$CRED_PATH" 2>/dev/null; then
        echo "Error: ADC must be external_account, authorized_user, or external_account_authorized_user." >&2
        exit 1
      fi
    fi

    if [ -z "''${GOOGLE_CLOUD_PROJECT:-}" ]; then
      echo "Error: GOOGLE_CLOUD_PROJECT must be set for Vertex AI." >&2
      exit 1
    fi

    exec "$GEMINI_BIN" "$@"
  '';
in
stdenv.mkDerivation {
  pname = "gemini-cli-workforce";
  version = gemini-cli.version;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    ln -s ${geminiWrapper}/bin/gemini $out/bin/gemini

    runHook postInstall
  '';

  meta = with lib; {
    description = "Gemini CLI wrapper with Workforce Identity Federation auth that forces Vertex AI location to global";
    license = licenses.mit;
    platforms = platforms.darwin;
    mainProgram = "gemini";
  };
}
