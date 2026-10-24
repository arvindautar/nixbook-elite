# Nix, locale, users and the basics (adapted from nixbook common.nix)
{
  config,
  pkgs,
  lib,
  nixbookUser,
  ...
}:

{
  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      # Only admins may talk to the nix daemon
      allowed-users = [ "@wheel" ];
      trusted-users = [ "root" ];
      max-jobs = "auto";
      download-buffer-size = 268435456;
    };
    # Builds and updates never make the desktop stutter
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    # Flake-only system: no channels, NIX_PATH points at the pinned nixpkgs
    channel.enable = false;
  };
  # Builds go to disk, not to the RAM-backed /tmp
  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";

  # Dutch UI and formats, US keyboard with € on AltGr+5
  time.timeZone = "Europe/Amsterdam";
  i18n.defaultLocale = "nl_NL.UTF-8";
  i18n.extraLocales = [ "en_US.UTF-8/UTF-8" ];
  services.xserver.xkb = {
    layout = "us";
    variant = "euro";
  };
  console.keyMap = "us";

  # The offline image has no primary account: the installer creates it.
  # Installed user.json declares it on later rebuilds without resetting its password.
  users.mutableUsers = true;
  users.users = {
    root.hashedPassword = "!"; # root login disabled, use sudo
  }
  // lib.optionalAttrs (nixbookUser.name != null) {
    ${nixbookUser.name} = {
      isNormalUser = true;
      uid = 1000;
      description = nixbookUser.fullName;
      extraGroups = [
        "wheel"
        "networkmanager"
        "libvirtd"
        "nordvpn"
        "video"
        "audio"
      ];
    };
  };
  # A user that an earlier generation declared and this one does not is
  # deleted on activation, also with mutableUsers. Refuse that for normal
  # accounts, so an empty or wrong user.json cannot lock anyone out.
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
        echo "Zet de naam in /etc/nixos/hosts/elitebook/user.json, bijvoorbeeld:"
        echo "  {\"name\": \"''${missing%%[[:space:]]*}\", \"fullName\": \"...\"}"
        exit 1
      fi
    '';

  # Groups the installer gives the first user
  users.groups = {
    libvirtd = { };
    nordvpn = { };
  };

  # Printing with driverless (IPP Everywhere) printers, like nixbook
  services.printing = {
    enable = true;
    browsed.enable = false;
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    # Find printers, but never announce this laptop on the network
    publish.enable = false;
    openFirewall = true;
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  environment.systemPackages = with pkgs; [
    git
    libnotify
    sbctl
    tpm2-tools
  ];

  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      jetbrains-mono
    ];
    fontDir.enable = true;
  };

  documentation = {
    nixos.enable = false;
    doc.enable = false;
    info.enable = false;
  };

  # Logs: persistent but bounded
  services.journald.extraConfig = ''
    SystemMaxUse=300M
    MaxRetentionSec=1month
  '';

  # Fast boot: don't block on the network
  systemd.services.NetworkManager-wait-online.enable = false;
  networking.networkmanager.enable = true;
}
