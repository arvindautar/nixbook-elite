# Secure Boot keys, the LUKS header, a recovery key and TPM2+PIN.
# Enrollment is interactive (it needs the current disk passphrase) and is not
# done at build time. After the next boot: sudo nixbook-enroll
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
    cp -a /var/lib/sbctl ${store}/sbctl
    cp -a /var/lib/sbctl "$dest/sbctl"
    ${pkgs.cryptsetup}/bin/cryptsetup luksHeaderBackup ${disk} \
      --header-backup-file ${store}/luks-header.bin
    cp -a ${store}/luks-header.bin "$dest/luks-header.bin"
    if [ -f ${store}/recovery-key.txt ]; then
      cp -a ${store}/recovery-key.txt "$dest/recovery-key.txt"
    fi
    chmod -R go-rwx ${store} "$dest"
    cat > ${store}/README.txt <<'EOF'
    nixbook-recovery

    sbctl/            Private Secure Boot-sleutels. Zonder deze map kan een
                      nieuwe generatie niet getekend worden.
    luks-header.bin   Reservekopie van de LUKS-header. De wachtzin opent
                      niets als de header op de SSD kapot is.
    recovery-key.txt  Staat er pas na `nixbook-enroll`.

    Bewaar deze map op een andere schijf, niet alleen op deze laptop.
    De USB-installatiestick start niet terwijl Secure Boot aanstaat.
    Voor een herinstallatie: F10, Secure Boot uit, van de stick starten.
    EOF
    cp -a ${store}/README.txt "$dest/README.txt"
    chmod 600 ${store}/README.txt "$dest/README.txt"
    echo "Klaar: ${store} en $dest"
    echo "Haal de andere schijf uit de laptop en leg hem apart."
  '';

  enroll = pkgs.writeShellScriptBin "nixbook-enroll" ''
    set -euo pipefail
    [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
    mkdir -p ${store}
    chmod 700 ${store}

    echo "Stap 1/3. Herstelsleutel. Typ de huidige LUKS-wachtzin."
    echo "De sleutel komt op het scherm en in ${store}/recovery-key.txt."
    echo "Schrijf hem op en bewaar hem niet alleen op deze schijf."
    ${pkgs.systemd}/bin/systemd-cryptenroll --recovery-key ${disk} | tee ${store}/recovery-key.txt
    chmod 600 ${store}/recovery-key.txt

    echo
    echo "Stap 2/3. TPM2 + PIN."
    echo "De PIN is kort: de TPM stopt gokken. De lange wachtzin blijft werken."
    echo "Alleen PCR 7 (Secure Boot-staat), zodat een gewone systeemupdate"
    echo "de ontgrendeling niet stuk maakt. Na een BIOS-update of een wijziging"
    echo "van de Secure Boot-sleutels vraagt de laptop weer om de wachtzin;"
    echo "voer dit commando dan opnieuw uit."
    ${pkgs.systemd}/bin/systemd-cryptenroll \
      --tpm2-device=auto \
      --tpm2-pcrs=7 \
      --tpm2-with-pin=true \
      --wipe-slot=tpm2 \
      ${disk}

    echo
    echo "Stap 3/3. Header en Secure Boot-sleutels naar ${store}."
    rm -rf ${store}/sbctl
    cp -a /var/lib/sbctl ${store}/sbctl
    ${pkgs.cryptsetup}/bin/cryptsetup luksHeaderBackup ${disk} \
      --header-backup-file ${store}/luks-header.bin
    chmod -R go-rwx ${store}
    echo
    echo "Klaar. Kopieer ${store} van de laptop af:"
    echo "  sudo nixbook-backup-recovery /pad/op/een/usb-stick"
    echo "Herstart daarna. Bij het opstarten vraagt de laptop om de PIN."
    echo "De lange wachtzin werkt nog als de PIN of de TPM het niet doet."
  '';
in
{
  # The initrd must contain the TPM2 token or the enrolled key is ignored.
  boot.initrd.systemd.tpm2.enable = true;

  environment.systemPackages = [
    backup
    enroll
  ];
}
