{ pkgs, homeDirectory, ... }:

{
  launchd.user.agents.swiftbar = {
    serviceConfig = {
      ProgramArguments = [
        "${homeDirectory}/Applications/Home Manager Apps/SwiftBar.app/Contents/MacOS/SwiftBar"
      ];
      # Start at login
      RunAtLoad = true;
      # Do not auto-restart on quit (user may want to explicitly stop it)
      KeepAlive = false;
      # Limit to GUI session (not SSH)
      LimitLoadToSessionType = "Aqua";
      ThrottleInterval = 10;
      StandardOutPath = "${homeDirectory}/Library/Logs/swiftbar/stdout.log";
      StandardErrorPath = "${homeDirectory}/Library/Logs/swiftbar/stderr.log";
    };
  };
}
