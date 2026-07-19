{ pkgs, userName, ... }:

let
  # Background daemon that monitors Caps Lock state via ioreg and sets
  # pmset disablesleep accordingly. When sleep prevention is active,
  # it also watches the lid state and turns off the internal display
  # on lid-close (since macOS keeps it on when disablesleep=1).
  #   Caps Lock ON  (LED lit)   → disablesleep = 1 (sleep prevention)
  #   Caps Lock OFF (LED off)   → disablesleep = 0 (normal sleep)
  daemon = pkgs.writeShellScript "sleepctl-daemon" ''
    set -u
    last_capslock=""
    lid_fired=0

    # Read initial state once; track it locally to avoid polling pmset -g
    # every 250ms in the loop below.
    sleep_disabled=$(/usr/bin/pmset -g \
      | /usr/bin/awk '$1 == "SleepDisabled" { print $2; exit }')
    [ "$sleep_disabled" = "1" ] || sleep_disabled=0

    while :; do
      # ---- Caps Lock polling ----
      # Read HIDCapsLockState from IOHIDSystem (returns Yes/No or true/false).
      # This reflects the physical toggle state of the Caps Lock key.
      capslock=$(/usr/sbin/ioreg -n IOHIDSystem -r \
        | /usr/bin/awk -F' = ' '/HIDCapsLockState/{gsub(/[^a-zA-Z]/,"",$2); print $2; exit}')

      if [ -n "$capslock" ] && [ "$capslock" != "$last_capslock" ]; then
        if [ "$capslock" = "Yes" ] || [ "$capslock" = "true" ]; then
          /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1 \
            && { /usr/bin/logger -t sleepctl-daemon "disablesleep=1 (caps lock on)"; sleep_disabled=1; } \
            || /usr/bin/logger -t sleepctl-daemon "ERROR: pmset disablesleep 1 failed"
        else
          /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 \
            && { /usr/bin/logger -t sleepctl-daemon "disablesleep=0 (caps lock off)"; sleep_disabled=0; } \
            || /usr/bin/logger -t sleepctl-daemon "ERROR: pmset disablesleep 0 failed"
        fi
        last_capslock="$capslock"
      fi

      # ---- Lid-closed display sleep ----
      # Uses local sleep_disabled variable instead of polling pmset -g
      # each iteration. Since this daemon is the sole controller of
      # disablesleep, the variable stays in sync. Only when Caps Lock
      # is toggled externally would it drift — unlikely in practice.
      if [ "$sleep_disabled" = "1" ]; then
        state=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 \
          | /usr/bin/awk -F' = ' '$1 ~ /"AppleClamshellState"$/ { gsub(/[^a-zA-Z]/,"",$2); print $2; exit }')

        if [ "$state" = "Yes" ] || [ "$state" = "true" ]; then
          if [ "$lid_fired" = "0" ]; then
            /usr/bin/pmset displaysleepnow \
              && /usr/bin/logger -t sleepctl-daemon "display sleep (lid closed)" \
              || /usr/bin/logger -t sleepctl-daemon "ERROR: pmset displaysleepnow failed"
            lid_fired=1
          fi
        else
          lid_fired=0
        fi
      else
        lid_fired=0
      fi

      /bin/sleep 0.25
    done
  '';

  # Read-only CLI to check current disablesleep status from anywhere
  # (not just zsh), since the physical Caps Lock key is the only
  # control surface. Use -v or --verbose to show raw ioreg values.
  sleepctlCmd = pkgs.writeShellScriptBin "sleepctl" ''
    verbose=0
    action=""

    while [ $# -gt 0 ]; do
      case "$1" in
        -v|--verbose)
          verbose=1
          ;;
        status)
          action="status"
          ;;
        *)
          echo "usage: sleepctl status [-v|--verbose]" >&2
          exit 1
          ;;
      esac
      shift
    done

    if [ "$action" != "status" ]; then
      echo "usage: sleepctl status [-v|--verbose]" >&2
      exit 1
    fi

    disabled=$(/usr/bin/pmset -g | /usr/bin/awk "\$1 == \"SleepDisabled\" { print \$2; exit }")
    if [ "$disabled" = "1" ]; then
      echo "on"
    else
      echo "off"
    fi

    if [ "$verbose" = "1" ]; then
      capslock=$(/usr/sbin/ioreg -n IOHIDSystem -r \
        | /usr/bin/awk -F" = " "/HIDCapsLockState/{gsub(/[^a-zA-Z]/,\"\",\$2); print \$2; exit}")
      clamshell=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 \
        | /usr/bin/awk -F" = " "\$1 ~ /\"AppleClamshellState\"\$/ { gsub(/[^a-zA-Z]/,\"\",\$2); print \$2; exit }")
      echo "capslock_raw: $capslock"
      echo "clamshell_raw: $clamshell"
    fi
  '';
in
{
  # Install the sleepctl CLI into system PATH (available to all shells).
  environment.systemPackages = [ sleepctlCmd ];

  # Passwordless sudo for the daemon's pmset disablesleep commands.
  # Arguments are restricted to exact matches for disablesleep 1/0 only.
  security.sudo.extraConfig = ''
    ${userName} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
  '';

  launchd.user.agents.sleepctl-daemon = {
    serviceConfig = {
      ProgramArguments = [ "${daemon}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
    };
  };
}
