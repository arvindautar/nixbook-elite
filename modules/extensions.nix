# GNOME Shell extensions that were installed by hand from the extensions app.
# They come from nixpkgs-unstable so the weekly flake update picks up fixes.
# Today that is dash-to-dock 109 (Shell 45-51) and blur-my-shell 72 (Shell 46-50).
# Gradia Capture is not in nixpkgs. This is the commit already built in ~/Downloads.
{
  pkgs,
  pkgs-unstable,
  ...
}:

let
  gradia-capture = pkgs.stdenv.mkDerivation {
    pname = "gnome-shell-extension-gradia-capture";
    version = "0b7e47e";

    src = pkgs.fetchFromGitHub {
      owner = "AlexanderVanhee";
      repo = "gradia-capture";
      rev = "0b7e47e1e5c1e68e234e4d2d24b307e1da1d18a9";
      hash = "sha256-ZpJTf6gfepiC0kXUWfjB73iWLRuiQtRBq4kFzk0N6Ss=";
    };

    nativeBuildInputs = [ pkgs.glib ];

    installPhase = ''
      runHook preInstall
      dest=$out/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io
      mkdir -p "$dest/schemas" "$dest/icons"
      cp src/*.js src/*.css src/metadata.json "$dest/"
      cp LICENSE README.md "$dest/"
      cp icons/*.svg "$dest/icons/"
      cp schemas/*.xml "$dest/schemas/"
      glib-compile-schemas "$dest/schemas"
      runHook postInstall
    '';

    meta.description = "Screenshot annotations for GNOME, companion of the Gradia Flatpak";
  };
in
{
  environment.systemPackages = [
    pkgs-unstable.gnomeExtensions.dash-to-dock
    pkgs-unstable.gnomeExtensions.blur-my-shell
    gradia-capture
  ];
}
