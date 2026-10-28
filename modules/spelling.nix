# Dutch and British English hunspell dictionaries for GNOME apps (enchant)
# and the hunspell CLI. Flatpaks and ONLYOFFICE ship their own.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    hunspell
    hunspellDicts.nl_NL
    hunspellDicts.en_GB-ise
  ];
  environment.pathsToLink = [ "/share/hunspell" ];
  environment.sessionVariables.DICPATH = "/run/current-system/sw/share/hunspell";
}
