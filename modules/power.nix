# Battery life for a 15 W Raptor Lake laptop.
# power-profiles-daemon drives intel_pstate EPP and integrates with GNOME's
# power menu (TLP would conflict with it).
# Left at the kernel's defaults on purpose: i915 picks the deepest panel self
# refresh (PSR2) and FBC itself, where enable_psr=1 would cap it at PSR1; the
# KIOXIA BG5 uses all its NVMe power states; audio is SOF, which does its own
# runtime power management (snd_hda_intel's power_save does not apply).
{ ... }:

{
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.upower.enable = true;

  # Runtime power management for PCI devices; USB input devices are left alone
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
  '';
}
