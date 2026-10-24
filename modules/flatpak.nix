# Flathub, declaratively (nix-flatpak). Apps you install with Bazaar are kept.
{ pkgs, lib, ... }:

let
  # Same steps as a hand install: clone the repo, pack with build.sh, install
  # the zip. build.sh starts with #!/bin/bash, and NixOS has no /bin/bash, so
  # it only builds when invoked as `bash build.sh`. gnome-extensions install
  # always writes into the calling user's home, which then overrides the
  # system copy from extensions.nix. That system copy is what an offline
  # install and the ISO already have.
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
    # A system service has no GNOME session. gnome-extensions install needs these
    # typelibs or it cannot unpack the zip.
    export GI_TYPELIB_PATH=${
      lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.glib.out
        pkgs.json-glib
        pkgs.gnome-autoar
      ]
    }

    if [ "''${HOME:-}" = "" ] || [ "$HOME" = /root ]; then
      echo "Gradia Capture hoort in de home van gebruiker." >&2
      exit 1
    fi

    uuid=gradia-integration@alexandervanhee.github.io
    installed="$HOME/.local/share/gnome-shell/extensions/$uuid"
    stamp="$HOME/.local/state/nixbook/gradia-capture-rev"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    if ! git clone --depth 1 https://github.com/AlexanderVanhee/gradia-capture "$work/src"; then
      if [ -d "$installed" ]; then
        echo "GitHub is onbereikbaar. De geïnstalleerde Gradia Capture blijft staan."
        exit 0
      fi
      echo "Gradia Capture kon niet van GitHub worden gehaald." >&2
      exit 1
    fi

    rev=$(git -C "$work/src" rev-parse HEAD)
    if [ -f "$stamp" ] && [ -d "$installed" ] && [ "$(cat "$stamp")" = "$rev" ]; then
      echo "Gradia Capture $rev staat er al."
      exit 0
    fi

    ( cd "$work/src" && bash build.sh )
    zip="$work/src/$uuid.shell-extension.zip"
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
    # Gradia the Flatpak is in the list above. Its shell extension is not a
    # Flatpak; pull the current git revision once this install succeeds.
    onSuccess = [ "nixbook-gradia-capture.service" ];
  };

  # Not wanted by boot. It starts only after flatpak-managed-install succeeds,
  # which is the first boot that can reach Flathub, and again on later boots
  # once that install has run. Offline, the system extension stays in use.
  systemd.services.nixbook-gradia-capture = {
    description = "Install Gradia Capture from git";
    serviceConfig = {
      Type = "oneshot";
      User = "gebruiker";
      Group = "users";
      ExecStart = gradiaCaptureFromGit;
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 19;
      Restart = "on-failure";
      RestartSec = "60s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  xdg.portal.enable = true;
}
