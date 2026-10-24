# Battery life for a 15 W Raptor Lake laptop.
# power-profiles-daemon drives intel_pstate EPP and integrates with GNOME's
# power menu (TLP would conflict with it).
{ ... }:

{
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.upower.enable = true;

  boot.kernelParams = [
    # Panel self refresh and framebuffer compression on the eDP panel
    "i915.enable_psr=1"
    "i915.enable_fbc=1"
    "nvme_core.default_ps_max_latency_us=5500"
  ];

  # Audio codec sleeps after 1s of silence
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
  '';

  # Runtime power management for PCI devices; USB input devices are left alone
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
  '';
}
