# USB installer: boots the stock NixOS minimal ISO environment and carries the
# complete, prebuilt nixbook system, so installation works without internet.
{
  modulesPath,
  pkgs,
  lib,
  targetSystem,
  flakeSource,
  ...
}:

let
  nixbookInstall = import ./script.nix {
    inherit pkgs lib flakeSource;
    target = targetSystem;
  };
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  isoImage = {
    edition = lib.mkForce "nixbook-elite";
    storeContents = [ targetSystem.config.system.build.toplevel ];
    squashfsCompression = "zstd -Xcompression-level 15";
  };
  image.baseName = lib.mkForce "nixbook-elite-installer";

  boot.kernelPackages = pkgs.linuxPackages_6_18;
  console.keyMap = "us";
  networking.wireless.enable = lib.mkForce false;

  environment.systemPackages = [ nixbookInstall ];
  system.build.nixbookInstall = nixbookInstall;

  services.getty.helpLine = lib.mkForce ''

    === nixbook-elite installer ===
    Start de installatie met:   sudo nixbook-install
    (geen internet nodig)
  '';

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
