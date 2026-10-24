# Hardware profile written from the hardware report, so the system can be
# built (and put on the ISO) before installation. File systems come from
# disko.nix and are referenced by label, never by UUID.
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

  # Raptor Lake Iris Xe: hardware video decode/encode saves a lot of battery
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  # GuC submission + HuC firmware for the iGPU (lower CPU use, better media power)
  boot.kernelParams = [ "i915.enable_guc=3" ];

  # Synaptics 06cb:00f0 fingerprint reader (enroll in GNOME Settings, optional)
  services.fprintd.enable = true;

  # AX211 Bluetooth: available, but off until you switch it on
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # Intel eSIM (no profiles). NetworkManager would otherwise start ModemManager
  # and probe it on every boot. Remove both lines to use cellular later.
  networking.modemmanager.enable = false;
  boot.blacklistedKernelModules = [ "iosm" ];

  # HP firmware updates through LVFS (where HP publishes them)
  services.fwupd.enable = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
