# Builds `nixbook-install` for a given target system (real one for the ISO,
# an instrumented copy for the VM test).
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
    jq
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
