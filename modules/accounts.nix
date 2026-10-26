# Accounts are data, not configuration: like a Chromebook, the first account is
# made at first boot in GNOME's setup screen and never appears in this flake.
# Everything an account needs (groups, container ID ranges) is given to it by
# name-independent rules here, so the prebuilt offline system is complete.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Admins (wheel) get what the installer used to give the first user
  adminGroups = [
    "networkmanager"
    "libvirtd"
    "nordvpn"
    "video"
    "audio"
  ];

  # Idempotent; run on every activation and whenever an account is added or
  # changed. NixOS rewrites /etc/subuid and /etc/subgid from declared users
  # only, so undeclared accounts get the range NixOS would allocate, recorded
  # in auto-subuid-map in case a later generation does declare them.
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
          for g in ${lib.concatStringsSep " " adminGroups}; do
            [[ "$groups" == *" $g "* ]] || usermod -aG "$g" "$name"
          done
        fi
      done
  '';

  # Pages for settings this flake fixes (language, keyboard, time zone) or apps
  # it does not ship. NixOS's own copy also skips account and password, which
  # leaves a fresh install without a way to make its first account.
  initialSetupVendorConf = pkgs.writeText "vendor.conf" ''
    [pages]
    skip=language;keyboard;timezone;software;
  '';
in
{
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!"; # root login disabled, use sudo

  users.groups = {
    libvirtd = { };
    nordvpn = { };
  };

  nixpkgs.overlays = [
    (_: prev: {
      gnome-initial-setup = prev.gnome-initial-setup.overrideAttrs (old: {
        mesonFlags = lib.filter (f: !lib.hasPrefix "-Dvendor-conf-file=" f) old.mesonFlags ++ [
          "-Dvendor-conf-file=${initialSetupVendorConf}"
        ];
      });
    })
  ];

  # NixOS creates this marker so GDM never offers to create an account. GDM
  # only runs setup while there are no accounts, so removing it is harmless
  # afterwards.
  systemd.services.display-manager.preStart = lib.mkAfter ''
    rm -f /run/gdm/gdm.ran-initial-setup
  '';

  system.activationScripts.nixbookAccounts = {
    deps = [ "users" ];
    text = "${setupAccounts}";
  };
  # GNOME's setup screen and Settings add accounts and admin rights at runtime
  systemd.paths.nixbook-setup-accounts = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = [
      "/etc/passwd"
      "/etc/group"
    ];
  };
  systemd.services.nixbook-setup-accounts = {
    description = "Give new accounts their groups and container ID ranges";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = setupAccounts;
    };
  };

  # Machines installed before accounts moved out of the flake had their user
  # declared by an earlier generation; NixOS deletes such a user from any later
  # generation that does not declare it. Refuse that for normal accounts.
  # A deliberate removal: NIXOS_NO_CHECK=1 nixos-rebuild ...
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
