# btrfs snapshots on the SSD itself (for undo, not for a dead disk), and
# restic to a disk labeled NIXBACKUP whenever one is plugged in.
{ pkgs, ... }:

let
  snapshot = pkgs.writeShellScript "nixbook-snapshot" ''
    set -euo pipefail
    stamp=$(date +%F-%H%M)
    mkdir -p /.snapshots
    chmod 700 /.snapshots
    ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /home "/.snapshots/home-$stamp"
    ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r / "/.snapshots/root-$stamp"
    # nested subvolumes aren't included, so no recursion
    cd /.snapshots
    ls -1d home-* 2>/dev/null | sort | head -n -14 | while read -r old; do
      ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/.snapshots/$old"
    done
    ls -1d root-* 2>/dev/null | sort | head -n -7 | while read -r old; do
      ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/.snapshots/$old"
    done
  '';

  backupHome = pkgs.writeShellScriptBin "nixbook-backup-home" ''
    set -euo pipefail
    [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
    label=NIXBACKUP
    mnt=/mnt/nixbackup
    dev=$(${pkgs.util-linux}/bin/blkid -L "$label" || true)
    if [ -z "$dev" ]; then
      if [ "''${1:-}" = "--if-present" ]; then
        exit 0
      fi
      echo "Geen schijf met label $label."
      echo "Formatteer een USB-schijf als ext4 of btrfs en geef hem het label NIXBACKUP."
      exit 1
    fi
    mkdir -p "$mnt" /root/nixbook-recovery
    chmod 700 /root/nixbook-recovery
    mounted=0
    if ! ${pkgs.util-linux}/bin/findmnt -n "$mnt" >/dev/null; then
      ${pkgs.util-linux}/bin/mount "$dev" "$mnt"
      mounted=1
    fi
    cleanup() {
      if [ "$mounted" = 1 ]; then
        ${pkgs.util-linux}/bin/umount "$mnt" || true
      fi
    }
    trap cleanup EXIT
    pw=/root/nixbook-recovery/restic-password
    if [ ! -s "$pw" ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -base64 32 > "$pw"
      echo "Nieuw restic-wachtwoord: $pw"
      echo "Kopieer dat bestand van de laptop af, samen met de Secure Boot-sleutels."
    fi
    export RESTIC_PASSWORD_FILE=$pw
    repo=$mnt/restic
    if [ ! -d "$repo" ]; then
      ${pkgs.restic}/bin/restic init --repo "$repo"
    fi
    ${pkgs.restic}/bin/restic backup --repo "$repo" /home \
      --exclude '/home/*/.cache' \
      --exclude '/home/*/.var/app/*/cache' \
      --exclude '/home/*/.local/share/Trash'
    ${pkgs.restic}/bin/restic forget --repo "$repo" --prune \
      --keep-daily 14 --keep-weekly 8 --keep-monthly 12
    echo "Backup van /home staat op $label ($repo)."
  '';
in
{
  environment.systemPackages = [ backupHome ];

  systemd.services.nixbook-snapshot = {
    description = "Read-only btrfs snapshots of / and /home";
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
