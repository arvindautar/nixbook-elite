# Secure Boot (lanzaboote), LTS kernel, systemd initrd, quiet boot
{ pkgs, lib, ... }:

let
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
  ];

  # 6.18 LTS, pinned so a nixpkgs bump doesn't switch kernels
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  # Own keys, enrolled automatically. The first boot generates them, re-signs
  # the ESP and reboots; on the second boot systemd-boot enrolls them (the
  # firmware has to be in Setup Mode).
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 8;
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
  ];

  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "40%";
  };
}
