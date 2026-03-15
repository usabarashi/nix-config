{ pkgs, ... }:
{
  # Expire home-manager generations (keep only the latest) before GC
  launchd.user.agents.home-manager-cleanup = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.home-manager}/bin/home-manager"
        "expire-generations"
        "now"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0; # Sunday
          Hour = 0;
          Minute = 0;
        }
      ];
      StandardOutPath = "/tmp/home-manager-cleanup.log";
      StandardErrorPath = "/tmp/home-manager-cleanup.log";
    };
  };

  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0; # Sunday
      Hour = 0;
      Minute = 30; # After home-manager cleanup
    };
    options = ""; # Don't delete profile generations; only GC unreferenced store paths
  };

  nix.optimise = {
    automatic = true;
    interval = {
      Weekday = 0; # Sunday
      Hour = 1; # After GC
      Minute = 0;
    };
  };
}
