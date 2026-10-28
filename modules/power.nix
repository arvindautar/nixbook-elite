# Battery settings for a 15 W Raptor Lake.
# power-profiles-daemon instead of TLP: it handles EPP and GNOME uses it.
# i915, NVMe and audio power saving are left at the defaults on purpose.
# i915.enable_psr=1 would cap PSR at PSR1, the BG5 is fine with all its NVMe
# power states, and audio is SOF, so snd_hda_intel.power_save does nothing.
{ ... }:

{
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.upower.enable = true;

  # runtime PM for PCI devices (USB is left alone)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
  '';
}
