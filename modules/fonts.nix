# Generic families follow openSUSE fonts-config. The GNOME interface font
# stays Adwaita Sans. Monospace stays JetBrainsMono Nerd Font.
{ pkgs, ... }:

let
  # Brave and LibreWolf. Leap 16 does not install Roboto Slab or Noto Serif,
  # so serif resolves to Liberation Serif. Sans resolves to Roboto. Leap's
  # fontconfig sends system-ui to Cantarell, which is not installed, and the
  # remaining face is Roboto. Hinting is slight and subpixel is RGB.
  browserFontconfig = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <alias>
        <family>sans-serif</family>
        <prefer>
          <family>Roboto</family>
          <family>Noto Sans</family>
          <family>Liberation Sans</family>
          <family>DejaVu Sans</family>
        </prefer>
      </alias>
      <alias>
        <family>serif</family>
        <prefer>
          <family>Liberation Serif</family>
          <family>DejaVu Serif</family>
        </prefer>
      </alias>
      <alias>
        <family>system-ui</family>
        <prefer><family>Roboto</family></prefer>
      </alias>
      <alias>
        <family>-apple-system</family>
        <prefer><family>Roboto</family></prefer>
      </alias>
      <alias>
        <family>BlinkMacSystemFont</family>
        <prefer><family>Roboto</family></prefer>
      </alias>
      <alias>
        <family>monospace</family>
        <prefer>
          <family>JetBrainsMono Nerd Font</family>
        </prefer>
      </alias>
      <match target="pattern">
        <test name="family"><string>ui-monospace</string></test>
        <edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit>
      </match>
      <match target="font">
        <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
      </match>
      <match target="font">
        <edit name="rgba" mode="assign"><const>rgb</const></edit>
      </match>
      <match target="font">
        <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
      </match>
    </fontconfig>
  '';

  fontconfig = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <alias>
        <family>sans-serif</family>
        <prefer>
          <family>Roboto</family>
          <family>Noto Sans</family>
          <family>Liberation Sans</family>
          <family>DejaVu Sans</family>
        </prefer>
      </alias>
      <alias>
        <family>serif</family>
        <prefer>
          <family>Noto Serif</family>
          <family>Liberation Serif</family>
          <family>DejaVu Serif</family>
        </prefer>
      </alias>
      <alias>
        <family>monospace</family>
        <prefer>
          <family>JetBrainsMono Nerd Font</family>
        </prefer>
      </alias>
      <!-- Replace the list. A later sans prefer would otherwise sit in front. -->
      <match target="pattern">
        <test name="family"><string>ui-monospace</string></test>
        <edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit>
      </match>

      <match target="font">
        <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
      </match>
      <match target="font">
        <edit name="rgba" mode="assign"><const>rgb</const></edit>
      </match>
      <match target="font">
        <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
      </match>
    </fontconfig>
  '';
in
{
  fonts = {
    packages = with pkgs; [
      # Roboto and Liberation are the faces Leap's browsers resolve.
      roboto
      liberation_ttf
      dejavu_fonts
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
    # flatpaks pick up fonts from /usr/share/fonts
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = {
        sansSerif = [
          "Roboto"
          "Noto Sans"
          "Liberation Sans"
          "DejaVu Sans"
        ];
        serif = [
          "Noto Serif"
          "Liberation Serif"
          "DejaVu Serif"
        ];
        monospace = [ "JetBrainsMono Nerd Font" ];
        emoji = [ "Noto Color Emoji" ];
      };
      hinting.style = "slight";
      subpixel.rgba = "rgb";
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
      ${pkgs.coreutils}/bin/install -D -m 0644 ${pkgs.writeText "50-nixbook-fonts.conf" browserFontconfig} \
        "$HOME/.config/fontconfig/conf.d/50-nixbook-fonts.conf"
      # Brave and LibreWolf keep their own font cache. A new face stays invisible
      # there until that cache is rebuilt.
      for app in com.brave.Browser io.gitlab.librewolf-community; do
        if ${pkgs.flatpak}/bin/flatpak info "$app" >/dev/null 2>&1; then
          ${pkgs.flatpak}/bin/flatpak run --command=fc-cache "$app" -f || true
        fi
      done
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
        font-rgba-order = "rgb";
      };
    }
  ];
}
