# Secure Boot (lanzaboote), LTS kernel, systemd initrd, quiet boot
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # nixbook-check-boot [keys|files]: will the firmware start what's on the ESP?
  # lzbt can't tell. autoGenerateKeys makes it install unsigned files when the
  # keys are gone, and a new key pair would make it re-sign the whole ESP.
  # Either way every generation and systemd-boot get replaced by files that
  # Secure Boot refuses, so nothing is left to fall back on.
  bootCheck = pkgs.writeShellScriptBin "nixbook-check-boot" ''
    set -u
    [ "$(${pkgs.coreutils}/bin/id -u)" = 0 ] || exec sudo "$0" "$@"
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.openssl
        pkgs.sbsigntool
      ]
    }
    cert=/var/lib/sbctl/keys/db/db.pem
    key=/var/lib/sbctl/keys/db/db.key
    secureboot=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
    db=/sys/firmware/efi/efivars/db-d719b2cb-3d3a-4596-a3bc-dad00e67656f
    hex() { od -An -v -t x1 | tr -d ' \n'; }

    # Without Secure Boot anything starts, and the keys may not exist yet
    # (installing, first boot).
    if [ ! -e "$secureboot" ] || [ "$(od -An -t u1 -j4 -N1 "$secureboot" | tr -d ' ')" != 1 ]; then
      echo "Secure Boot staat uit, niets te controleren."
      exit 0
    fi

    failed=0
    bad() {
      echo "FOUT: $1"
      failed=1
    }

    check_keys() {
      if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
        bad "de Secure Boot-sleutels ontbreken in /var/lib/sbctl; zet ze terug van je reservekopie"
        return
      fi
      case "$(hex < "$db")" in
        *"$(openssl x509 -in "$cert" -outform DER | hex)"*) ;;
        *) bad "de sleutel in /var/lib/sbctl staat niet in de firmware; zet de juiste terug van je reservekopie" ;;
      esac
    }

    check_files() {
      local f hash link gen
      for f in /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/Linux/nixos-*.efi; do
        sbverify --cert "$cert" "$f" > /dev/null 2>&1 || bad "$f is niet goed ondertekend"
      done
      # kernels and initrds aren't signed, the signed stub holds their hash
      for f in /boot/EFI/nixos/kernel-*.efi /boot/EFI/nixos/initrd-*.efi; do
        hash=$(openssl dgst -sha256 -binary "$f" | base32 | tr -d = | tr '[:upper:]' '[:lower:]')
        [ "$f" != "''${f%-"$hash".efi}" ] || bad "$f is beschadigd"
      done
      link=$(readlink /nix/var/nix/profiles/system)
      gen=''${link#system-}
      gen=''${gen%-link}
      for f in /boot/EFI/Linux/nixos-generation-"$gen"-*.efi; do
        [ -e "$f" ] || bad "generatie $gen staat niet op de ESP"
      done
    }

    case "''${1:-all}" in
      keys) check_keys ;;
      files) check_files ;;
      all)
        check_keys
        [ "$failed" = 1 ] || check_files
        ;;
      *)
        echo "Gebruik: nixbook-check-boot [keys|files]"
        exit 1
        ;;
    esac
    [ "$failed" = 0 ] || exit 1
    echo "Secure Boot: de sleutels en de opstartbestanden zijn in orde."
  '';

  # The one place everything that writes to the ESP goes through. A rebuild
  # that fails here keeps the current boot entries.
  lzbt = pkgs.writeShellScriptBin "lzbt" ''
    set -e
    ${bootCheck}/bin/nixbook-check-boot keys
    ${inputs.lanzaboote.packages.${pkgs.stdenv.hostPlatform.system}.lzbt}/bin/lzbt "$@"
    ${bootCheck}/bin/nixbook-check-boot files
  '';

  # nixbook-secureboot shows whose keys are in the firmware and what to do next.
  # HP Sure Start puts the factory keys back after enrollment, so it has to be
  # off first. nixbook-enroll is the manual fallback for lanzaboote's
  # auto-enrollment.
  enroll = pkgs.writeShellScriptBin "nixbook-enroll" ''
    set -euo pipefail
    [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
    efivar() {
      f=/sys/firmware/efi/efivars/$1
      [ -e "$f" ] && ${pkgs.coreutils}/bin/od -An -t u1 -j4 -N1 "$f" | tr -d ' ' || echo 0
    }
    hpattr() {
      cat "/sys/class/firmware-attributes/hp-bioscfg/attributes/$1/current_value" 2>/dev/null || echo "?"
    }
    setupmode=$(efivar SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c)
    protection=$(hpattr "Sure Start Secure Boot Keys Protection")
    [ "$setupmode" = 1 ] || {
      echo "Firmware staat niet in Setup Mode; zie 'nixbook-secureboot'."
      exit 1
    }
    if [ "$protection" = Enable ]; then
      echo "Zet eerst 'Sure Start Secure Boot Keys Protection' uit in het BIOS,"
      echo "anders zet HP de fabriekssleutels terug."
      exit 1
    fi
    ${pkgs.sbctl}/bin/sbctl enroll-keys --microsoft
    echo
    echo "Ingeschreven. Herstart, zet Secure Boot aan in het BIOS (F10) en controleer"
    echo "daarna met 'bootctl status': Secure Boot: enabled (user)."
  '';

  secureBootTool = pkgs.writeShellScriptBin "nixbook-secureboot" ''
    efivar() { # name-guid -> value of the 5th byte (after the 4 attribute bytes)
      f=/sys/firmware/efi/efivars/$1
      [ -e "$f" ] && ${pkgs.coreutils}/bin/od -An -t u1 -j4 -N1 "$f" | tr -d ' ' || echo 0
    }
    pk_owner() {
      f=/sys/firmware/efi/efivars/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c
      if [ ! -e "$f" ]; then echo none
      elif ${pkgs.gnugrep}/bin/grep -aq "HP UEFI Secure Boot PK" "$f"; then echo hp
      else echo custom
      fi
    }
    hpattr() {
      cat "/sys/class/firmware-attributes/hp-bioscfg/attributes/$1/current_value" 2>/dev/null || echo "?"
    }

    secureboot=$(efivar SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c)
    setupmode=$(efivar SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c)
    owner=$(pk_owner)
    protection=$(hpattr "Sure Start Secure Boot Keys Protection")

    case "''${1:-status}" in
      status)
        echo "Secure Boot actief:            $([ "$secureboot" = 1 ] && echo ja || echo nee)"
        echo "Setup Mode (geen sleutels):    $([ "$setupmode" = 1 ] && echo ja || echo nee)"
        echo "Platform Key van:              $owner"
        echo "Sure Start sleutelbescherming: $protection"
        echo
        if [ "$secureboot" = 1 ] && [ "$owner" = custom ]; then
          echo "Secure Boot staat aan met je eigen sleutels."
          if [ "$protection" = Enable ]; then
            echo
            echo "Sure Start sleutelbescherming staat op Enable."
            echo "Dat is in orde als Sure Start jouw sleutels als basis heeft genomen."
            echo "Controleer dat met een koude start, niet met Herstarten:"
            echo "  USB-stick bij de hand, laptop helemaal uit, daarna weer aan."
            echo "  Daarna opnieuw: nixbook-secureboot"
            echo "Blijft 'Platform Key van: custom', dan bewaakt Sure Start jouw sleutels."
            echo "Zet HP de fabriekssleutels terug, dan start nixbook niet. Zet in het"
            echo "BIOS (F10) Secure Boot uit en laat de sleutelbescherming uit."
            echo "Doe deze test opnieuw na elke BIOS-update (fwupd)."
          fi
          echo
          echo "Kopieer de sleutels van deze schijf af:"
          echo "  sudo nixbook-backup-recovery /pad/op/een/usb-stick"
        elif [ "$owner" = custom ]; then
          echo "Je eigen sleutels staan in de firmware. Zet nu Secure Boot aan:"
          echo "  F10 -> Beveiliging -> Secure Boot-configuratie -> Secure Boot inschakelen."
        elif [ "$setupmode" = 1 ]; then
          echo "Firmware staat in Setup Mode. Herstart: de sleutels worden automatisch"
          echo "ingeschreven (15 seconden aftellen). Of nu direct: sudo nixbook-enroll"
        else
          echo "De firmware heeft de HP-fabriekssleutels: zet Secure Boot NIET aan, dan start"
          echo "nixbook niet. Eerst in het BIOS (F10):"
          echo "  1. Beveiliging -> Sure Start -> 'Sure Start Secure Boot Keys Protection' uit"
          echo "  2. Secure Boot-configuratie -> 'Clear Secure Boot keys', Secure Boot uit laten"
          echo "  3. Opslaan, herstarten, de 4-cijferige code invoeren"
          echo "Daarna schrijft systemd-boot de sleutels automatisch in. Controleer met"
          echo "'nixbook-secureboot' voordat je Secure Boot aanzet."
        fi
        ;;
      enroll)
        exec ${enroll}/bin/nixbook-enroll
        ;;
      *)
        echo "Gebruik: nixbook-secureboot [status|enroll]"
        echo "Sleutels inschrijven: sudo nixbook-enroll"
        exit 1
        ;;
    esac
  '';
in
{
  environment.systemPackages = [
    secureBootTool
    enroll
    bootCheck
  ];

  # 6.18 LTS, pinned so a nixpkgs bump doesn't switch kernels
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  # Own keys, enrolled automatically. The first boot generates them, re-signs
  # the ESP and reboots; on the second boot systemd-boot enrolls them (the
  # firmware has to be in Setup Mode).
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    package = lzbt;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 8;
    # A new generation gets 3 tries to reach the login screen. After that
    # systemd-boot moves on to the previous one by itself.
    bootCounting.initialTries = 3;
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      autoReboot = true;
      # option ROMs (GPU, Thunderbolt) and HP firmware are signed by Microsoft
      includeMicrosoftKeys = true;
    };
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # no menu, hold space to get it
  boot.loader.timeout = 0;

  # By default a boot counts as good right after sysinit, long before anything
  # that could be broken has run. Wait for the login screen.
  systemd.services.nixbook-boot-good = {
    description = "Check that the login screen came up";
    requiredBy = [ "boot-complete.target" ];
    before = [ "boot-complete.target" ];
    after = [ "display-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemctl is-active --quiet display-manager.service";
    };
  };

  boot.initrd.systemd.enable = true;

  # quiet boot (from nixbook's common.nix), LUKS prompt in Plymouth
  boot.plymouth.enable = true;
  boot.consoleLogLevel = lib.mkDefault 0;
  boot.initrd.verbose = false;
  # plymouth adds "splash", consoleLogLevel adds "loglevel=0"
  boot.kernelParams = [
    "quiet"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_level=3"
    # restart instead of hanging forever, so a panic uses up a boot try
    "panic=10"
  ];

  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "40%";
  };
}
