# AI coding tools, always from nixos-unstable (updated weekly with the system)
{ pkgs-unstable, ... }:

{
  environment.systemPackages = with pkgs-unstable; [
    claude-code
    codex
    grok-build
  ];
}
