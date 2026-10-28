# libvirt/KVM VMs and distrobox (on podman). Everything is socket-activated: no boot cost.
# A GUI (virt-manager or GNOME Boxes) can be installed from Flathub via Bazaar.
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

  # autoPrune above only cleans root's containers. Each account's own image
  # store (~/.local/share/containers) loses its unused layers weekly. Only
  # dangling images: images that containers and distroboxes use are kept.
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

  # VM disks on btrfs: no copy-on-write (avoids fragmentation)
  systemd.tmpfiles.rules = [ "h /var/lib/libvirt/images - - - - +C" ];
}
