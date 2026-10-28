#!/usr/bin/env bash
# nixbook-install: offline installer for the HP EliteBook 840 G10.
# The @...@ placeholders are filled in by installer/script.nix.
# Creates the first account. It's not added to the flake, accounts.nix takes
# care of its groups and subuid ranges.
# For tests: NB_USER NB_FULLNAME NB_PASSWORD NB_LUKS NB_CONFIRM=yes
set -euo pipefail

TOPLEVEL="@toplevel@"
DISKO="@disko@"
FLAKE_SRC="@flake@"
# users and groups the system already has
RESERVED=" @reserved@ "
DISK="/dev/nvme0n1"
KEYFILE="/tmp/nixbook-luks.key"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31mFOUT: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
[ -d /sys/firmware/efi ] || die "Niet in UEFI-modus opgestart. Zet in het BIOS 'Legacy' uit."
[ -b "$DISK" ] || die "$DISK niet gevonden."

valid_user() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] && [[ "$RESERVED" != *" $1 "* ]]
}
# useradd doesn't accept ':' or control characters in the comment field
valid_fullname() {
  [[ "$1" != *[[:cntrl:]:]* ]]
}

ask_secret() { # prompt, var, minlen
  local a b
  while true; do
    read -r -s -p "$1: " a; echo
    read -r -s -p "Herhaal: " b; echo
    [ "$a" = "$b" ] || { echo "Komt niet overeen."; continue; }
    [ "${#a}" -ge "$3" ] || { echo "Minimaal $3 tekens."; continue; }
    printf -v "$2" '%s' "$a"; return
  done
}

bold "nixbook-elite installatie"
lsblk -d -o NAME,SIZE,MODEL "$DISK"
echo
echo "ALLE gegevens op $DISK worden gewist."

if [ -z "${NB_USER:-}" ]; then
  while true; do
    read -r -p "Gebruikersnaam (kleine letters): " NB_USER
    valid_user "$NB_USER" && break
    echo "Ongeldige of al gebruikte naam."
  done
  while true; do
    read -r -p "Volledige naam: " NB_FULLNAME
    valid_fullname "$NB_FULLNAME" && break
    echo "Geen dubbele punt (:) in de naam."
  done
  ask_secret "Wachtwoord voor $NB_USER" NB_PASSWORD 8
  echo
  echo "Schijfversleuteling: kies een lange wachtzin (bijv. 5+ woorden)."
  echo "Die typ je bij elke start. Kwijt = alle gegevens kwijt."
  ask_secret "LUKS-wachtzin" NB_LUKS 12
fi
valid_user "$NB_USER" || die "Ongeldige gebruikersnaam: $NB_USER"
valid_fullname "${NB_FULLNAME:-}" || die "Ongeldige volledige naam."
# check before anything gets wiped
[ -n "${NB_PASSWORD:-}" ] && [ -n "${NB_LUKS:-}" ] || die "Wachtwoord of LUKS-wachtzin ontbreekt."
if [ "${NB_CONFIRM:-}" != "yes" ]; then
  read -r -p "Typ WISSEN om $DISK te wissen en te installeren: " c
  [ "$c" = "WISSEN" ] || die "Geannuleerd."
fi

# for the Secure Boot hints at the end
setup_mode=0
for f in /sys/firmware/efi/efivars/SetupMode-*; do
  if [ -e "$f" ] && [ "$(od -An -t u1 -j4 -N1 "$f" | tr -d ' ')" = "1" ]; then
    setup_mode=1
  fi
done

# HP Sure Start puts the factory keys back after enrollment unless this is off
sb_protect=$(cat "/sys/class/firmware-attributes/hp-bioscfg/attributes/Sure Start Secure Boot Keys Protection/current_value" 2>/dev/null || true)

bold "1/4 Partitioneren en versleutelen (LUKS2 + btrfs)"
(umask 077 && printf '%s' "$NB_LUKS" > "$KEYFILE")
trap 'rm -f "$KEYFILE"' EXIT
"$DISKO"
rm -f "$KEYFILE"

bold "2/4 Systeem installeren (offline)"
nixos-install --system "$TOPLEVEL" --no-root-passwd --no-channel-copy

bold "3/4 Gebruiker aanmaken"
# admin with all the extra groups, accounts.nix adds subuid ranges on first boot
printf -v account_command 'useradd -m -u 1000 -c %q -G wheel,networkmanager,libvirtd,nordvpn,video,audio %q' \
  "${NB_FULLNAME:-$NB_USER}" "$NB_USER"
nixos-enter --root /mnt -c "$account_command"
printf '%s:%s\n' "$NB_USER" "$NB_PASSWORD" | nixos-enter --root /mnt -c chpasswd

bold "4/4 Configuratie naar /etc/nixos kopiëren"
# DESKTOP- plus 7 random characters, like a fresh Windows install. The flake
# sets no hostname, so NixOS leaves this file alone, and hostnamed reads it.
chars=ABCDEFGHJKLMNPQRSTUVWXYZ0123456789
host=DESKTOP-
for b in $(od -An -N7 -tu1 /dev/urandom); do host+=${chars:$((b % ${#chars})):1}; done
printf '%s\n' "$host" > /mnt/etc/hostname
mkdir -p /mnt/etc/nixos
cp -rT "$FLAKE_SRC" /mnt/etc/nixos
chmod -R u+w /mnt/etc/nixos
sync

bold "Klaar!"
cat <<EOF
Verwijder de USB-stick en herstart. Na het invoeren van de wachtzin log je in
als $NB_USER.

Secure Boot:
EOF
if [ "$setup_mode" = 1 ]; then
  echo "  Firmware staat in Setup Mode: eigen sleutels worden automatisch"
  echo "  aangemaakt en ingeschreven (de laptop herstart 1x vanzelf)."
else
  echo "  Firmware staat NIET in Setup Mode. Na de eerste start:"
  echo "  F10 -> Beveiliging -> Secure Boot-configuratie -> 'Clear Secure Boot keys'."
  echo "  Bij de volgende start worden de sleutels ingeschreven."
fi
if [ "$sb_protect" = Enable ]; then
  echo
  echo "  LET OP: 'Sure Start Secure Boot Keys Protection' staat aan. Zet die eerst uit"
  echo "  (F10 -> Beveiliging -> Sure Start), anders zet HP de fabriekssleutels terug."
fi
echo
echo "  Zet Secure Boot pas aan als 'nixbook-secureboot' zegt dat je eigen sleutels"
echo "  in de firmware staan; anders start de laptop niet."
echo
echo "  Deze stick start niet zolang Secure Boot aanstaat. Voor een herinstallatie"
echo "  eerst F10 -> Secure Boot uit, dan van de stick starten."
