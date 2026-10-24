# Nix, locale, users and the basics (adapted from nixbook common.nix)
{ pkgs, lib, ... }:

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

  # Passwords stay off the Nix store. The account is declared so group
  # membership survives a rebuild; the existing password is left alone.
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!"; # root login disabled, use sudo
  users.users.gebruiker = {
    isNormalUser = true;
    uid = 1000;
    description = "gebruiker";
    extraGroups = [
      "wheel"
      "networkmanager"
      "libvirtd"
      "nordvpn"
      "video"
      "audio"
    ];
  };
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
