# Chromebook-style updates (adapted from nixbook base.nix):
#  - a few times a day, but only when the last success is 6+ days old and the
#    laptop is on AC: update flake inputs in /etc/nixos, commit the lock, build
#    the new system in the background. It becomes active on the next reboot.
#  - daily: Flatpak updates (flatpak.nix)
#  - garbage collection scaled to free disk space (nixbook channel.sh)
{ pkgs, lib, ... }:

let
  flakeDir = "/etc/nixos";

  notifyUsers = pkgs.writeShellScript "notify-users" ''
    title="$1"
    body="$2"
    for uid in $(${pkgs.systemd}/bin/loginctl list-users --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
      user=$(${pkgs.coreutils}/bin/id -nu "$uid") || continue
      [ -S "/run/user/$uid/bus" ] || continue
      ${pkgs.util-linux}/bin/runuser -u "$user" -- env \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        ${pkgs.libnotify}/bin/notify-send -a "Systeemupdate" "$title" "$body" || true
    done
  '';

  collectGarbage = pkgs.writeShellScript "nixbook-gc" ''
    FREE_GB=$(${pkgs.coreutils}/bin/df -BG --output=avail /nix | ${pkgs.gawk}/bin/awk 'NR==2 { gsub(/G/, "", $1); print $1 }')
    if [ "$FREE_GB" -lt 16 ]; then
      ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 3d
    elif [ "$FREE_GB" -lt 48 ]; then
      ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 14d
    else
      ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 30d
    fi
  '';

  stampFile = "/var/lib/nixbook-upgrade/last-success";

  # Usage: nixbook-upgrade [--if-due]
  #  --if-due (timer): skip when the last successful update is less than 6 days old,
  #  and when offline (tried again the next day instead of failing).
  upgrade = pkgs.writeShellScript "nixbook-upgrade" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.nix
        pkgs.nixos-rebuild
        pkgs.git
        pkgs.coreutils
        pkgs.systemd
        pkgs.curl
      ]
    }:$PATH

    # /sys/class/power_supply/*/online is 1 on mains. No mains device means a desktop.
    on_ac() {
      local f online=0 seen=0
      for f in /sys/class/power_supply/*/online; do
        [ -e "$f" ] || continue
        seen=1
        if [ "$(cat "$f")" = "1" ]; then online=1; fi
      done
      [ "$seen" = 0 ] || [ "$online" = 1 ]
    }

    git_nixbook() {
      git -C ${flakeDir} \
        -c safe.directory=${flakeDir} \
        -c user.name=nixbook \
        -c user.email=nixbook@localhost \
        -c commit.gpgsign=false \
        "$@"
    }

    ensure_git() {
      if [ ! -d ${flakeDir}/.git ]; then
        git_nixbook init
        git_nixbook add -A
        git_nixbook commit -m "Initial nixbook configuration"
      fi
      if [ -n "$(git_nixbook status --porcelain)" ]; then
        git_nixbook add -A
        git_nixbook commit -m "Configuration before upgrade"
      fi
    }

    # A failed build must not leave the new lock as the only copy.
    lock_committed=0
    rollback_lock() {
      if [ "$lock_committed" = 1 ]; then
        git_nixbook revert --no-edit HEAD || true
        lock_committed=0
      else
        git_nixbook checkout -- flake.lock || true
      fi
    }

    if [ "''${1:-}" = "--if-due" ]; then
      if [ -e ${stampFile} ] && [ $(( $(date +%s) - $(stat -c %Y ${stampFile}) )) -lt $((6 * 86400)) ]; then
        echo "Last successful update is less than 6 days old, nothing to do."
        exit 0
      fi
      if ! on_ac; then
        echo "On battery, trying again later."
        exit 0
      fi
      # NetworkManager-wait-online is off, so wait here for up to 5 minutes
      online=0
      for _ in $(seq 30); do
        if curl -fsS --max-time 10 -o /dev/null https://github.com; then online=1; break; fi
        sleep 10
      done
      if [ "$online" = 0 ]; then
        echo "Offline, trying again later."
        exit 0
      fi
    fi

    trap 'rollback_lock; ${notifyUsers} "Update mislukt" "Het systeem is niet bijgewerkt. De flake.lock van voor deze poging is teruggezet. Details: journalctl -u nixbook-upgrade"' ERR
    ${notifyUsers} "Updates worden geïnstalleerd" "Dit gebeurt op de achtergrond, je kunt gewoon doorwerken."
    ensure_git
    nix flake update --flake ${flakeDir}
    if [ -n "$(git_nixbook status --porcelain -- flake.lock)" ]; then
      git_nixbook add flake.lock
      git_nixbook commit -m "flake update $(date +%F)"
      lock_committed=1
    fi
    nixos-rebuild boot --flake ${flakeDir}#nixbook
    lock_committed=0
    trap - ERR
    ${collectGarbage}
    mkdir -p "$(dirname ${stampFile})"
    touch ${stampFile}
    ${notifyUsers} "Updates klaar" "Herstart wanneer het je uitkomt om de updates te gebruiken."
  '';

  # All Flatpak apps, including those installed with Bazaar (nix-flatpak only updates its own)
  flatpakUpdate = scope: ''
    ${pkgs.flatpak}/bin/flatpak update ${scope} -y --noninteractive
    ${pkgs.flatpak}/bin/flatpak uninstall ${scope} --unused -y --noninteractive
  '';

  # Manual "update now" for the app grid (nixbook update.sh / update_shutdown.sh)
  updateNow = pkgs.writeShellScriptBin "nixbook-update" ''
    action="''${1:-reboot}"
    echo "Dit werkt je systeem bij en voert daarna '$action' uit."
    read -r -p "Doorgaan? (j/n): " answer
    case "$answer" in
      [jJyY]*)
        sudo ${upgrade} || { echo "Update mislukt. Druk op Enter."; read -r; exit 1; }
        flatpak update -y --noninteractive
        systemctl "$action"
        ;;
      *) echo "Update geannuleerd." ;;
    esac
  '';

  desktopItem =
    name: desktopName: action:
    pkgs.makeDesktopItem {
      inherit name desktopName;
      exec = "ghostty -e nixbook-update ${action}";
      icon = "system-software-update";
      categories = [
        "System"
        "Utility"
      ];
    };
in
{
  # Several times a day. The script returns without touching the stamp while the
  # last success is under 6 days old, the laptop is on battery, or GitHub is unreachable.
  systemd.services.nixbook-upgrade = {
    description = "Update NixOS (applied on next boot)";
    serviceConfig = {
      Type = "oneshot";
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 19;
    };
    script = "${upgrade} --if-due";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  # Several chances per day. The script itself returns immediately on battery
  # or when the last success is under 6 days old, without moving the stamp,
  # so a missed lunch slot is picked up the next time the laptop is plugged in.
  systemd.timers.nixbook-upgrade = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = [
        "*-*-* 08:00:00"
        "*-*-* 12:00:00"
        "*-*-* 18:00:00"
        "*-*-* 21:00:00"
      ];
      Persistent = true;
      RandomizedDelaySec = "20min";
    };
  };

  systemd.services.nixbook-flatpak-update = {
    description = "Update all Flatpak apps";
    serviceConfig = {
      Type = "oneshot";
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 19;
      Restart = "on-failure";
      RestartSec = "15min";
    };
    unitConfig.StartLimitIntervalSec = 0;
    script = flatpakUpdate "--system";
    after = [
      "network-online.target"
      "flatpak-managed-install.service"
    ];
    wants = [ "network-online.target" ];
  };
  systemd.timers.nixbook-flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      OnBootSec = "15min";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Apps installed per user (`flatpak --user`); a no-op when there are none
  systemd.user.services.nixbook-flatpak-update = {
    description = "Update Flatpak apps installed for this user";
    serviceConfig.Type = "oneshot";
    script = flatpakUpdate "--user";
  };
  systemd.user.timers.nixbook-flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      OnStartupSec = "20min";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  environment.systemPackages = [
    updateNow
    (desktopItem "nixbook-update-reboot" "Bijwerken en herstarten" "reboot")
    (desktopItem "nixbook-update-poweroff" "Bijwerken en afsluiten" "poweroff")
  ];
}
