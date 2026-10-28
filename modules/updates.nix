# Automatic updates, roughly like nixbook's:
# - system: flake update + `nixos-rebuild boot`, at most every 6 days, only on AC
# - flatpaks every 4 hours
# - firmware from LVFS, installed by the update tiles
# - reboot reminder after 3 days
# - gc based on free disk space (nixbook's channel.sh)
{
  config,
  pkgs,
  lib,
  ...
}:

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

  # nixbook-upgrade [--if-due]
  # --if-due is what the timer uses: do nothing if the last update is less
  # than 6 days old, or we're on battery or offline.
  upgrade = pkgs.writeShellScript "nixbook-upgrade" ''
    # -E so the ERR trap also fires inside functions
    set -Eeu
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

    # online is 1 on mains. No power supply at all means a desktop.
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

    # if the build fails, put the old lock back
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
      # NetworkManager-wait-online is disabled, so wait up to 5 min ourselves
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

  # nix-flatpak only updates its own apps, this also covers Bazaar installs
  flatpakUpdate = scope: ''
    ${pkgs.flatpak}/bin/flatpak update ${scope} -y --noninteractive
    ${pkgs.flatpak}/bin/flatpak uninstall ${scope} --unused -y --noninteractive
  '';

  # Running apps keep the old version until restarted, so tell the user.
  flatpakSystemUpdate = ''
    apps() { ${pkgs.flatpak}/bin/flatpak list --system --app --columns=application,active,name | sort; }
    before=$(apps)
    ${flatpakUpdate "--system"}
    after=$(apps)
    changed=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | cut -f1 | sort -u)
    [ -n "$changed" ] || exit 0
    for uid in $(${pkgs.systemd}/bin/loginctl list-users --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
      user=$(id -nu "$uid") || continue
      [ -S "/run/user/$uid/bus" ] || continue
      as_user() {
        ${pkgs.util-linux}/bin/runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
      }
      running=$(as_user ${pkgs.flatpak}/bin/flatpak ps --columns=application | sort -u)
      for app in $(comm -12 <(printf '%s\n' "$changed") <(printf '%s\n' "$running")); do
        name=$(${pkgs.gawk}/bin/awk -F'\t' -v a="$app" '$1 == a { print $3 }' <<< "$after")
        as_user ${pkgs.libnotify}/bin/notify-send -a "Systeemupdate" "$name is bijgewerkt" \
          "Sluit $name en open het opnieuw om de update te gebruiken." || true
      done
    done
  '';

  fwupdmgr = "${config.services.fwupd.package}/bin/fwupdmgr";

  # BIOS updates get staged and applied on the next boot.
  # --no-unreported-check so fwupdmgr never asks to upload a report.
  # Exit code 2 means nothing to do.
  firmwareUpdate = pkgs.writeShellScript "nixbook-firmware-update" ''
    ${fwupdmgr} refresh >/dev/null 2>&1 || true
    rc=0
    ${fwupdmgr} update --assume-yes --no-reboot-check --no-unreported-check || rc=$?
    [ "$rc" = 0 ] || [ "$rc" = 2 ]
  '';

  # Runs after fwupd-refresh. get-updates also exits 0 with an empty list
  # (fwupd 2.1.4), so count the releases instead. Notify once per set.
  firmwareCheck = pkgs.writeShellScript "nixbook-firmware-check" ''
    set -eu
    stamp=/var/lib/nixbook-upgrade/firmware-notified
    json=$(${fwupdmgr} get-updates --json --no-unreported-check 2>/dev/null) || true
    updates=$(printf '%s' "$json" |
      ${pkgs.jq}/bin/jq -r '.Devices[]? | .Name as $n | .Releases[]? | "\($n) \(.Version)"' 2>/dev/null |
      sort -u) || updates=
    if [ -z "$updates" ]; then
      rm -f "$stamp"
      exit 0
    fi
    [ "$(cat "$stamp" 2>/dev/null)" != "$updates" ] || exit 0
    ${notifyUsers} "Firmware-update beschikbaar" "$(printf '%s\n' "$updates" | head -3)
    Sluit de lader aan en kies 'Bijwerken en herstarten' in het app-overzicht."
    mkdir -p "$(dirname "$stamp")"
    printf '%s\n' "$updates" > "$stamp"
  '';

  # `nixos-rebuild boot` needs a reboot to take effect
  rebootReminder = pkgs.writeShellScript "nixbook-reboot-reminder" ''
    set -eu
    booted=$(readlink -f /run/booted-system)
    latest=$(readlink -f /nix/var/nix/profiles/system)
    [ "$booted" != "$latest" ] || exit 0
    age=$(( $(date +%s) - $(stat -c %Y /nix/var/nix/profiles/system) ))
    [ "$age" -ge $((3 * 86400)) ] || exit 0
    ${notifyUsers} "Herstart nodig" "Er staat al $((age / 86400)) dagen een update klaar. Herstart om de beveiligingsupdates te gebruiken."
  '';

  # "update now" tiles, like nixbook's update.sh / update_shutdown.sh
  updateNow = pkgs.writeShellScriptBin "nixbook-update" ''
    action="''${1:-reboot}"
    echo "Dit werkt je systeem bij en voert daarna '$action' uit."
    read -r -p "Doorgaan? (j/n): " answer
    case "$answer" in
      [jJyY]*)
        sudo ${upgrade} || { echo "Update mislukt. Druk op Enter."; read -r; exit 1; }
        flatpak update -y --noninteractive
        echo "Firmware bijwerken (BIOS en apparaten, via LVFS)..."
        sudo ${firmwareUpdate} || { echo "Firmware-update mislukt; het systeem is wel bijgewerkt. Druk op Enter."; read -r; }
        systemctl "$action"
        ;;
      *) echo "Update geannuleerd." ;;
    esac
  '';

  # Adwaita 50 has no system-software-update icon anymore, ship our own
  desktopItem =
    name: desktopName: action: iconFile:
    pkgs.symlinkJoin {
      name = "${name}-desktop";
      paths = [
        (pkgs.makeDesktopItem {
          inherit name desktopName;
          exec = "ghostty -e nixbook-update ${action}";
          icon = name;
          categories = [
            "System"
            "Utility"
          ];
          keywords = [
            "update"
            "bijwerken"
            "nixbook"
          ];
        })
      ];
      postBuild = ''
        mkdir -p $out/share/icons/hicolor/scalable/apps
        cp ${iconFile} $out/share/icons/hicolor/scalable/apps/${name}.svg
      '';
    };
in
{
  # Cheap to run often, the script exits early when no update is due.
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

  # Several slots so a missed one gets picked up the next time we're on AC.
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

  systemd.services.nixbook-firmware-check = {
    description = "Tell users about firmware updates from LVFS";
    after = [ "fwupd-refresh.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = firmwareCheck;
      StandardInput = "null";
    };
  };
  systemd.timers.nixbook-firmware-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 11:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  systemd.services.nixbook-reboot-reminder = {
    description = "Remind users to restart for an installed update";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = rebootReminder;
    };
  };
  systemd.timers.nixbook-reboot-reminder = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 10:00:00";
      Persistent = true;
      RandomizedDelaySec = "30min";
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
    script = flatpakSystemUpdate;
    after = [
      "network-online.target"
      "flatpak-managed-install.service"
    ];
    wants = [ "network-online.target" ];
  };
  # Browser fixes hit Flathub within hours. When nothing changed this only
  # fetches the repo summary.
  systemd.timers.nixbook-flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "00/4:00";
      OnBootSec = "15min";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # `flatpak --user` installs, usually there are none
  systemd.user.services.nixbook-flatpak-update = {
    description = "Update Flatpak apps installed for this user";
    serviceConfig.Type = "oneshot";
    script = flatpakUpdate "--user";
  };
  systemd.user.timers.nixbook-flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "00/4:00";
      OnStartupSec = "20min";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  environment.systemPackages = [
    updateNow
    (desktopItem "nixbook-update-reboot" "Bijwerken en herstarten" "reboot"
      ./icons/nixbook-update-reboot.svg
    )
    (desktopItem "nixbook-update-poweroff" "Bijwerken en afsluiten" "poweroff"
      ./icons/nixbook-update-poweroff.svg
    )
  ];
}
