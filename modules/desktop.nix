# Full GNOME desktop, no bundled apps: Ghostty, Bazaar, Nautilus and VS Code only.
# Everything else comes from Flathub via Bazaar.
{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

{
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Keep the GNOME platform (shell, settings, portals, keyring, GVfs...), drop the apps
  services.gnome.core-apps.enable = false;
  services.gnome.core-developer-tools.enable = false;
  services.gnome.games.enable = false;
  # Nothing that could expose this laptop on a network
  services.gnome.gnome-remote-desktop.enable = false;
  services.gnome.gnome-user-share.enable = false;
  services.gnome.rygel.enable = false;
  services.gnome.gnome-browser-connector.enable = false;
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    gnome-user-docs
    gnome-software # replaced by Bazaar
  ];

  # System tools that are not on Flathub
  programs.gnome-disks.enable = true;
  services.gnome.sushi.enable = true; # spacebar preview in Nautilus

  environment.systemPackages = [
    pkgs.ghostty
    pkgs.nautilus # not on Flathub
    pkgs.gnome-system-monitor # not on Flathub
    # FHS variant: extensions that ship their own binaries (language servers etc.) work
    pkgs.vscode.fhs
    pkgs-unstable.bazaar
    pkgs-unstable.gnomeExtensions.appindicator # tray icons (NordVPN GUI)
  ];

  # "Open in Ghostty" in Nautilus, and Ghostty as the default terminal
  programs.nautilus-open-any-terminal = {
    enable = true;
    terminal = "ghostty";
  };
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "com.mitchellh.ghostty.desktop" ];
  };

  # The Brave Flatpak reads the host's /etc/brave/policies. This turns off what
  # Brave sends on its own. Safe Browsing, component updates (ad-block lists,
  # certificate revocation) and variations (remote fixes) stay on for security;
  # Leo (AI) is off, like Brave Origin; Translate, Sync, Wayback Machine and search
  # suggestions stay the user's choice.
  # A real file, not a symlink: the sandbox can't see /etc/static (/nix/store).
  environment.etc."brave/policies/managed/nixbook.json".mode = "0444";
  environment.etc."brave/policies/managed/nixbook.json".text = builtins.toJSON {
    # Telemetry and pings
    BraveP3AEnabled = false;
    BraveStatsPingEnabled = false;
    BraveWebDiscoveryEnabled = false;
    MetricsReportingEnabled = false;
    # Brave services nobody here uses (the wallet is also attack surface)
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    BraveNewsDisabled = true;
    BraveTalkDisabled = true;
    # Leo, the AI assistant: sends what you ask (and page content) to Brave's servers
    BraveAIChatEnabled = false;
    # Don't preload pages you never open
    NetworkPredictionOptions = 2;
    # Closing the last window really quits, so an update is used on the next start
    BackgroundModeEnabled = false;
  };

  # Sensible GNOME defaults (users can change all of them)
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/shell" = {
          favorite-apps = [
            "com.brave.Browser.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.kolunmi.Bazaar.desktop"
          ];
          enabled-extensions = [
            "appindicatorsupport@rgcjonas.gmail.com"
            "dash-to-dock@micxgx.gmail.com"
            "blur-my-shell@aunetx"
            "gradia-integration@alexandervanhee.github.io"
          ];
        };
        "org/gnome/desktop/input-sources" = {
          sources = [
            (lib.gvariant.mkTuple [
              "xkb"
              "us+euro"
            ])
          ];
        };
        "org/gnome/desktop/interface" = {
          show-battery-percentage = true;
          clock-show-weekday = true;
        };
        # Week numbers in the top bar clock/calendar
        "org/gnome/desktop/calendar".show-weekdate = true;
        "org/gnome/desktop/wm/preferences".button-layout = "appmenu:minimize,maximize,close";
        "org/gnome/desktop/peripherals/touchpad" = {
          tap-to-click = true;
        };
        "org/gnome/mutter" = {
          edge-tiling = true;
          dynamic-workspaces = true;
        };
        # Privacy
        "org/gnome/system/location".enabled = false;
        "org/gnome/desktop/privacy" = {
          report-technical-problems = false;
          send-software-usage-stats = false;
          remove-old-trash-files = true;
          remove-old-temp-files = true;
          old-files-age = lib.gvariant.mkUint32 30;
          recent-files-max-age = lib.gvariant.mkInt32 30;
        };
        "org/gnome/desktop/screensaver".lock-enabled = true;
        "org/gnome/desktop/notifications".show-in-lock-screen = false;
        "org/gnome/desktop/search-providers".disable-external = false;
      };
    }
  ];

  # Default apps (Flatpaks from flatpak.nix)
  xdg.mime.defaultApplications =
    let
      for = app: types: lib.genAttrs types (_: app);
    in
    for "com.brave.Browser.desktop" [
      "text/html"
      "application/xhtml+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ]
    // for "org.gnome.Papers.desktop" [ "application/pdf" ]
    // for "io.github.diegopvlk.Cine.desktop" [
      "video/mp4"
      "video/x-matroska"
      "video/webm"
      "video/quicktime"
      "video/x-msvideo"
      "video/mpeg"
      "video/ogg"
    ]
    // for "org.gnome.Decibels.desktop" [
      "audio/mpeg"
      "audio/flac"
      "audio/ogg"
      "audio/opus"
      "audio/x-opus+ogg"
      "audio/wav"
      "audio/x-wav"
      "audio/mp4"
      "audio/aac"
    ]
    // for "org.onlyoffice.desktopeditors.desktop" [
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      "application/msword"
      "application/vnd.ms-excel"
      "application/vnd.ms-powerpoint"
      "application/vnd.oasis.opendocument.text"
      "application/vnd.oasis.opendocument.spreadsheet"
      "application/vnd.oasis.opendocument.presentation"
      "text/csv"
    ];

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
}
