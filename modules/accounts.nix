# No accounts in the flake. The installer creates the first one, more can be
# added in GNOME Settings. Groups and subuid ranges come from the rules below,
# so the prebuilt system on the ISO doesn't need to know any names.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # extra groups for admins (wheel). The installer already sets these for the
  # first account, this is for admins added later.
  adminGroups = [
    "networkmanager"
    "libvirtd"
    "nordvpn"
    "video"
    "audio"
  ];

  # Idempotent, runs on activation and whenever passwd/group change.
  # NixOS only writes subuid/subgid for declared users, so give the others the
  # range NixOS would pick and record it in auto-subuid-map, in case a later
  # generation declares the user after all.
  setupAccounts = pkgs.writeShellScript "nixbook-setup-accounts" ''
    set -eu
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.shadow
      ]
    }
    map=/var/lib/nixos/auto-subuid-map
    [ -s "$map" ] || echo '{}' > "$map"
    sed -i '/^$/d' /etc/subuid /etc/subgid
    awk -F: '$3 >= 1000 && $3 <= 29999 { print $1, 100000 + ($3 - 1000) * 65536 }' /etc/passwd |
      while read -r name start; do
        start=$(jq -r --arg n "$name" --argjson s "$start" '.[$n] // $s' "$map")
        for f in /etc/subuid /etc/subgid; do
          grep -q "^$name:" "$f" || echo "$name:$start:65536" >> "$f"
        done
        jq -c --arg n "$name" --argjson s "$start" '.[$n] = $s' "$map" > "$map.tmp"
        mv "$map.tmp" "$map"

        groups=" $(id -nG "$name") "
        if [[ "$groups" == *" wheel "* ]]; then
          # single usermod: every write to /etc/group triggers the path unit again
          missing=
          for g in ${lib.concatStringsSep " " adminGroups}; do
            [[ "$groups" == *" $g "* ]] || missing+="''${missing:+,}$g"
          done
          [ -z "$missing" ] || usermod -aG "$missing" "$name"
        fi
      done
  '';
in
{
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!"; # root login disabled, use sudo

  users.groups = {
    libvirtd = { };
    nordvpn = { };
  };

  # The installer makes the account and everything the wizard asks is set here
  # already. Its privacy page could also turn location services back on.
  services.gnome.gnome-initial-setup.enable = false;

  system.activationScripts.nixbookAccounts = {
    deps = [ "users" ];
    text = "${setupAccounts}";
  };
  # accounts can be added at runtime (GNOME Settings)
  systemd.paths.nixbook-setup-accounts = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = [
      "/etc/passwd"
      "/etc/group"
    ];
  };
  systemd.services.nixbook-setup-accounts = {
    description = "Give new accounts their groups and container ID ranges";
    # Creating an account writes passwd/group several times and so do we.
    # Running twice is harmless, but hitting the start limit also kills the
    # path unit until the next boot.
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = setupAccounts;
    };
  };

  # Laptops installed before accounts moved out of the flake had their user
  # declared in an older generation. NixOS deletes such users from a generation
  # that doesn't declare them anymore, so refuse that.
  # To remove one on purpose: NIXOS_NO_CHECK=1 nixos-rebuild ...
  system.preSwitchChecks.nixbookKeepUsers =
    let
      normalUsers = lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users);
    in
    ''
      decl=/var/lib/nixos/declarative-users
      [ -e "$decl" ] || exit 0
      missing=$(${pkgs.gawk}/bin/awk -F: \
        -v decl="$(${pkgs.coreutils}/bin/cat "$decl")" \
        -v keep=${lib.escapeShellArg (lib.concatStringsSep " " normalUsers)} '
        BEGIN {
          split(decl, d, " "); for (i in d) was[d[i]] = 1
          split(keep, k, " "); for (i in k) now[k[i]] = 1
        }
        $3 >= 1000 && $3 <= 29999 && ($1 in was) && !($1 in now) { print $1 }
      ' /etc/passwd)
      if [ -n "$missing" ]; then
        echo "Deze configuratie zou deze gebruiker(s) verwijderen: $missing"
        echo "Haal ze eerst uit /var/lib/nixos/declarative-users, dan blijven ze bestaan:"
        echo "  sudo sed -i 's/\<''${missing%%[[:space:]]*}\>//' /var/lib/nixos/declarative-users"
        exit 1
      fi
    '';
}
