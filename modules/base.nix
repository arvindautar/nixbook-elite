# Nix, locale and other basics (based on nixbook's common.nix)
{
  pkgs,
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
      # only admins can talk to the nix daemon
      allowed-users = [ "@wheel" ];
      trusted-users = [ "root" ];
      max-jobs = "auto";
      download-buffer-size = 268435456;
    };
    # dedupe weekly instead of on every build
    optimise.automatic = true;
    # keep builds from making the desktop stutter
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    # flakes only, NIX_PATH points at the pinned nixpkgs
    channel.enable = false;
  };
  # don't build in the RAM backed /tmp
  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";

  # Dutch UI and formats, US keyboard with € on AltGr+5.
  # No time zone here so it can be changed in Settings.
  time.timeZone = null;
  # Default to Amsterdam when no zone is set: fresh installs, and laptops
  # installed when the flake still set the zone (NixOS removes its link on the
  # first rebuild).
  system.activationScripts.nixbookTimeZone = {
    deps = [ "etc" ];
    text = ''
      if [ ! -e /etc/localtime ]; then
        ln -sfn /etc/zoneinfo/Europe/Amsterdam /etc/localtime
      fi
    '';
  };
  i18n.defaultLocale = "nl_NL.UTF-8";
  i18n.extraLocales = [ "en_GB.UTF-8/UTF-8" ]; # British English, in Settings
  services.xserver.xkb = {
    layout = "us";
    variant = "euro";
  };
  console.keyMap = "us";

  # driverless (IPP Everywhere) printing, like nixbook
  services.printing = {
    enable = true;
    browsed.enable = false;
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    # discover printers, but don't announce ourselves
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

  documentation = {
    nixos.enable = false;
    doc.enable = false;
    info.enable = false;
  };

  # persistent logs, but capped
  services.journald.extraConfig = ''
    SystemMaxUse=300M
    MaxRetentionSec=1month
  '';

  # don't block boot on the network
  systemd.services.NetworkManager-wait-online.enable = false;
  networking.networkmanager.enable = true;
}
