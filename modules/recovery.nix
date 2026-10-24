# Secure Boot keys and the LUKS header. The disk unlock is the passphrase.
{
  pkgs,
  ...
}:

let
  disk = "/dev/disk/by-label/NIXCRYPT";
  store = "/root/nixbook-recovery";

  backup = pkgs.writeShellScriptBin "nixbook-backup-recovery" ''
    set -euo pipefail
    [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
    dest="''${1:-}"
    [ -n "$dest" ] || {
      echo "Gebruik: sudo nixbook-backup-recovery /pad/op/een/andere/schijf"
      echo "Voorbeeld: een USB-stick. De kopie op deze schijf helpt niet als de SSD stuk gaat."
      exit 1
    }
    mkdir -p ${store} "$dest"
    chmod 700 ${store} "$dest"
    rm -rf ${store}/sbctl "$dest/sbctl"
    # A USB stick is usually FAT: it has no owners, and cp -a as root fails
    # there, so copies to $dest keep only mode and time.
    copy() { cp -r --preserve=mode,timestamps "$@"; }
    cp -a /var/lib/sbctl ${store}/sbctl
    copy /var/lib/sbctl "$dest/sbctl"
    # luksHeaderBackup refuses to overwrite, and this is meant to be run again
    rm -f ${store}/luks-header.bin
    ${pkgs.cryptsetup}/bin/cryptsetup luksHeaderBackup ${disk} \
      --header-backup-file ${store}/luks-header.bin
    copy ${store}/luks-header.bin "$dest/luks-header.bin"
    chmod -R go-rwx ${store} "$dest"
    cat > ${store}/README.txt <<'EOF'
    nixbook-recovery

    sbctl/            Private Secure Boot-sleutels. Zonder deze map kan een
                      nieuwe generatie niet getekend worden.
    luks-header.bin   Reservekopie van de LUKS-header. De wachtzin opent
                      niets als de header op de SSD kapot is.

    Bewaar deze map op een andere schijf, niet alleen op deze laptop.
    De schijf gaat open met de lange wachtzin. Er is geen PIN.
    De USB-installatiestick start niet terwijl Secure Boot aanstaat.
    Voor een herinstallatie: F10, Secure Boot uit, van de stick starten.
    EOF
    copy ${store}/README.txt "$dest/README.txt"
    chmod 600 ${store}/README.txt "$dest/README.txt"
    echo "Klaar: ${store} en $dest"
    echo "Haal de andere schijf uit de laptop en leg hem apart."
  '';
in
{
  environment.systemPackages = [ backup ];
}
