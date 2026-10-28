# HP EliteBook 840 14 inch G10 (i5-1345U, 16 GB, KIOXIA BG5 256 GB NVMe)
{ ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base.nix
    ../../modules/accounts.nix
    ../../modules/boot.nix
    ../../modules/desktop.nix
    ../../modules/fonts.nix
    ../../modules/flatpak.nix
    ../../modules/spelling.nix
    ../../modules/security.nix
    ../../modules/privacy.nix
    ../../modules/performance.nix
    ../../modules/power.nix
    ../../modules/virtualisation.nix
    ../../modules/ai.nix
    ../../modules/nordvpn.nix
    ../../modules/updates.nix
    ../../modules/extensions.nix
    ../../modules/recovery.nix
    ../../modules/backup.nix
  ];

  # Random DESKTOP-XXXXXXX hostname, written by the installer. No hostname
  # here, so NixOS doesn't touch /etc/hostname.
  networking.hostName = "";

  # Older installs got /etc/hostname from NixOS (user.json), which now deletes
  # it on rebuild. Put back the name they're running with.
  system.activationScripts.nixbookHostname = {
    deps = [ "etc" ];
    text = ''
      if [ ! -e /etc/hostname ]; then
        case "$(cat /proc/sys/kernel/hostname)" in
          DESKTOP-*) cat /proc/sys/kernel/hostname > /etc/hostname ;;
        esac
      fi
    '';
  };

  system.stateVersion = "26.05";
}
