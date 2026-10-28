# GNOME extensions for all users. Gradia Capture is per user, see flatpak.nix.
{ pkgs-unstable, ... }:

{
  environment.systemPackages = [
    pkgs-unstable.gnomeExtensions.dash-to-dock
    pkgs-unstable.gnomeExtensions.blur-my-shell
  ];
}
