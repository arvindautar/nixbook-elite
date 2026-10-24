# Automatic partitioning: GPT -> 1 GiB ESP + LUKS2 (argon2id) -> btrfs subvolumes.
# nvme0n1 is the EliteBook's SSD; the installer formats exactly that disk.
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
            # Only used while formatting; the installer deletes it afterwards
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
              # TRIM through LUKS keeps the DRAM-less BG5 fast; leaks only free-space layout
              allowDiscards = true;
              # Skip dm-crypt workqueues: lower latency on NVMe (as used by Cloudflare/Fedora)
              bypassWorkqueues = true;
              # Unlock stays the long passphrase. No TPM and no PIN.
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
                # VM images: no compression/COW fragmentation fights (nodatacow set by tmpfiles)
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
