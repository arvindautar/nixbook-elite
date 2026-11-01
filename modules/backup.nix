# btrfs snapshots on the SSD itself (for undo, not for a dead disk), and
# restic to a disk labeled NIXBACKUP whenever one is plugged in.
{ pkgs, ... }:

let
  notifyUsers = import ./notify-users.nix { inherit pkgs; };

  snapshot = pkgs.writeShellScript "nixbook-snapshot" ''
    set -euo pipefail
    stamp=$(date +%F-%H%M)
    mkdir -p /.snapshots
    chmod 700 /.snapshots
    ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /home "/.snapshots/home-$stamp"
    ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r / "/.snapshots/root-$stamp"
    # Snapshots keep deleted files on the disk. Space comes first when it's
    # nearly full, same limit as the first step of nixbook-gc.
    keepHome=14
    keepRoot=7
    free=$(df -BG --output=avail / | ${pkgs.gawk}/bin/awk 'NR==2 { gsub(/G/, "", $1); print $1 }')
    if [ "$free" -lt 16 ]; then
      keepHome=3
      keepRoot=3
    fi
    # nested subvolumes aren't included, so no recursion
    cd /.snapshots
    ls -1d home-* 2>/dev/null | sort | head -n -"$keepHome" | while read -r old; do
      ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/.snapshots/$old"
    done
    ls -1d root-* 2>/dev/null | sort | head -n -"$keepRoot" | while read -r old; do
      ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/.snapshots/$old"
    done
  '';

  backupHome = pkgs.writeShellScriptBin "nixbook-backup-home" ''
    set -euo pipefail
    [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
    label=NIXBACKUP
    mnt=/mnt/nixbackup
    state=/var/lib/nixbook-backup
    # the timer steps aside, running it by hand waits
    exec 9>/run/nixbook-backup-home.lock
    if [ "''${1:-}" = "--if-present" ]; then
      ${pkgs.util-linux}/bin/flock -n 9 || exit 0
    else
      ${pkgs.util-linux}/bin/flock 9
    fi
    dev=$(${pkgs.util-linux}/bin/blkid -L "$label" || true)
    if [ -z "$dev" ]; then
      if [ "''${1:-}" = "--if-present" ]; then
        # a disk that stays in a drawer protects nothing, ask once a week
        if [ -n "$(${pkgs.findutils}/bin/find "$state/last-success" -mtime +13 2>/dev/null)" ] &&
          [ -z "$(${pkgs.findutils}/bin/find "$state/last-reminder" -mtime -7 2>/dev/null)" ]; then
          ${notifyUsers} "Back-up is oud" "De laatste back-up is meer dan 14 dagen oud. Steek de schijf $label in."
          touch "$state/last-reminder"
        fi
        exit 0
      fi
      echo "Geen schijf met label $label."
      echo "Formatteer een USB-schijf als ext4 of btrfs en geef hem het label NIXBACKUP."
      exit 1
    fi
    mkdir -p "$mnt" "$state" /root/nixbook-recovery /.snapshots
    chmod 700 /root/nixbook-recovery /.snapshots
    # Backing up a snapshot: files don't change or vanish halfway through, so
    # databases (browsers) come back whole. The path stays the same every run,
    # which lets restic skip what hasn't changed.
    snap=/.snapshots/backup-home
    dropSnapshot() {
      if [ -e "$snap" ]; then
        ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "$snap" >/dev/null
      fi
    }
    mounted=0
    cleanup() {
      dropSnapshot || true
      if [ "$mounted" = 1 ]; then
        ${pkgs.util-linux}/bin/umount "$mnt" || true
      fi
    }
    trap cleanup EXIT
    if ! ${pkgs.util-linux}/bin/findmnt -n "$mnt" >/dev/null; then
      ${pkgs.util-linux}/bin/mount "$dev" "$mnt"
      mounted=1
    fi
    pw=/root/nixbook-recovery/restic-password
    export RESTIC_PASSWORD_FILE=$pw
    repo=$mnt/restic
    if [ -e "$repo/config" ]; then
      # A new password can never open this repository, so don't make one.
      if [ ! -s "$pw" ]; then
        echo "$pw ontbreekt, en $label heeft al een back-up." >&2
        echo "Zet het bestand terug van je reservekopie." >&2
        exit 1
      fi
    else
      if [ ! -s "$pw" ]; then
        umask 077
        ${pkgs.openssl}/bin/openssl rand -base64 32 > "$pw"
        echo "Nieuw restic-wachtwoordbestand: $pw"
        echo "Dit is niet je inlogwachtwoord en niet de wachtzin van de schijf."
        echo "Kopieer het van de laptop af: sudo nixbook-backup-recovery /pad/op/een/usb-stick"
        echo "Zonder dit bestand kun je de backup niet terugzetten."
        ${notifyUsers} "Backup-wachtwoord aangemaakt" "Het is niet je inlogwachtwoord. Kopieer het van de laptop af met 'sudo nixbook-backup-recovery /pad/op/een/usb-stick', anders kun je de backup niet terugzetten."
      fi
      ${pkgs.restic}/bin/restic init --repo "$repo"
    fi
    dropSnapshot
    ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /home "$snap" >/dev/null
    ${pkgs.restic}/bin/restic backup --repo "$repo" "$snap" \
      --exclude-caches \
      --exclude "$snap/*/.cache" \
      --exclude "$snap/*/.var/app/*/cache" \
      --exclude "$snap/*/.local/share/Trash" \
      --exclude "$snap/*/.local/share/containers"
    ${pkgs.restic}/bin/restic forget --repo "$repo" \
      --keep-daily 14 --keep-weekly 8 --keep-monthly 12
    touch "$state/last-success"
    # Pruning rewrites packs on the disk, so once a week, not every hour. A
    # backup that can't be read is only noticed when it's needed, so also read
    # back a sample.
    pruned="$mnt/nixbook-pruned"
    if [ -z "$(${pkgs.findutils}/bin/find "$pruned" -mtime -7 2>/dev/null)" ]; then
      ${pkgs.restic}/bin/restic prune --repo "$repo"
      ${pkgs.restic}/bin/restic check --repo "$repo" --read-data-subset=5%
      touch "$pruned"
    fi
    echo "Backup van /home staat op $label ($repo)."
  '';

  # These run unattended, so nobody would see them fail. Once a day per task:
  # a backup that fails does so every hour.
  taskFailed = pkgs.writeShellScript "nixbook-task-failed" ''
    unit=$1
    stamp="$STATE_DIRECTORY/$unit"
    [ -z "$(${pkgs.findutils}/bin/find "$stamp" -mmin -1440 2>/dev/null)" ] || exit 0
    touch "$stamp"
    case "$unit" in
      nixbook-backup-home*) task="De back-up" ;;
      nixbook-snapshot*) task="De dagelijkse snapshot" ;;
      btrfs-scrub*) task="De controle van de SSD" ;;
      *) task="$unit" ;;
    esac
    ${notifyUsers} "$task is mislukt" "Details: journalctl -u $unit"
  '';
  onFailure = [ "nixbook-task-failed@%n.service" ];
in
{
  environment.systemPackages = [
    backupHome
    pkgs.restic # to restore
  ];

  systemd.services."nixbook-task-failed@" = {
    description = "Tell users that %i failed";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "nixbook-task-failed";
      ExecStart = "${taskFailed} %i";
    };
  };

  systemd.services."btrfs-scrub--" = { inherit onFailure; };

  systemd.services.nixbook-snapshot = {
    description = "Read-only btrfs snapshots of / and /home";
    inherit onFailure;
    path = [
      pkgs.coreutils
      pkgs.btrfs-progs
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${snapshot}";
      Nice = 19;
      IOWeight = 20;
    };
  };
  systemd.timers.nixbook-snapshot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # does nothing when the disk isn't there
  systemd.services.nixbook-backup-home = {
    description = "restic backup of /home to a disk labeled NIXBACKUP";
    inherit onFailure;
    path = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.restic
      pkgs.openssl
    ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOWeight = 20;
    };
    script = "${backupHome}/bin/nixbook-backup-home --if-present";
  };
  systemd.timers.nixbook-backup-home = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
  };
}
