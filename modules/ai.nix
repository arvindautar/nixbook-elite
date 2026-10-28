# AI coding CLIs from unstable, updated with the weekly system update
{ pkgs-unstable, ... }:

{
  environment.systemPackages = with pkgs-unstable; [
    claude-code
    codex
    grok-build
  ];
}
