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
}
