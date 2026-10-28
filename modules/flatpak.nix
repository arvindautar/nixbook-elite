# Flathub apps via nix-flatpak. Anything installed with Bazaar is left alone.
{ pkgs, lib, ... }:

let
  # Gradia Capture isn't on Flathub. Build it the way upstream's README does:
  # clone, `bash build.sh`, install the zip. build.sh wants /bin/bash, which
  # NixOS doesn't have, hence the explicit bash. The extension is per user
  # (gnome-extensions install) and only rebuilt when upstream HEAD moved.
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
    # gnome-extensions needs these typelibs to unpack the zip
    export GI_TYPELIB_PATH=${
      lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.glib.out
        pkgs.json-glib
        pkgs.gnome-autoar
      ]
    }

    # the GDM greeter gets a graphical session too (uid > 60000), skip it
    uid=$(id -u)
    if [ "$uid" -lt 1000 ] || [ "$uid" -gt 29999 ] || [ -z "''${HOME:-}" ]; then
      exit 0
    fi
    uuid=gradia-integration@alexandervanhee.github.io
    repo=https://github.com/AlexanderVanhee/gradia-capture
    installed="$HOME/.local/share/gnome-shell/extensions/$uuid"
    stamp="$HOME/.local/state/nixbook/gradia-capture-rev"

    # older versions cloned into ~/Downloads, remove it if it's untouched
    old="$HOME/Downloads/gradia-capture"
    if [ -d "$old/.git" ] &&
      [ "$(git -C "$old" remote get-url origin 2>/dev/null)" = "$repo" ] &&
      [ -z "$(git -C "$old" status --porcelain 2>/dev/null)" ]; then
      rm -rf "$old"
    fi

    # fails until flatpak-managed-install is done, the unit retries
    ${pkgs.flatpak}/bin/flatpak info --system be.alexandervanhee.gradia >/dev/null

    # only fetches the commit id
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
  onlyDownloads.Context.filesystems = [
    "!home"
    "!host"
    "xdg-download"
  ];
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
    # installed in the background once online, see flatpak-managed-install
    packages = [
      "com.github.tchx84.Flatseal"
      "com.brave.Browser"
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
    overrides.settings = {
      # opens other people's documents and is online, so not the whole home dir
      "org.onlyoffice.desktopeditors".Context.filesystems = [
        "!host"
        "xdg-documents"
        "xdg-download"
        "xdg-desktop"
      ];
      # Downloads only. Uploads from elsewhere still work through the portal.
      "com.brave.Browser" = onlyDownloads;
      "io.gitlab.librewolf-community" = onlyDownloads;
    };
    # keep apps installed with Bazaar
    uninstallUnmanaged = false;
    # updates.nix updates all apps, not just these
    update.auto.enable = false;
  };

  # Don't hold up boot when offline. ExecStartPre fails until Flathub is
  # reachable and systemd retries every minute. An install interrupted by a
  # reboot just continues.
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

  # Per graphical session so it ends up in the right $HOME. Retries until
  # the Gradia flatpak is installed and GitHub is reachable.
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
