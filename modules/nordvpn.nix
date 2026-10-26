# NordVPN daemon + CLI + GUI, using the module and package from nixos-unstable
# (not in 26.05). Run `nordvpn login` or open "NordVPN" from the app grid.
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

  # The module starts the daemon from graphical.target without requiring its
  # socket. On a rebuild the daemon could then come back first, and systemd
  # refuses to start the socket ("Socket service already active"), failing the switch.
  systemd.services.nordvpnd.requires = [ "nordvpnd.socket" ];
}
