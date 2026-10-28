# libvirt/KVM and distrobox on podman, all socket activated. For a GUI,
# install virt-manager or Boxes from Flathub.
{ config, pkgs, ... }:

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

  # autoPrune only covers root. Prune dangling images in each user's store
  # too; images used by containers (distrobox) are left alone.
  systemd.user.services.nixbook-podman-prune = {
    description = "Remove unused container image layers";
    unitConfig = {
      ConditionUser = "!@system";
      ConditionPathExists = "%h/.local/share/containers/storage";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.virtualisation.podman.package}/bin/podman image prune --force";
      Nice = 19;
      IOWeight = 20;
    };
  };
  systemd.user.timers.nixbook-podman-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # nodatacow for VM disks
  systemd.tmpfiles.rules = [ "h /var/lib/libvirt/images - - - - +C" ];
}
