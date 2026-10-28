# GPT on nvme0n1: 1 GiB ESP + LUKS2 (argon2id) with btrfs subvolumes.
{ lib, ... }:

let
  btrfsOpts = [
    "compress=zstd:1"
    "noatime"
    "discard=async"
  ];
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = [
              "-n"
              "NIXBOOT"
            ];
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # only used while formatting, the installer removes it
            passwordFile = "/tmp/nixbook-luks.key";
            extraFormatArgs = [
              "--type"
              "luks2"
              "--cipher"
              "aes-xts-plain64"
              "--key-size"
              "512"
              "--pbkdf"
              "argon2id"
              "--iter-time"
              "3000"
              "--label"
              "NIXCRYPT"
            ];
            settings = {
              # TRIM through LUKS, the BG5 needs it. Leaks which blocks are free.
              allowDiscards = true;
              # skip the dm-crypt workqueues, lower latency on NVMe
              bypassWorkqueues = true;
              # passphrase only, no TPM or PIN
            };
            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-L"
                "nixos"
              ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsOpts;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsOpts;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOpts;
                };
                "@log" = {
                  mountpoint = "/var/log";
                  mountOptions = btrfsOpts;
                };
                # VM images: no compression, nodatacow is set via tmpfiles
                "@libvirt" = {
                  mountpoint = "/var/lib/libvirt/images";
                  mountOptions = [
                    "noatime"
                    "discard=async"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/var/log".neededForBoot = true;
}
