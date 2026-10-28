# Builds nixbook-install for a target system: the real one for the ISO, the
# instrumented one for the VM test.
{
  pkgs,
  lib,
  target,
  flakeSource,
}:

pkgs.writeShellApplication {
  name = "nixbook-install";
  runtimeInputs = with pkgs; [
    util-linux
    coreutils
    nixos-install-tools
  ];
  text =
    lib.replaceStrings
      [ "@toplevel@" "@disko@" "@flake@" "@reserved@" ]
      [
        "${target.config.system.build.toplevel}"
        "${target.config.system.build.diskoScript}"
        "${flakeSource}"
        (lib.concatStringsSep " " (
          lib.attrNames target.config.users.users ++ lib.attrNames target.config.users.groups
        ))
      ]
      (builtins.readFile ./install.sh);
}
