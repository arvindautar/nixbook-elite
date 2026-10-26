# Flathub, declaratively (nix-flatpak). Apps you install with Bazaar are kept.
{ pkgs, lib, ... }:

let
  # Same steps as a hand install: clone, pack with build.sh, install the zip.
  # The clone is a temporary directory, removed once the zip is installed; a
  # login only asks GitHub for the latest commit id and rebuilds when it moved.
  # build.sh starts with #!/bin/bash, and NixOS has no /bin/bash, so it only
  # builds when invoked as `bash build.sh`. gnome-extensions install writes
  # only into the logged-in user's home. There is no system copy.
  gradiaCaptureFromGit = pkgs.writeShellScript "nixbook-gradia-capture" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.bash
        pkgs.git
        pkgs.gnome-shell
        pkgs.glib.dev # glib-compile-schemas, used by gnome-extensions install
        pkgs.findutils # build.sh uses GNU find -printf
        pkgs.coreutils
      ]
    }
    # gnome-extensions install needs these typelibs to unpack the zip.
    export GI_TYPELIB_PATH=${
      lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.glib.out
        pkgs.json-glib
        pkgs.gnome-autoar
      ]
    }

    # The GDM greeter (gdm-greeter*, uids above 60000) also starts a graphical
    # session. Only normal accounts (uid 1000-29999) get the extension.
    uid=$(id -u)
    if [ "$uid" -lt 1000 ] || [ "$uid" -gt 29999 ] || [ -z "''${HOME:-}" ]; then
      exit 0
    fi
    uuid=gradia-integration@alexandervanhee.github.io
    repo=https://github.com/AlexanderVanhee/gradia-capture
    installed="$HOME/.local/share/gnome-shell/extensions/$uuid"
    stamp="$HOME/.local/state/nixbook/gradia-capture-rev"

    # Earlier versions kept the checkout in ~/Downloads. Remove it only when it
    # is the untouched upstream clone; anything else there belongs to the user.
    old="$HOME/Downloads/gradia-capture"
    if [ -d "$old/.git" ] &&
      [ "$(git -C "$old" remote get-url origin 2>/dev/null)" = "$repo" ] &&
      [ -z "$(git -C "$old" status --porcelain 2>/dev/null)" ]; then
      rm -rf "$old"
    fi

    # Fails until flatpak-managed-install has put Gradia on the system; the
    # unit then retries.
    ${pkgs.flatpak}/bin/flatpak info --system be.alexandervanhee.gradia >/dev/null

    # Only the commit id is fetched to see whether an update exists
    if ! rev=$(git ls-remote "$repo" HEAD | cut -f1) || [ -z "$rev" ]; then
      if [ -d "$installed" ]; then
        echo "GitHub is onbereikbaar. De geïnstalleerde Gradia Capture blijft staan."
        exit 0
      fi
      echo "Gradia Capture kon niet van GitHub worden gehaald." >&2
      exit 1
    fi
    if [ -f "$stamp" ] && [ -d "$installed" ] && [ "$(cat "$stamp")" = "$rev" ]; then
      echo "Gradia Capture $rev staat er al."
      exit 0
    fi

    src=$(mktemp -d)
    trap 'rm -rf "$src"' EXIT
    git clone --depth 1 "$repo" "$src"
    rev=$(git -C "$src" rev-parse HEAD)
    ( cd "$src" && bash build.sh )
    zip="$src/$uuid.shell-extension.zip"
    [ -f "$zip" ]
    gnome-extensions install --force "$zip"
    mkdir -p "$(dirname "$stamp")"
    printf '%s\n' "$rev" > "$stamp"
    echo "Gradia Capture $rev geïnstalleerd. Log uit en weer in om hem te laden."
  '';
in
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
      "org.mozilla.firefox" # policies in desktop.nix
      "io.github.diegopvlk.Cine" # video
      "org.gnome.Decibels" # audio
      "org.gnome.SoundRecorder"
      "io.github.alainm23.planify" # tasks
      "org.onlyoffice.desktopeditors" # office (own nl/en-GB dictionaries)
      "com.github.PintaProject.Pinta" # paint
      "be.alexandervanhee.gradia" # screenshot annotation, with Gradia Capture
      "org.gnome.Papers" # PDF
      "org.gnome.Loupe" # images
      "org.gnome.Calculator"
      "io.gitlab.librewolf-community" # browser
      "it.mijorus.smile" # emoji picker
      "com.mattjakeman.ExtensionManager" # browse/install GNOME extensions
    ];
    # OnlyOffice opens documents from others and is online: no access to every
    # file, only these folders. Elsewhere, open the file from Nautilus.
    overrides.settings."org.onlyoffice.desktopeditors".Context.filesystems = [
      "!host"
      "xdg-documents"
      "xdg-download"
      "xdg-desktop"
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

  # Run in each graphical session using that user's HOME, retrying until the
  # system-wide Gradia Flatpak and GitHub are available. Existing copies work
  # offline. Every few minutes is enough: Flathub installs take longer.
  systemd.user.services.nixbook-gradia-capture = {
    description = "Install Gradia Capture from git";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = gradiaCaptureFromGit;
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 19;
      Restart = "on-failure";
      RestartSec = "5min";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  xdg.portal.enable = true;
}
