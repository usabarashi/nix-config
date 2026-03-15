{ lib }:

let
  getEnvOrThrow =
    var: fallbackMsg:
    let
      value = builtins.getEnv var;
    in
    if value != "" then value else builtins.throw fallbackMsg;
in
{
  repoPath = getEnvOrThrow "REPOSITORY_PATH" "REPOSITORY_PATH environment variable must be set for multi-user sharing. Please set it to your repository path.";

  currentUser = getEnvOrThrow "CURRENT_USER" "CURRENT_USER environment variable must be set. Please ensure whoami is available.";
}
