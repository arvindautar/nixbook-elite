# HP EliteBook 840 14 inch G10 (i5-1345U, 16 GB, KIOXIA BG5 256 GB NVMe)
{ nixbookUser, ... }:

{
  _module.args.nixbookUser = builtins.fromJSON (builtins.readFile ./user.json);

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

  # Looks like any Windows PC: says nothing about you, the device or the OS.
  # The installer picks a random DESKTOP-XXXXXXX per laptop, writes it to
  # /etc/hostname for the first boot and to user.json for every rebuild after.
  # The offline image has none, so NixOS leaves /etc/hostname to the installer.
  networking.hostName = if nixbookUser.hostName or null == null then "" else nixbookUser.hostName;
  assertions = [
    {
      assertion = nixbookUser.name == null || nixbookUser.hostName or null != null;
      message = ''hosts/elitebook/user.json mist "hostName", bijvoorbeeld "DESKTOP-AB12CD3".'';
    }
  ];

  system.stateVersion = "26.05";
}
