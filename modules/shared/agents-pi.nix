{
  config,
  pkgs,
  repoPath,
  ...
}:

let
  agentSkills = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/skills";
    force = true;
    recursive = true;
  };
  # Pi calls these "prompt templates"; the shared source directory is
  # config/agents/commands (deployed as ~/.pi/agent/prompts, surfaced as
  # `/name` slash commands).
  agentPrompts = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/commands";
    force = true;
    recursive = true;
  };
  # nix-agent-guard: render the pinned nix path and version stamp INTO the
  # deployed shim (placeholders @NIX_REAL_PATH@ / @NIX_VERSION_STAMP@) so the
  # guard's real binary cannot be repointed through the environment.
  nixGuardShim =
    builtins.replaceStrings
      [ "@NIX_REAL_PATH@" "@NIX_VERSION_STAMP@" ]
      [ "${pkgs.nix}/bin/nix" pkgs.nix.version ]
      (builtins.readFile "${repoPath}/config/agents/scripts/nix-agent-guard.sh");
in
{
  imports = [ ./agents-common.nix ];

  home.packages = [
    # Sandboxed wrapper (Apple Seatbelt + shared cloud-restricted.sb). Node/npm
    # for Pi's package installer is supplied inside that wrapper's PATH only;
    # it is intentionally not a nix-config-wide package.
    pkgs.customPackages.pi-sandboxed
  ];

  # Pi reads user-scoped state from ~/.pi/agent (settings.json, mcp.json,
  # models.json, skills/, prompts/, extensions/, ...). Pi rewrites
  # ~/.pi/agent/settings.json on /settings; the atomic write follows the leaf
  # symlink into this repo, so the managed file is the dotfiles-style source of
  # truth.
  #
  # Inside the sandbox these symlinks resolve into this repo, so the wrapper
  # realpaths each managed input and grants the resolved path; the config files
  # are read-only under the (shared) profile, and Pi's runtime state under
  # ~/.pi/agent (auth.json, sessions, installed packages, logs) is read+write.
  #
  # Provider credentials are NOT managed here: OpenCode Go authenticates with
  # /login opencode-go (or OPENCODE_API_KEY in the environment), ChatGPT Plus
  # with /login openai -> "Sign in with ChatGPT", and Cursor via the
  # @rahularya01/pi-cursor extension with /login cursor (it can also reuse an
  # existing Cursor app/CLI login). Credentials live in agent-owned state
  # (auth.json / Cursor Keychain). Use `pi --no-sandbox` for the one-time
  # browser logins. models.json only declares the local llama.cpp endpoint
  # (llamacpp-local), which Pi does not ship in its catalog.
  home.file = {
    ".pi/agent/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/pi/settings.json";
      force = true;
    };
    ".pi/agent/mcp.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/pi/mcp.json";
      force = true;
    };
    ".pi/agent/models.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/pi/models.json";
      force = true;
    };
    # pi-advisor-flow (Claude-Code-advisor equivalent): executor = OpenCode Go
    # DeepSeek V4.1 Flash, advisor = the frontier GPT.
    ".pi/agent/advisor.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/pi/advisor.json";
      force = true;
    };
    ".pi/agent/prompts" = agentPrompts;
    ".pi/agent/skills" = agentSkills;
    # Pi extensions, auto-discovered from the agent-dir extensions/:
    # notification-sound.ts rings the host bell when control returns to the
    # user; auto-mode.ts adds the `/auto` toggle (Claude Code auto-style);
    # goal.ts adds `/goal` (set/clear a session goal).
    ".pi/agent/extensions" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/pi/extensions";
      force = true;
      recursive = true;
    };
    # Shared Seatbelt profile (same deny-default policy as the claude wrapper).
    ".pi/agent/cloud-restricted.sb" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/cloud-restricted.sb";
      force = true;
    };
    # Free-tier profile for low-trust no-cost providers (`pi --seatbelt
    # free-tier.sb`): separate code path in the wrapper with an isolated
    # runtime root and a sandbox-immutable auth.json.
    ".pi/agent/free-tier.sb" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/free-tier.sb";
      force = true;
    };
    # git-agent-guard: plain-script git deny shim (config/agents/scripts/),
    # deployed as a COPY (store content) so it stays readable inside the
    # sandbox; the wrapper puts ~/.pi/agent/bin first on the sandbox PATH.
    ".pi/agent/bin/git" = {
      text = builtins.readFile "${repoPath}/config/agents/scripts/git-agent-guard.sh";
      executable = true;
    };
    # nix-agent-guard: PATH-first `nix` shim that constrains the workspace
    # flake and options; the pinned nix path/version are rendered at build time.
    ".pi/agent/bin/nix" = {
      text = nixGuardShim;
      executable = true;
    };
  };
}
