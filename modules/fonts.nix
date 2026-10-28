# Fonts as on Omarchy: Liberation Sans and Serif (metric-compatible with Arial
# and Times New Roman, so documents keep their layout) and JetBrainsMono Nerd
# Font. GNOME's own interface font stays Adwaita Sans. Helvetica, Palatino and
# the other PostScript fonts get TeX Gyre (GNOME's default fonts), the
# TrueType successor of the URW fonts Omarchy uses for them.
{ pkgs, ... }:

let
  # Omarchy's 50-omarchy.conf. A strong assign, so a page or app asking for
  # sans-serif, serif or monospace always gets these, also inside Flatpaks.
  fontconfig = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <match target="pattern">
        <test name="family" qual="any"><string>sans-serif</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Liberation Sans</string></edit>
      </match>
      <match target="pattern">
        <test name="family" qual="any"><string>serif</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Liberation Serif</string></edit>
      </match>
      <match target="pattern">
        <test name="family" qual="any"><string>monospace</string></test>
        <edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit>
      </match>

      <!-- The system font websites ask for -->
      <alias><family>system-ui</family><prefer><family>Liberation Sans</family></prefer></alias>
      <alias><family>-apple-system</family><prefer><family>Liberation Sans</family></prefer></alias>
      <alias><family>BlinkMacSystemFont</family><prefer><family>Liberation Sans</family></prefer></alias>
      <alias><family>ui-monospace</family><default><family>monospace</family></default></alias>
    </fontconfig>
  '';
in
{
  fonts = {
    packages = with pkgs; [
      # fontconfig's metric aliases then give Arial, Times New Roman and
      # Courier New these Liberation fonts
      liberation_ttf
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
    # Flatpaks see the fonts through /usr/share/fonts
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Liberation Sans" ];
        serif = [ "Liberation Serif" ];
        monospace = [ "JetBrainsMono Nerd Font" ];
        emoji = [ "Noto Color Emoji" ];
      };
      # Same as Omarchy: slight hinting, grayscale antialiasing
      hinting.style = "slight";
      subpixel.rgba = "none";
      localConf = fontconfig;
    };
  };

  # Flatpaks don't read /etc/fonts, only ~/.config/fontconfig (read-only).
  # A real file owned by the account: the sandbox can't follow links into
  # /nix/store, and tmpfiles' copy keeps root as owner, which a user can't set.
  systemd.user.services.nixbook-fontconfig = {
    description = "Copy the font settings where Flatpaks read them";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "!@system"; # not the GDM greeter
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.coreutils}/bin/install -D -m 0644 ${pkgs.writeText "50-nixbook-fonts.conf" fontconfig} \
        "$HOME/.config/fontconfig/conf.d/50-nixbook-fonts.conf"
    '';
  };
  systemd.user.tmpfiles.rules = [
    # Ghostty's own default has no Nerd Font icons. Only written when the
    # account has no Ghostty config yet, so later changes stay.
    "d %h/.config/ghostty - - - -"
    "f %h/.config/ghostty/config - - - - font-family = JetBrainsMono Nerd Font\\n"
  ];
  # Written at activation, not by nix-flatpak's install job, which only runs
  # once online. flatpak override merges, so other global overrides stay.
  system.activationScripts.flatpakFontconfig = ''
    ${pkgs.flatpak}/bin/flatpak override --system --filesystem=xdg-config/fontconfig:ro
  '';

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        monospace-font-name = "JetBrainsMono Nerd Font 11";
        font-antialiasing = "grayscale";
        font-hinting = "slight";
      };
    }
  ];
}
