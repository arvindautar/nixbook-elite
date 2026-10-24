# Spell checking for Dutch and British English: Hunspell dictionaries for
# GNOME apps (enchant) and Firefox (DICPATH). Brave and ONLYOFFICE bring their own.
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
