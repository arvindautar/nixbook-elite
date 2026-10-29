# Font matching and rendering as on Ubuntu 26.04 LTS, for the system and for
# Flatpaks. Two choices differ from Ubuntu: GNOME keeps Adwaita Sans (dconf
# is left alone), and monospace is JetBrainsMono Nerd Font.
{ lib, pkgs, ... }:

let
  # Ubuntu 26.04's fonts.conf and every conf.d file it enables, copied
  # unchanged from fontconfig-config 2.17.1-3ubuntu1, fonts-dejavu-core and
  # fonts-dejavu-mono 2.37-8build1, and fonts-noto-cjk 20240730+repack1-1build1.
  # Left out are 51-local.conf, whose place `nixbook` takes, and
  # fonts-ubuntu's 71-ubuntulegacy.conf, which only hides Ubuntu fonts.
  ubuntuFile = name: builtins.readFile (./fontconfig-ubuntu + "/${name}");
  ubuntu =
    name:
    let
      body = lib.last (lib.splitString "<fontconfig>" (ubuntuFile "${name}.conf"));
    in
    "<!-- Ubuntu ${name}.conf -->\n" + lib.head (lib.splitString "</fontconfig>" body);

  # This laptop's choices, in 51-local.conf's place
  nixbook = ''
    <!-- Monospace stays JetBrainsMono Nerd Font. Ubuntu's DejaVu Sans Mono,
         Noto Mono and Noto Sans Mono follow from 60-latin. -->
    <alias>
      <family>monospace</family>
      <prefer><family>JetBrainsMono Nerd Font</family></prefer>
    </alias>
    <!-- Replace the list. A later sans prefer would otherwise sit in front. -->
    <match target="pattern">
      <test name="family"><string>ui-monospace</string></test>
      <edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit>
    </match>
    <!-- Ubuntu has none of the faces 60-latin prefers for system-ui, so web
         pages get its sans-serif. Adwaita Sans is installed here for GNOME,
         so skip the system-ui list instead. -->
    <match target="pattern">
      <test name="family"><string>system-ui</string></test>
      <edit name="family" mode="assign"><string>sans-serif</string></edit>
    </match>
  '';

  # The system: NixOS's conf.d is upstream fontconfig 2.17.1 like Ubuntu's,
  # with hinting, subpixel and bitmaps set by the options below to the same
  # files Ubuntu enables. This adds the rest as local.conf (51), so 57- to 70-
  # run in Ubuntu's order and before the system's own 60-latin and 65-nonlatin.
  # Each must run once: a second 57-dejavu-sans after 58-dejavu-lgc-sans puts
  # DejaVu Sans in front of Noto Sans.
  systemConf = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
    ${lib.concatMapStrings ubuntu [
      "20-unhint-small-dejavu-lgc-sans"
      "20-unhint-small-dejavu-lgc-sans-mono"
      "20-unhint-small-dejavu-lgc-serif"
      "20-unhint-small-dejavu-sans"
      "20-unhint-small-dejavu-sans-mono"
      "20-unhint-small-dejavu-serif"
      "40-nonlatin"
    ]}
    ${nixbook}
    ${lib.concatMapStrings ubuntu [
      "57-dejavu-sans"
      "57-dejavu-sans-mono"
      "57-dejavu-serif"
      "58-dejavu-lgc-sans"
      "58-dejavu-lgc-sans-mono"
      "58-dejavu-lgc-serif"
      "60-latin"
      "65-nonlatin"
      "70-fonts-noto-cjk"
    ]}
    </fontconfig>
  '';

  # Flatpaks: Ubuntu's whole configuration instead of their runtime's, which
  # has its own fonts, Liberation and FreeFont aliases, 10-sub-pixel-none
  # and, on GNOME 51, fontconfig 2.18's guessed generic families. Only the font
  # and cache directories change, to the ones the runtime's 50-flatpak.conf uses.
  # `extra` goes in 51-local.conf's place too, after this laptop's rules.
  flatpakConf =
    extra:
    let
      replace =
        from: to: text:
        assert lib.assertMsg (lib.hasInfix from text) "fontconfig-ubuntu/fonts.conf has no ${from}";
        lib.replaceStrings [ from ] [ to ] text;
      confD = lib.concatMapStrings ubuntu [
        "10-hinting-slight"
        "10-scale-bitmap-fonts"
        "10-sub-pixel-rgb"
        "10-yes-antialias"
        "11-lcdfilter-default"
        "20-unhint-small-dejavu-lgc-sans"
        "20-unhint-small-dejavu-lgc-sans-mono"
        "20-unhint-small-dejavu-lgc-serif"
        "20-unhint-small-dejavu-sans"
        "20-unhint-small-dejavu-sans-mono"
        "20-unhint-small-dejavu-serif"
        "20-unhint-small-vera"
        "30-metric-aliases"
        "40-nonlatin"
        "45-generic"
        "45-latin"
        "48-spacing"
        "49-sansserif"
        "50-user"
      ];
      confD' = lib.concatMapStrings ubuntu [
        "57-dejavu-sans"
        "57-dejavu-sans-mono"
        "57-dejavu-serif"
        "58-dejavu-lgc-sans"
        "58-dejavu-lgc-sans-mono"
        "58-dejavu-lgc-serif"
        "60-generic"
        "60-latin"
        "65-fonts-persian"
        "65-nonlatin"
        "69-unifont"
        "70-fonts-noto-cjk"
        "70-no-bitmaps-except-emoji"
        "80-delicious"
        "90-synthetic"
      ];
    in
    lib.pipe (ubuntuFile "fonts.conf") [
      (replace "\t<dir>/usr/share/fonts</dir>\n\t<dir>/usr/local/share/fonts</dir>\n" (
        lib.concatMapStrings (dir: "\t<dir>${dir}</dir>\n") [
          "/app/share/fonts"
          "/run/host/fonts"
          "/run/host/local-fonts"
          "/run/host/user-fonts"
        ]
        # maps /run/host/fonts to the system path, so caches match
        + "\t<include ignore_missing=\"yes\">/run/host/font-dirs.xml</include>\n"
      ))
      (replace "\t<include ignore_missing=\"yes\">conf.d</include>\n" ''
        ${confD}
        ${nixbook}
        ${extra}
        <!-- an app's own settings, as the runtime's 50-flatpak.conf loads them -->
        <include ignore_missing="yes">/app/etc/fonts/local.conf</include>
        <!-- The runtime's fonts stay out even though no dir lists them:
             fontconfig also uses every cache in the app's cache directory, and
             that has the runtime's from before. -->
        <selectfont>
          <rejectfont><glob>/usr/share/fonts/*</glob></rejectfont>
        </selectfont>
        ${confD'}
      '')
      (replace "\t<cachedir>/var/cache/fontconfig</cachedir>\n" (
        "\t<cachedir>/run/host/fonts-cache</cachedir>\n"
        + "\t<cachedir>/run/host/user-fonts-cache</cachedir>\n"
      ))
    ];

  # Brave and LibreWolf only. Their tabs and menus, and pages that ask for
  # system-ui, get GNOME's interface font by name, not through fontconfig's
  # system-ui. Noto Sans reads better in a browser. Strong, because Chromium
  # ignores weaker substitutes. GNOME and the other apps keep Adwaita Sans.
  browsers = [
    "com.brave.Browser"
    "io.gitlab.librewolf-community"
  ];
  browserConf = flatpakConf ''
    <match target="pattern">
      <test name="family"><string>Adwaita Sans</string></test>
      <edit name="family" mode="assign" binding="strong"><string>Noto Sans</string></edit>
    </match>
  '';
in
{
  fonts = {
    # Ubuntu's set: no Unifont, FreeFont or TeX Gyre, so Helvetica gets
    # Liberation Sans. GNOME adds Adwaita Sans and Adwaita Mono.
    enableDefaultPackages = false;
    packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
    ];
    # Flatpaks see the system fonts through /run/current-system/sw/share/X11/fonts
    fontDir.enable = true;
    fontconfig = {
      # NixOS adds these with binding="same", which outranks a language match
      # and would put Noto Sans before Noto Sans CJK JP for Japanese. The
      # families come from systemConf instead.
      defaultFonts = {
        sansSerif = [ ];
        serif = [ ];
        monospace = [ ];
        emoji = [ ];
      };
      # keeps upstream's 70-no-bitmaps-except-emoji, as on Ubuntu
      allowBitmaps = false;
      hinting.style = "slight";
      subpixel.rgba = "rgb";
      localConf = systemConf;
    };
  };

  # Flatpaks don't read /etc/fonts. The file has to be real and in the home
  # directory: the sandbox can't follow links into /nix/store, and a tmpfiles
  # C copy keeps root as owner, which fails as a user. It sits outside conf.d,
  # so the system doesn't load it.
  systemd.user.services.nixbook-fontconfig = {
    description = "Give Flatpaks Ubuntu's font settings";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "!@system"; # not the GDM greeter
    serviceConfig.Type = "oneshot";
    script = ''
            conf="$HOME/.config/fontconfig/nixbook-flatpak.conf"
            ${pkgs.coreutils}/bin/install -D -m 0644 ${pkgs.writeText "nixbook-flatpak.conf" (flatpakConf "")} "$conf"
            ${pkgs.flatpak}/bin/flatpak override --user --env=FONTCONFIG_FILE="$conf"
            # an app's own override wins over the global one
            browserConf="$HOME/.config/fontconfig/nixbook-flatpak-browsers.conf"
            ${pkgs.coreutils}/bin/install -D -m 0644 ${pkgs.writeText "nixbook-flatpak-browsers.conf" browserConf} "$browserConf"
            for app in ${lib.concatStringsSep " " browsers}; do
              ${pkgs.flatpak}/bin/flatpak override --user "$app" --env=FONTCONFIG_FILE="$browserConf"
            done
            # Earlier versions put their rules in conf.d, which the system also reads.
            ${pkgs.coreutils}/bin/rm -f "$HOME/.config/fontconfig/conf.d/50-nixbook-fonts.conf"
            # Every Flatpak keeps its own cache of the system fonts, and fontconfig
            # trusts it while the directory's date matches. Store paths are always
            # dated 1970, so after an update that adds or removes fonts the apps
            # would keep the old list, missing files included. The directory's
            # store path changes exactly then: drop the caches once, each app
            # rebuilds its own on the next start. Brave's own fontconfig writes a
            # differently named cache, which this also catches.
            fonts=$(${pkgs.coreutils}/bin/readlink -f /run/current-system/sw/share/X11/fonts)
            stamp="$HOME/.local/state/nixbook/flatpak-fonts"
            if [ "$(${pkgs.coreutils}/bin/cat "$stamp" 2>/dev/null)" != "$fonts" ]; then
              if [ -d "$HOME/.var/app" ]; then
                ${pkgs.findutils}/bin/find "$HOME/.var/app" -mindepth 4 -maxdepth 4 \
                  -path '*/cache/fontconfig/*' -name '*cache-*' -delete
              fi
              ${pkgs.coreutils}/bin/install -D -m 0644 /dev/null "$stamp"
              printf '%s\n' "$fonts" > "$stamp"
            fi
            # Brave substitutes its own default before it asks fontconfig. The generic
            # word "serif" then misses Noto Serif, so the profile has to name the
            # families. Create that file before Brave's first start. A first launch
            # keeps these names and fills in the rest of the profile. LibreWolf asks
            # fontconfig for the generic names and needs no profile edit.
            prefs="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default/Preferences"
            if ! ${pkgs.procps}/bin/pgrep -u "$(${pkgs.coreutils}/bin/id -u)" -f /app/brave/brave >/dev/null 2>&1; then
              ${pkgs.python3}/bin/python3 - "$prefs" <<'PY' || true
      import json, os, sys, tempfile
      path = sys.argv[1]
      existed = os.path.exists(path)
      if existed:
          try:
              with open(path) as handle:
                  data = json.load(handle)
          except (OSError, json.JSONDecodeError):
              sys.exit(0)
      else:
          data = {}
      fonts = data.setdefault("webkit", {}).setdefault("webprefs", {}).setdefault("fonts", {})
      want = {
          "standard": "Noto Sans",
          "sansserif": "Noto Sans",
          "serif": "Noto Serif",
          "fixed": "JetBrainsMono Nerd Font",
      }
      changed = not existed
      for key, family in want.items():
          current = fonts.get(key)
          if not isinstance(current, dict):
              current = {}
          if current.get("Zyyy") == family:
              continue
          current = dict(current)
          current["Zyyy"] = family
          fonts[key] = current
          changed = True
      if not changed:
          sys.exit(0)
      os.makedirs(os.path.dirname(path), exist_ok=True)
      fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".prefs.")
      try:
          with os.fdopen(fd, "w") as handle:
              json.dump(data, handle, separators=(",", ":"))
          os.replace(tmp, path)
      except OSError:
          try:
              os.unlink(tmp)
          except OSError:
              pass
      PY
            fi
    '';
  };
  systemd.user.tmpfiles.rules = [
    # Ghostty's builtin font has no Nerd Font glyphs. 'f' only writes the file
    # if it doesn't exist yet.
    "d %h/.config/ghostty - - - -"
    "f %h/.config/ghostty/config - - - - font-family = JetBrainsMono Nerd Font\\n"
  ];
  # At activation because nix-flatpak only applies overrides once online.
  # `flatpak override` merges with whatever is already there.
  system.activationScripts.flatpakFontconfig = ''
    ${pkgs.flatpak}/bin/flatpak override --system --filesystem=xdg-config/fontconfig:ro
  '';

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        monospace-font-name = "JetBrainsMono Nerd Font 11";
        # Ubuntu's session override. Hinting and RGBA order stay at the schema
        # defaults Ubuntu also keeps: slight, and rgb.
        font-antialiasing = "rgba";
        font-hinting = "slight";
        font-rgba-order = "rgb";
      };
    }
  ];
}
