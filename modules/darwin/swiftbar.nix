{ homeDirectory, ... }:

{
  launchd.user.agents.swiftbar = {
    serviceConfig = {
      ProgramArguments = [
        "${homeDirectory}/Applications/Home Manager Apps/SwiftBar.app/Contents/MacOS/SwiftBar"
      ];
      # Start at login
      RunAtLoad = true;
      # Auto-restart if it exits. Without this, `nix run .#mac14-9` (which
      # reloads the LaunchAgent) leaves SwiftBar stopped until the next login,
      # because the activation terminates the running app.
      # Trade-off: quitting from the menu bar is no longer persistent; use
      # `launchctl bootout gui/$(id -u)/org.nixos.swiftbar` to stop it for good.
      KeepAlive = true;
      # Limit to GUI session (not SSH)
      LimitLoadToSessionType = "Aqua";
      ThrottleInterval = 10;
      StandardOutPath = "${homeDirectory}/Library/Logs/swiftbar/stdout.log";
      StandardErrorPath = "${homeDirectory}/Library/Logs/swiftbar/stderr.log";
    };
  };
}
