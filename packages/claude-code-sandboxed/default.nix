{
  lib,
  stdenv,
  claude-code,
  nodejs,
  runCommand,
  writeShellScriptBin,
}:

let
  # Expose only the `node` binary (no npm/npx/corepack) to the claude-code
  # process tree. Required by the openai-codex plugin's companion scripts,
  # which are executed via `node ${CLAUDE_PLUGIN_ROOT}/scripts/*.mjs`.
  # Omitting npm prevents any `npm install` side effects from the sandbox.
  nodeOnly = runCommand "node-only" { } ''
    mkdir -p $out/bin
    ln -s ${nodejs}/bin/node $out/bin/node
  '';

  sandboxProfilePath = "\${HOME}/.claude/permissive-open.sb";
  errorMessages = {
    profileNotFound = "Error: Sandbox policy not found at ${sandboxProfilePath}";
    installationNote = "Please ensure claude configuration is properly installed.";
  };
  sandboxNotice = "🔒 Running Claude Code with macOS Seatbelt (permissive-open)";

  claudeWrapper = writeShellScriptBin "claude" ''
    # Direct path to claude-code binary
    CLAUDE_BIN="${claude-code}/bin/claude"

    # Expose only `node` to the claude-code process tree (scoped, not a user
    # install). Required by the openai-codex plugin's companion scripts.
    export PATH="${nodeOnly}/bin:$PATH"

    # --no-sandbox: bypass sandbox and execute the binary directly.
    # Useful when invoked from an already-sandboxed context (e.g., Gemini CLI).
    if [ "''${1:-}" = "--no-sandbox" ]; then
        shift
        exec "$CLAUDE_BIN" "$@"
    fi

    # Check if sandbox profile exists
    if [ ! -f "${sandboxProfilePath}" ]; then
        echo "${errorMessages.profileNotFound}" >&2
        echo "${errorMessages.installationNote}" >&2
        exit 1
    fi

    # Show sandbox mode if not using --version or help flags
    case "$*" in
        *--version*|*--help*|*-h*) ;;
        *)
            echo "${sandboxNotice}" >&2
            ;;
    esac

    # Execute claude with sandbox
    exec /usr/bin/sandbox-exec -f "${sandboxProfilePath}" -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" "$CLAUDE_BIN" "$@"
  '';

in
stdenv.mkDerivation {
  pname = "claude-code-sandboxed";
  version = claude-code.version or "1.0.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    ln -s ${claudeWrapper}/bin/claude $out/bin/claude

    runHook postInstall
  '';

  meta = with lib; {
    description = "Sandboxed wrapper for Claude Code CLI";
    longDescription = ''
      A security wrapper that runs claude-code within a macOS sandbox using sandbox-exec
      to restrict file system access for improved security.

      Note: Requires claude-code to be installed separately.
    '';
    license = licenses.mit;
    platforms = platforms.darwin;
    mainProgram = "claude";
  };
}
