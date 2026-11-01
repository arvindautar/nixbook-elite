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

  notifyUsers = import ./notify-users.nix { inherit pkgs; };

  # A phone's hotspot. Updates can be gigabytes, they wait for a normal network.
  # 1 is yes, 3 is NetworkManager's guess, and no answer means not metered.
  metered = pkgs.writeShellScript "nixbook-metered" ''
    case "$(${pkgs.systemd}/bin/busctl get-property org.freedesktop.NetworkManager \
      /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered 2>/dev/null)" in
      "u 1" | "u 3") exit 0 ;;
    esac
    exit 1
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
  systemProfile = "/nix/var/nix/profiles/system";

  # nixbook-upgrade [--if-due]
  # --if-due is what the timer uses: do nothing if the last update is less
  # than 6 days old, or we're on battery, offline or on a metered network.
  upgrade = pkgs.writeShellScript "nixbook-upgrade" ''
    # -E so the ERR trap also fires inside functions
    set -Eeu
    export PATH=${
      lib.makeBinPath [
        pkgs.nix
        pkgs.nixos-rebuild
        pkgs.git
        pkgs.coreutils
        pkgs.findutils
        pkgs.systemd
        pkgs.curl
        pkgs.util-linux
      ]
    }:$PATH

    # The timer and the update tiles must not run at the same time. The timer
    # steps aside, a tile waits.
    exec 8>/run/nixbook-upgrade.lock
    if [ "''${1:-}" = "--if-due" ]; then
      flock -n 8 || exit 0
    else
      flock 8
    fi

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

    # nixos-rebuild moves the profile before it installs the boot loader. If
    # that fails nothing new can boot, so drop the generation again.
    restore_profile() {
      local now
      now=$(readlink ${systemProfile})
      [ "$now" != "$1" ] || return 0
      ln -sfn "$1" ${systemProfile}
      rm -f "$(dirname ${systemProfile})/$now"
    }

    # try_update [input...]: update these inputs (all without any) and build
    # the system for the next boot. Puts the old lock back if that fails.
    # Called from `if`, so set -e is off in here and every step is checked.
    try_update() {
      local committed=0 profile
      profile=$(readlink ${systemProfile})
      if ! nix flake update --flake ${flakeDir} "$@"; then
        git_nixbook checkout -- flake.lock || true
        return 1
      fi
      if [ -n "$(git_nixbook status --porcelain -- flake.lock)" ]; then
        if ! git_nixbook add flake.lock ||
          ! git_nixbook commit -m "flake update $(date +%F)''${1:+ ($*)}"; then
          git_nixbook checkout -- flake.lock || true
          return 1
        fi
        committed=1
      fi
      if ! nixos-rebuild boot --flake ${flakeDir}#nixbook; then
        restore_profile "$profile"
        if [ "$committed" = 1 ]; then
          git_nixbook revert --no-edit HEAD || true
        else
          git_nixbook checkout -- flake.lock || true
        fi
        return 1
      fi
    }

    # The timer retries a failed update a few times a day. Tell the user once
    # a day, not every time.
    failStamp=/var/lib/nixbook-upgrade/last-failure-notice
    quiet=0
    if [ "''${1:-}" = "--if-due" ] && [ -n "$(find "$failStamp" -mmin -1440 2>/dev/null)" ]; then
      quiet=1
    fi
    notify() { [ "$quiet" = 1 ] || ${notifyUsers} "$@"; }
    fail() {
      notify "Update mislukt" "Het systeem is niet bijgewerkt en blijft zoals het was. Details: journalctl -u nixbook-upgrade"
      mkdir -p "$(dirname "$failStamp")"
      touch "$failStamp"
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
      if ${metered}; then
        echo "On a metered network, trying again later."
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

    trap fail ERR
    notify "Updates worden geïnstalleerd" "Dit gebeurt op de achtergrond, je kunt gewoon doorwerken."
    ensure_git
    # nixos-unstable (AI CLIs, Bazaar, NordVPN, extensions) can break the
    # build. Then still take the stable NixOS updates, they carry the
    # security fixes. The rest is tried again with the next update.
    if try_update; then
      done_msg="Herstart wanneer het je uitkomt om de updates te gebruiken."
    elif try_update nixpkgs; then
      done_msg="Herstart wanneer het je uitkomt om de updates te gebruiken. Een paar apps uit nixos-unstable zijn nog niet bijgewerkt, dat gebeurt bij de volgende update."
    else
      trap - ERR
      fail
      exit 1
    fi
    trap - ERR
    rm -f "$failStamp"
    # Neither of these is a reason to run the whole update again.
    ${collectGarbage} || true
    # Take the generations that were just removed out of the boot menu, their
    # entries can't start anymore.
    ${systemProfile}/bin/switch-to-configuration boot || true
    mkdir -p "$(dirname ${stampFile})"
    touch ${stampFile}
    ${notifyUsers} "Updates klaar" "$done_msg"
  '';

  # nix-flatpak only updates its own apps, this also covers Bazaar installs
  flatpakUpdate = scope: ''
    ${pkgs.flatpak}/bin/flatpak update ${scope} -y --noninteractive
    ${pkgs.flatpak}/bin/flatpak uninstall ${scope} --unused -y --noninteractive
  '';

  # Running apps keep the old version until restarted, so tell the user.
  flatpakSystemUpdate = ''
    if ${metered}; then
      echo "On a metered network, trying again later."
      exit 0
    fi
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
    latest=$(readlink -f ${systemProfile})
    [ "$booted" != "$latest" ] || exit 0
    # Out of boot tries: systemd-boot went back to an older generation and a
    # reboot won't help. The next update gets three new tries.
    gen=$(readlink ${systemProfile})
    gen=''${gen#system-}
    gen=''${gen%-link}
    for entry in /boot/EFI/Linux/nixos-generation-"$gen"-*+0-*.efi; do
      if [ -e "$entry" ]; then
        echo "Generation $gen is out of boot tries."
        ${notifyUsers} "Update startte niet" "De laatste update startte niet op, daarom draait de vorige versie nog. Je kunt gewoon doorwerken, de volgende update probeert het opnieuw."
        exit 0
      fi
    done
    age=$(( $(date +%s) - $(stat -c %Y ${systemProfile}) ))
    [ "$age" -ge $((3 * 86400)) ] || exit 0
    ${notifyUsers} "Herstart nodig" "Er staat al $((age / 86400)) dagen een update klaar. Herstart om de beveiligingsupdates te gebruiken."
  '';

  # One sudo for both: a long build outlasts its timeout, and the tile would
  # then sit at a password prompt with nobody watching.
  updateAsRoot = pkgs.writeShellScript "nixbook-update-root" ''
    ${upgrade} || exit 1
    echo "Firmware bijwerken (BIOS en apparaten, via LVFS)..."
    ${firmwareUpdate} || exit 2
  '';

  # "update now" tiles, like nixbook's update.sh / update_shutdown.sh
  updateNow = pkgs.writeShellScriptBin "nixbook-update" ''
    action="''${1:-reboot}"
    echo "Dit werkt je systeem bij en voert daarna '$action' uit."
    read -r -p "Doorgaan? (j/n): " answer
    case "$answer" in
      [jJyY]*)
        rc=0
        sudo ${updateAsRoot} || rc=$?
        case "$rc" in
          0) ;;
          2) echo "Firmware-update mislukt; het systeem is wel bijgewerkt. Druk op Enter."; read -r ;;
          *) echo "Update mislukt. Druk op Enter."; read -r; exit 1 ;;
        esac
        flatpak update -y --noninteractive
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
      # a stuck download would otherwise block every later update
      TimeoutStartSec = "3h";
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
      TimeoutStartSec = "1h";
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
    script = ''
      if ${metered}; then
        exit 0
      fi
      ${flatpakUpdate "--user"}
    '';
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
