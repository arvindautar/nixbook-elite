# Same fonts as Omarchy: Liberation Sans/Serif (metric compatible with Arial
# and Times New Roman) and JetBrainsMono Nerd Font. The UI font stays Adwaita
# Sans. Helvetica & co. resolve to TeX Gyre, which GNOME already pulls in.
{ pkgs, ... }:

let
  # From Omarchy's 50-omarchy.conf. Strong binding so the generic names always
  # map to these, flatpaks included.
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
      # Arial, Times New Roman and Courier New map to these through
      # 30-metric-aliases.conf
      liberation_ttf
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
    # flatpaks pick up fonts from /usr/share/fonts
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Liberation Sans" ];
        serif = [ "Liberation Serif" ];
        monospace = [ "JetBrainsMono Nerd Font" ];
        emoji = [ "Noto Color Emoji" ];
      };
      # same as Omarchy
      hinting.style = "slight";
      subpixel.rgba = "none";
      localConf = fontconfig;
    };
  };

  # Flatpaks don't read /etc/fonts, only ~/.config/fontconfig. Needs to be a
  # real file: the sandbox can't follow links into /nix/store, and a tmpfiles
  # C copy keeps root as owner, which fails as a user.
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
        font-antialiasing = "grayscale";
        font-hinting = "slight";
      };
    }
  ];
}
