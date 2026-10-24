# HP EliteBook 840 14 inch G10 (i5-1345U, 16 GB, KIOXIA BG5 256 GB NVMe)
{ ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/base.nix
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

  # Looks like any Windows PC: says nothing about you, the device or the OS
  networking.hostName = "DESKTOP-4F8K2Q1";

  system.stateVersion = "26.05";
}
