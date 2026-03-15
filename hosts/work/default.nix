{ userName, ... }:
{
  imports = [
    ../../modules/darwin/netskope-ssl.nix
    ../../modules/darwin/nix-maintenance.nix
    ../../modules/darwin/nix-settings.nix
  ];

  # See: https://daiderd.com/nix-darwin/manual/
  system = {
    primaryUser = userName;
    # See: https://github.com/LnL7/nix-darwin/pull/1069
    stateVersion = 5;

    defaults = {
      NSGlobalDomain = {
        AppleICUForce24HourTime = true;
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        NSAutomaticCapitalizationEnabled = false;
      };

      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

      dock = {
        autohide = true;
        launchanim = false;
        wvous-bl-corner = 1; # Disabled
        wvous-br-corner = 4; # Desktop
        wvous-tl-corner = 1; # Disabled
        wvous-tr-corner = 6; # Disable Screen Saver
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        FXDefaultSearchScope = "SCcf";
        ShowPathbar = true;
        _FXShowPosixPathInTitle = true;
      };

      menuExtraClock = {
        Show24Hour = true;
        ShowDate = 0; # Show the date
        ShowSeconds = true;
      };

      screensaver.askForPassword = true;
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };
  };

  programs.zsh.enable = true;
  security.pam.services.sudo_local.touchIdAuth = true;
  time.timeZone = "Asia/Tokyo";
}
