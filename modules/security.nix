# Cheap hardening. Left out on purpose because they're slow or break things:
# init_on_free, hardened_malloc, lockdown= (modules aren't signed),
# mitigations=auto,nosmt.
{ lib, ... }:

{
  # AppArmor
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = false;
  };

  # nftables, drop everything inbound, no ping replies
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = false;
    rejectPackets = false; # drop silently: ports look "stealth", not "closed"
    logRefusedConnections = false;
    # needed for NordLynx/WireGuard
    checkReversePath = "loose";
  };

  # kernel
  boot.kernelParams = [
    "init_on_alloc=1" # ~1% cost, zeroes new allocations
    "slab_nomerge"
    "page_alloc.shuffle=1"
    "randomize_kstack_offset=on"
    "vsyscall=none"
    "debugfs=off"
    "intel_iommu=on" # Thunderbolt DMA protection
  ];
  security.protectKernelImage = true;

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.kexec_load_disabled" = 1;
    "kernel.sysrq" = 4; # only Secure Attention Key
    "kernel.perf_event_paranoid" = 3;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "fs.suid_dumpable" = 0;
    "dev.tty.ldisc_autoload" = 0;

    # network
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.conf.all.log_martians" = 0;
  };

  # protocols and filesystems a laptop doesn't need
  boot.blacklistedKernelModules = [
    "dccp"
    "sctp"
    "rds"
    "tipc"
    "n-hdlc"
    "ax25"
    "netrom"
    "x25"
    "rose"
    "decnet"
    "econet"
    "af_802154"
    "ipx"
    "appletalk"
    "psnap"
    "p8023"
    "p8022"
    "can"
    "atm"
    "firewire-core"
    "firewire-ohci"
    "cramfs"
    "freevxfs"
    "jffs2"
    "hfs"
    "vivid"
  ];

  # privileges
  security.sudo = {
    execWheelOnly = true;
    wheelNeedsPassword = true;
  };
  security.polkit.enable = true;
  # Fingerprint only for GDM (login and lock screen). With fprintd on, NixOS
  # enables it for every PAM service, sudo and polkit included.
  security.pam.services =
    lib.genAttrs
      [
        "sudo"
        "su"
        "polkit-1"
        "systemd-run0"
        "runuser"
        "runuser-l"
        "passwd"
        "chpasswd"
        "chfn"
        "chsh"
        "useradd"
        "userdel"
        "usermod"
        "groupadd"
        "groupdel"
        "groupmems"
        "groupmod"
        "cups"
        "other"
      ]
      (_: {
        fprintAuth = false;
      });

  # Thunderbolt devices need to be authorized, GNOME asks
  services.hardware.bolt.enable = true;

  # TPM stays available to the firmware, the disk is unlocked with a passphrase
  security.tpm2.enable = true;

  # core dumps can contain passwords and keys
  systemd.coredump.settings.Coredump.Storage = "none";
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "core";
      type = "hard";
      value = "0";
    }
  ];

  services.openssh.enable = lib.mkForce false;
}
