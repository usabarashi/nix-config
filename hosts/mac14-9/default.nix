{ userName, serialNumber, ... }:
{
  imports = [
    ../../modules/darwin/distrust-emudhra.nix
    ../../modules/darwin/karabiner.nix
    ../../modules/darwin/nix-maintenance.nix
    ../../modules/darwin/nix-settings.nix
    ../../modules/darwin/sleepctl.nix
    ../../modules/darwin/llama-server.nix
    ../../modules/darwin/swiftbar.nix
  ];

  # Restore the device name on activation instead of keeping the numbered name
  # macOS derives on its own (observed as "<serial> (<n>)"). The name is the
  # hardware serial number, which the deploy wrapper reads with ioreg.
  #
  # macOS appends " (N)" to ComputerName when it believes the name is taken on
  # the network; "wake for network access" (sleep/wake + proxied address) is
  # the most commonly reported trigger, so it is disabled here as well.
  # https://apple.stackexchange.com/q/153080 https://apple.stackexchange.com/q/125411
  networking = {
    computerName = serialNumber;
    hostName = serialNumber;
    localHostName = serialNumber;
    wakeOnLan.enable = false;
  };

  # See: https://daiderd.com/nix-darwin/manual/
  system = {
    primaryUser = userName;
    # See: https://github.com/LnL7/nix-darwin/pull/1069
    stateVersion = 5;

    defaults = {
      NSGlobalDomain = {
        AppleICUForce24HourTime = true;
        AppleInterfaceStyle = "Dark";
        ApplePressAndHoldEnabled = false;
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
      };

      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

      dock = {
        appswitcher-all-displays = true;
        autohide = true;
        launchanim = false;
        mru-spaces = false;
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

      screencapture = {
        location = "/Users/${userName}/Desktop";
        target = "file";
      };

      screensaver.askForPassword = true;
    };

    keyboard = {
      enableKeyMapping = true;
    };
  };

  # zsh exports these from /etc/zshenv. They do not reach Finder-launched
  # processes; those keep using the filtered /etc/ssl/cert.pem from
  # distrust-emudhra.nix. PIP_CERT steers the built-in pip off its private
  # root copy. Do not set these on mac14-10: that host points the same
  # variables at the Netskope bundle.
  environment.variables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    PIP_CERT = "/etc/ssl/cert.pem";
  };

  programs.zsh.enable = true;
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };
  time.timeZone = "Asia/Tokyo";
}
