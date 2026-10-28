# NordVPN daemon, CLI and GUI. Module and package come from unstable, 26.05
# doesn't have them.
{
  inputs,
  pkgs-unstable,
  ...
}:

{
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/networking/nordvpn.nix"
  ];

  services.nordvpn = {
    enable = true;
    package = pkgs-unstable.nordvpn;
  };

  # The module starts nordvpnd from graphical.target without requiring the
  # socket, so on a rebuild the daemon can come up first and the switch fails
  # with "Socket service already active".
  systemd.services.nordvpnd.requires = [ "nordvpnd.socket" ];
}
