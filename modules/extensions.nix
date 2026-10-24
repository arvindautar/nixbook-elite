# GNOME Shell extensions that were installed by hand from the extensions app.
# Dash to Dock, Blur my Shell and AppIndicator come from nixpkgs-unstable.
# Gradia Capture is not in nixpkgs. Its source is the gradia-capture flake
# input, so a flake update follows the newest commit on master.
{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

let
  rev =
    (builtins.fromJSON (builtins.readFile "${inputs.self}/flake.lock")).nodes.gradia-capture.locked.rev;

  gradia-capture = pkgs.stdenv.mkDerivation {
    pname = "gnome-shell-extension-gradia-capture";
    version = builtins.substring 0 7 rev;

    src = inputs.gradia-capture;

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
