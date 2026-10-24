# Hardening with negligible performance cost.
# Deliberately NOT used (too slow or breaks things): init_on_free, hardened_malloc,
# lockdown= (NixOS modules are unsigned), mitigations=auto,nosmt.
{ lib, ... }:

{
  # --- AppArmor (MAC) ---
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = false;
  };

  # --- Firewall: nftables, drop everything inbound, don't answer pings (stealth) ---
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = false;
    rejectPackets = false; # drop silently: ports look "stealth", not "closed"
    logRefusedConnections = false;
    # VPN (NordLynx/WireGuard) needs loose reverse path filtering
    checkReversePath = "loose";
  };

  # --- Kernel ---
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

    # Network stack
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

  # Obscure network protocols and old filesystems nobody uses on a laptop
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

  # --- Privilege ---
  security.sudo = {
    execWheelOnly = true;
    wheelNeedsPassword = true;
  };
  security.polkit.enable = true;

  # Thunderbolt devices must be authorised (GNOME asks)
  services.hardware.bolt.enable = true;

  # The TPM stays available to the firmware. Disk unlock is the passphrase.
  security.tpm2.enable = true;

  # No core dumps (they can contain passwords/keys)
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
