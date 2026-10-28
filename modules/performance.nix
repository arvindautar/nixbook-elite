# Tuned for 16 GB RAM and a DRAM-less NVMe (KIOXIA BG5)
{ ... }:

{
  # zram only, no swap on the SSD. zstd gets ~3-4x on desktop workloads.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  # Swapping to zram is cheap, so do that before dropping page cache. Same
  # values ChromeOS, Pop!_OS and Fedora use for zram-only setups.
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.vfs_cache_pressure" = 50;
    # smaller writeback bursts, the BG5 has no DRAM cache
    "vm.dirty_bytes" = 268435456;
    "vm.dirty_background_bytes" = 67108864;
  };

  # kill runaway processes before the desktop freezes
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
