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

  # Upstream build.sh packs a .shell-extension.zip. The -i flag installs that
  # zip into the user's home, which a Nix system package must not do.
  gradia-capture = pkgs.stdenv.mkDerivation {
    pname = "gnome-shell-extension-gradia-capture";
    version = builtins.substring 0 7 rev;

    src = inputs.gradia-capture;

    nativeBuildInputs = [
      pkgs.gnome-shell # gnome-extensions pack, called by build.sh
      pkgs.glib # glib-compile-schemas, same step as gnome-extensions install
      pkgs.unzip
    ];

    buildPhase = ''
      runHook preBuild
      bash build.sh
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      shopt -s nullglob
      zips=( *.shell-extension.zip )
      [ ''${#zips[@]} -eq 1 ]
      uuid=''${zips[0]%.shell-extension.zip}
      dest=$out/share/gnome-shell/extensions/$uuid
      mkdir -p "$dest"
      unzip -q "''${zips[0]}" -d "$dest"
      # gnome-extensions install unpacks the zip and then compiles schemas.
      # The zip only contains the xml. That command always writes into the
      # user home and has no directory flag, so the unpack happens here.
      [ -d "$dest/schemas" ]
      glib-compile-schemas --strict "$dest/schemas"
      [ -f "$dest/schemas/gschemas.compiled" ]
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
