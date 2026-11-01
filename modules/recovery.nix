# Copies the Secure Boot keys and a LUKS header backup off the laptop.
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
    # USB sticks are usually FAT. cp -a fails on ownership there, and FAT
    # refuses a chmod it can't store.
    copy() { cp -r --preserve=mode,timestamps "$@"; }
    private() { chmod "$@" 2>/dev/null || true; }
    mkdir -p ${store} "$dest"
    chmod 700 ${store}
    private 700 "$dest"
    rm -rf ${store}/sbctl
    cp -a /var/lib/sbctl ${store}/sbctl
    # the old copy goes only once the new one is complete
    rm -rf "$dest/sbctl.new"
    copy /var/lib/sbctl "$dest/sbctl.new"
    rm -rf "$dest/sbctl"
    mv "$dest/sbctl.new" "$dest/sbctl"
    # luksHeaderBackup won't overwrite, and this is meant to be rerun
    rm -f ${store}/luks-header.bin
    ${pkgs.cryptsetup}/bin/cryptsetup luksHeaderBackup ${disk} \
      --header-backup-file ${store}/luks-header.bin
    copy ${store}/luks-header.bin "$dest/luks-header.bin"
    # made by the first nixbook-backup-home
    if [ -s ${store}/restic-password ]; then
      copy ${store}/restic-password "$dest/restic-password"
    fi
    chmod -R go-rwx ${store}
    private -R go-rwx "$dest"
    cat > ${store}/README.txt <<'EOF'
    nixbook-recovery

    sbctl/            Private Secure Boot-sleutels. Zonder deze map kan een
                      nieuwe generatie niet getekend worden.
    luks-header.bin   Reservekopie van de LUKS-header. De wachtzin opent
                      niets als de header op de SSD kapot is.
    restic-password   Wachtwoord van de back-up op de NIXBACKUP-schijf. Zonder
                      dit bestand is die back-up niet terug te zetten. Staat
                      er alleen als er al een back-up is gemaakt.

    Bewaar deze map op een andere schijf, niet alleen op deze laptop.
    De schijf gaat open met de lange wachtzin. Er is geen PIN.
    De USB-installatiestick start niet terwijl Secure Boot aanstaat.
    Voor een herinstallatie: F10, Secure Boot uit, van de stick starten.
    EOF
    copy ${store}/README.txt "$dest/README.txt"
    chmod 600 ${store}/README.txt
    private 600 "$dest/README.txt"
    # a stick can be pulled out as soon as this says it's done
    sync
    echo "Klaar: ${store} en $dest"
    echo "Haal de andere schijf uit de laptop en leg hem apart."
  '';
in
{
  environment.systemPackages = [ backup ];
}
