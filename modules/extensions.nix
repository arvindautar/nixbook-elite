# Shared GNOME extensions. Gradia Capture is installed only in the logged-in
# user's home by the user service in flatpak.nix.
{ pkgs-unstable, ... }:

{
  environment.systemPackages = [
    pkgs-unstable.gnomeExtensions.dash-to-dock
    pkgs-unstable.gnomeExtensions.blur-my-shell
  ];
}
