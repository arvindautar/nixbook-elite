# Memory and I/O tuned for 16 GB RAM + a DRAM-less NVMe (KIOXIA BG5)
{ ... }:

{
  # zram: compressed swap in RAM, no swap on the SSD (no hibernation, no wear).
  # zstd gives ~3-4x on desktop memory, so 8 GB zram ~ 24-30 GB extra headroom.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  # Swapping to zram is cheap, so prefer it over dropping file cache
  # (same values ChromeOS / Pop!_OS / Fedora use for zram-only systems)
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.vfs_cache_pressure" = 50;
    # Smaller writeback bursts: no stalls on the DRAM-less SSD
    "vm.dirty_bytes" = 268435456;
    "vm.dirty_background_bytes" = 67108864;
  };

  # Kill runaway memory hogs before the desktop freezes
  systemd.oomd = {
    enable = true;
    enableUserSlices = true;
    enableRootSlice = true;
  };

  services.dbus.implementation = "broker";

  services.fstrim.enable = true;
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
