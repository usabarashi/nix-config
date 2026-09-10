{
  config,
  pkgs,
  repoPath,
  flakeInputs,
  ...
}:

let
  # Claude-specific (unlike the config/agents/* bindings below), mirrors how
  # CLAUDE.md and settings.json are sourced from config/claude/ in this file.
  claudeAgents = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/agents";
    force = true;
    recursive = true;
  };
  agentScripts = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/scripts";
    force = true;
    recursive = true;
  };
  # Scripts invoked directly by settings.json hooks (deny-check.sh, notify.sh)
  # are copied into a SEPARATE, previously-nonexistent directory rather than
  # symlinked into .claude/scripts: a background/forked Claude session scoped
  # to a project other than this repo cannot follow a symlink that escapes
  # into this repo (same rationale as the git/nix guard shims below, and
  # documented in git-agent-guard.sh's header). This must be a new path, not
  # a restructuring of .claude/scripts itself: switching an existing
  # directory-symlink entry to per-file entries makes Home Manager's
  # conflict/backup handling treat the live repo file (reached through the
  # not-yet-torn-down old symlink) as a colliding pre-existing file, and it
  # gets renamed to *.backup and replaced by a store symlink -- corrupting
  # the repository's working tree. A brand-new directory has no prior state
  # to collide with.
  agentHookScripts = {
    ".claude/hooks/deny-check.sh" = {
      text = builtins.readFile "${repoPath}/config/agents/scripts/deny-check.sh";
      executable = true;
    };
    ".claude/hooks/notify.sh" = {
      text = builtins.readFile "${repoPath}/config/agents/scripts/notify.sh";
      executable = true;
    };
  };
  agentSkills = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/skills";
    force = true;
    recursive = true;
  };
  agentCommands = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/commands";
    force = true;
    recursive = true;
  };
  # Only cloud-restricted.sb is made available to the claude wrapper (it is the
  # shared default for both agents). Other profiles in config/agents (free-tier)
  # require opencode-specific wrapper env/params and must not be selectable or
  # advertised by `claude --list-seatbelts`.
  seatbeltProfileNames = [ "cloud-restricted.sb" ];
  seatbeltProfiles = builtins.listToAttrs (
    map (name: {
      name = ".claude/${name}";
      value = {
        source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/agents/${name}";
        force = true;
      };
    }) seatbeltProfileNames
  );
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
    # Used by config/agents/scripts/notify.sh (copied into .claude/hooks).
    # customPackages override: nixpkgs ships Intel-only zip, this builds arm64 from source.
    pkgs.customPackages.terminal-notifier
    # MCP server launched via ~/.claude.json (not Nix-managed); only Claude
    # Code wires serena as an MCP server, so it is owned here.
    flakeInputs.serena
    pkgs.customPackages.claude-code-sandboxed
  ];

  home.file = {
    ".claude/CLAUDE.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/CLAUDE.md";
      force = true;
    };
    ".claude/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/claude/settings.json";
      force = true;
    };
    ".claude/agents" = claudeAgents;
    ".claude/commands" = agentCommands;
    ".claude/scripts" = agentScripts;
    ".claude/skills" = agentSkills;
    # git-agent-guard: plain-script git deny shim (config/agents/scripts/),
    # copied here because ~/.claude is the tree the cloud-restricted seatbelt
    # grants the claude session. See agents-opencode.nix for the rationale.
    ".claude/bin/git" = {
      text = builtins.readFile "${repoPath}/config/agents/scripts/git-agent-guard.sh";
      executable = true;
    };
    # nix-agent-guard: same deployment rationale and position as the git shim;
    # the pinned nix path/version are rendered into it at eval time.
    ".claude/bin/nix" = {
      text = nixGuardShim;
      executable = true;
    };
  }
  // agentHookScripts
  // seatbeltProfiles;
}
