{
  pkgs,
  config,
  userName,
  homeDirectory,
  ...
}:

{
  programs.home-manager.enable = true;
  home = {
    username = userName;
    inherit homeDirectory;
    stateVersion = "25.11";

    activation.createOllamaLogDir = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${homeDirectory}/Library/Logs/ollama"
    '';
  };

  targets.darwin.copyApps = {
    enable = true;
    enableChecks = true;
  };

  home.packages = with pkgs; [
    discord
    iina
    ollama
    ripgrep
    slack
    zoom-us
  ];

  launchd.agents.ollama = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.ollama}/bin/ollama"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${homeDirectory}/Library/Logs/ollama/stdout.log";
      StandardErrorPath = "${homeDirectory}/Library/Logs/ollama/stderr.log";
      EnvironmentVariables = {
        OLLAMA_HOST = "127.0.0.1:11434";
        OLLAMA_KEEP_ALIVE = "5m";
        OLLAMA_MAX_LOADED_MODELS = "1";
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
      };
    };
  };

  # Weekly truncate of Ollama logs (launchd has no built-in rotation).
  launchd.agents.ollama-log-rotate = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          for f in "${homeDirectory}/Library/Logs/ollama/"*.log; do
            [ -f "$f" ] || continue
            size=$(/usr/bin/stat -f%z "$f" 2>/dev/null || echo 0)
            [ "$size" -gt 52428800 ] && : > "$f"
          done
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 2;
          Minute = 0;
        }
      ];
      StandardOutPath = "/dev/null";
      StandardErrorPath = "/dev/null";
    };
  };

  imports = [
    ../../modules/darwin/karabiner.nix
    ../../modules/shared/agents.nix
    ../../modules/shared/extra.nix
    ../../modules/shared/git.nix
    ../../modules/shared/neovim.nix
    ../../modules/shared/ssh.nix
    ../../modules/shared/terminal.nix
    ../../modules/shared/terraform.nix
    ../../modules/shared/vscode.nix
  ];
}
