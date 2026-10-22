_:

let
  getEnvOrThrow =
    var: fallbackMsg:
    let
      value = builtins.getEnv var;
    in
    if value != "" then value else builtins.throw fallbackMsg;

  serialNumber = getEnvOrThrow "SERIAL_NUMBER" "SERIAL_NUMBER environment variable must be set. Please run via `nix run .#<host>` so it is derived from the hardware serial number.";
in
{
  repoPath = getEnvOrThrow "REPOSITORY_PATH" "REPOSITORY_PATH environment variable must be set for multi-user sharing. Please set it to your repository path.";

  currentUser = getEnvOrThrow "CURRENT_USER" "CURRENT_USER environment variable must be set. Please ensure whoami is available.";

  # Used as the device name, and interpolated into shell commands by
  # nix-darwin, so only accept what a `hostName` may contain.
  serialNumber =
    if builtins.match "[A-Za-z0-9]+" serialNumber != null then
      serialNumber
    else
      throw "SERIAL_NUMBER must be alphanumeric (got: ${serialNumber})";
}
