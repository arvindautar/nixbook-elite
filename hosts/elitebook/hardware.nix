# Written from the hardware report so the system can be built (and put on
# the ISO) before installing. Filesystems come from disko.nix, by label.
{ lib, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ "i915" ]; # early KMS: flicker-free Plymouth
  boot.kernelModules = [ "kvm-intel" ];

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true; # iwlwifi AX211, SOF audio, i915 GuC/HuC

  # Iris Xe video decode/encode, saves a lot of battery
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  # GuC submission and HuC are already on by default on Raptor Lake

  # Synaptics 06cb:00f0, enroll in GNOME Settings
  services.fprintd.enable = true;

  # off at boot
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # Intel eSIM without profiles. Otherwise NM starts ModemManager and probes it
  # on every boot. Remove both to use cellular.
  networking.modemmanager.enable = false;
  boot.blacklistedKernelModules = [ "iosm" ];

  # HP publishes its firmware on LVFS
  services.fwupd.enable = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
