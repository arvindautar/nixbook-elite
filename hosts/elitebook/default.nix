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

  # Looks like any Windows PC: says nothing about you, the device or the OS.
  # The installer picks a random DESKTOP-XXXXXXX per laptop and writes it to
  # /etc/hostname. With no hostname here, NixOS leaves that file alone.
  networking.hostName = "";

  # Laptops installed when user.json held the hostname had /etc/hostname from
  # NixOS, which removes it now. Keep the name they are running with.
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
