# Flathub, declaratively (nix-flatpak). Apps you install with Bazaar are kept.
{ pkgs, ... }:

{
  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    # Installed in the background on the first boot with internet
    packages = [
      "com.github.tchx84.Flatseal"
      "com.brave.Browser"
      "io.github.diegopvlk.Cine" # video
      "org.gnome.Decibels" # audio
      "org.onlyoffice.desktopeditors" # office (own nl/en-GB dictionaries)
      "com.github.PintaProject.Pinta" # paint
      "be.alexandervanhee.gradia" # screenshot annotation, with Gradia Capture
      "org.gnome.Papers" # PDF
      "com.mattjakeman.ExtensionManager" # browse/install GNOME extensions
    ];
    # Never remove apps that were installed through Bazaar
    uninstallUnmanaged = false;
    # Daily updates of all apps (not only the ones listed here) live in updates.nix
    update.auto.enable = false;
  };

  # Don't hold up boot or fail when offline: install in the background once online.
  # Until Flathub is reachable the start fails and is retried every minute, forever;
  # an install cut off by a reboot simply continues on the next boot.
  systemd.services.flatpak-managed-install = {
    serviceConfig = {
      ExecStartPre = "${pkgs.curl}/bin/curl -fsS --max-time 15 -o /dev/null https://dl.flathub.org/repo/summary.idx";
      Restart = "on-failure";
      RestartSec = "60s";
      CPUWeight = 20;
      IOWeight = 20;
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  xdg.portal.enable = true;
}
