# libvirt/KVM VMs and distrobox (on podman). Everything is socket-activated: no boot cost.
# A GUI (virt-manager or GNOME Boxes) can be installed from Flathub via Bazaar.
{ pkgs, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu = {
      runAsRoot = false;
      swtpm.enable = true; # TPM for Windows 11 guests
    };
  };
  virtualisation.spiceUSBRedirection.enable = true;
  networking.firewall.trustedInterfaces = [ "virbr0" ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
    autoPrune.enable = true;
  };

  environment.systemPackages = [ pkgs.distrobox ];

  # VM disks on btrfs: no copy-on-write (avoids fragmentation)
  systemd.tmpfiles.rules = [ "h /var/lib/libvirt/images - - - - +C" ];
}
