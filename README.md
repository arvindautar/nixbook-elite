# nixbook-elite

A Chromebook-like, secure and private NixOS for the **HP EliteBook 840 G10**.
It installs offline from a USB stick and then looks after itself: updates,
apps and backups run in the background. It is still a full Linux machine
underneath, with a terminal, containers, VMs and developer tools.

Based on [nixbook](https://github.com/mkellyxp/nixbook), rebuilt for one
specific laptop with Secure Boot, full-disk encryption and a hardened,
privacy-first default setup.

> The installer and the system messages are in Dutch. [Nederlandse samenvatting ↓](#nederlands)

## Why

| | Chromebook | Plain NixOS | nixbook-elite |
|---|---|---|---|
| Updates without thinking about it | ✓ | – | ✓ in the background, applied on next boot |
| Bad update? Previous version one boot away | partly | ✓ | ✓ the 8 most recent generations stay bootable |
| Whole system described in one versioned config | – | ✓ | ✓ every change is a git commit in `/etc/nixos` |
| App store | ✓ | – | ✓ Flathub through Bazaar |
| Terminal, containers, VMs, dev tools | limited | ✓ | ✓ |
| Secure Boot with your own keys + disk encryption | ✓ | manual | ✓ automatic |

## What you get

**Desktop.** GNOME without the bundled apps. Ghostty, Firefox, Nautilus,
VS Code (FHS variant) and Bazaar are installed; everything else comes from
Flathub. Installed on the first boot with internet: Brave, LibreWolf,
ONLYOFFICE, Papers (PDF), Loupe (images), Cine (video), Decibels (audio),
Pinta, Gradia (screenshots, with its Gradia Capture shell extension),
Calculator, Smile (emoji), Extension Manager and Flatseal. Dash to Dock,
Blur my Shell and AppIndicator are enabled. Dutch UI and formats, US keyboard
with € on AltGr+5, spell checking for Dutch and British English.

**Security.**
- Secure Boot with your own keys through [lanzaboote](https://github.com/nix-community/lanzaboote), generated and enrolled automatically (Microsoft keys kept for option ROMs and firmware).
- LUKS2 full-disk encryption: AES-256 (XTS), argon2id, unlocked with a long passphrase. No TPM unlock, no PIN.
- AppArmor; an nftables firewall that drops all inbound traffic and ignores pings.
- Kernel hardening with negligible cost (`init_on_alloc`, `slab_nomerge`, kptr/dmesg/BPF/ptrace restrictions, no kexec, IOMMU for Thunderbolt DMA), and unused network protocols and filesystems blacklisted.
- Root is locked, there is no SSH, sudo is for `wheel` only, Thunderbolt devices need approval, and core dumps are off.

**Privacy.**
- A different random MAC address per Wi-Fi network (stable on that network), a stable random MAC on Ethernet, and no hostname in DHCP.
- A random Windows-style hostname per laptop (`DESKTOP-XXXXXXX`).
- IPv6 privacy addresses; no LLMNR, no network connectivity checks, and no fallback DNS to Google or Cloudflare.
- Telemetry off in Firefox and GNOME, location services off, and the laptop is never announced on the network.
- NordVPN daemon, CLI and GUI included (`nordvpn login`).

**Performance.**
- 6.18 LTS kernel; zram swap in RAM (zstd, 50%) instead of swap on the SSD, with ChromeOS/Fedora-style VM tuning.
- systemd-oomd stops runaway programs before the desktop freezes, and Nix builds run at idle CPU and I/O priority.
- btrfs with zstd:1 compression and async discard, plus monthly scrub and fstrim.
- Smaller writeback bursts for the DRAM-less KIOXIA SSD.
- Hardware video decoding (iHD), panel self refresh, PCI runtime power management and power-profiles-daemon.
- Silent boot with Plymouth.

**Updates.**
- A few times a day the system checks whether an update is due (6+ days since the last success, on mains power and online).
- When it is, it updates the flake inputs, commits the new `flake.lock` and builds the new system in the background. That system becomes active on the next reboot.
- A failed build reverts the lock and shows a notification.
- Flatpaks update daily, and old generations are garbage-collected based on free disk space.
- Two app-grid tiles do it right away: *Bijwerken en herstarten* (update and reboot) and *Bijwerken en afsluiten* (update and shut down).

**Backups.**
- Daily read-only btrfs snapshots of `/` (7 kept) and `/home` (14 kept) in `/.snapshots`.
- Plug in a disk labelled `NIXBACKUP` (ext4 or btrfs) and `/home` is backed up to it with restic every hour (14 daily, 8 weekly and 12 monthly kept).
- `sudo nixbook-backup-recovery /path/on/a/usb-stick` copies the Secure Boot keys and a LUKS header backup off the laptop.

**Virtualisation and development.** libvirt/KVM (with a software TPM for
Windows 11 guests), Podman with Docker compatibility, Distrobox, and the AI
coding CLIs Claude Code, Codex and Grok, all from nixos-unstable so they
stay current.

## Installing

You need: the EliteBook 840 G10, a USB stick of 8 GB or more, and a machine
with Nix (flakes enabled) to build the ISO.

1. **Build the ISO** (about 4.8 GB). The installer is fully offline: the
   complete system is on the stick.
   ```sh
   nix build .#iso
   sudo dd if=result/iso/nixbook-elite-installer.iso of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
   ```
   Replace `/dev/sdX` with your USB stick (check with `lsblk`). Everything on it is erased.

2. **Prepare the BIOS** (F10 at power-on):
   - Turn **Secure Boot off**. The stick doesn't start while it is on.
   - Under *Security → Sure Start*, turn **Sure Start Secure Boot Keys
     Protection off**. Otherwise HP restores its factory keys after yours are
     enrolled.
   - To enroll your own keys automatically, choose *Secure Boot
     Configuration → Clear Secure Boot keys* (this puts the firmware in Setup
     Mode). You can also do this after the installation.

3. **Install.** Boot from the stick (F9) and run:
   ```sh
   sudo nixbook-install
   ```
   It asks for a username, full name, password (8+ characters) and a disk
   passphrase (12+ characters; use 5+ words). Names the system already uses
   are refused before anything is touched. Typing `WISSEN` erases
   `/dev/nvme0n1` and installs. No internet is needed.

4. **First boots.**
   - Unlock the disk with your passphrase.
   - If the firmware is in Setup Mode, the system generates its Secure Boot
     keys, signs itself and reboots once. On the next boot, systemd-boot
     enrolls the keys.
   - Run `nixbook-secureboot`. Only when it says your own keys are in the
     firmware, turn Secure Boot on in the BIOS; with the HP keys still in
     place the laptop would not start.
   - Copy the keys and the LUKS header off the laptop:
     `sudo nixbook-backup-recovery /path/on/a/usb-stick`.

5. **First boot with internet.** The Flatpaks install in the background. The
   first automatic update writes your username and hostname into the system
   configuration (from `/etc/nixos/hosts/elitebook/user.json`, which the
   installer created).

## Everyday use

| Command | What it does |
|---|---|
| `nixbook-update [reboot\|poweroff]` | Update now, then reboot or shut down (also the two app-grid tiles) |
| `nixbook-secureboot` | Whose Secure Boot keys the firmware holds and what to do next |
| `sudo nixbook-enroll` | Enroll the keys by hand (firmware must be in Setup Mode) |
| `sudo nixbook-backup-recovery DIR` | Copy Secure Boot keys + LUKS header backup to `DIR` |
| `sudo nixbook-backup-home` | Back up `/home` to the `NIXBACKUP` disk now |
| `journalctl -u nixbook-upgrade` | Why an automatic update failed |

Changing the system: edit the files in `/etc/nixos` and run
`sudo nixos-rebuild switch --flake /etc/nixos#nixbook`. The automatic updater
commits your changes before it updates.

## How it fits together

```
flake.nix                  nixbook (the system), installer (the ISO), the VM test
hosts/elitebook/
  default.nix              module list, hostname
  hardware.nix             EliteBook 840 G10 hardware profile
  disko.nix                GPT: 1 GiB ESP + LUKS2 → btrfs subvolumes
  user.json                username + hostname; null here, filled in by the installer
installer/
  install.sh               the offline installer (nixbook-install)
  iso.nix, script.nix      the ISO and how the installer gets built
modules/
  base.nix                 Nix, locale, the user account, printing, fonts
  boot.nix                 lanzaboote Secure Boot, kernel, silent boot
  desktop.nix              GNOME, apps, Firefox policies, defaults
  flatpak.nix              Flathub apps, Gradia Capture
  security.nix, privacy.nix, performance.nix, power.nix
  updates.nix              automatic updates, garbage collection
  backup.nix, recovery.nix snapshots, restic, key/header backup
  virtualisation.nix, ai.nix, nordvpn.nix, spelling.nix, extensions.nix
tests/install.nix          end-to-end offline install test
```

**Any username works.** The prebuilt system on the ISO has no user account and
no hostname. The installer creates the account (UID 1000), writes a random
`DESKTOP-XXXXXXX` to `/etc/hostname`, and stores both in `user.json`.
Rebuilds then declare that account and hostname. Two safety checks:
- A rebuild is refused if it would delete a normal account that an earlier
  generation declared. NixOS would otherwise remove it, even with
  `mutableUsers`.
- An installed system whose `user.json` has no `hostName` fails to evaluate
  instead of silently losing its hostname.

## Development

```sh
nix build .#toplevel                          # the system
nix build .#iso                               # the installer ISO
nix build .#checks.x86_64-linux.install -L    # end-to-end test (needs KVM)
nix fmt                                       # format the Nix files
```

The test runs entirely offline in QEMU. It:
- boots the installer and checks that bad usernames are refused before the
  disk is touched;
- installs onto an empty NVMe disk;
- boots with Secure Boot firmware in Setup Mode, unlocks LUKS, lets lanzaboote
  generate and enroll keys, and checks for `Secure Boot: enabled (user)`;
- then checks the disk layout, the kernel, zram, the user and hostname, the
  account-deletion guard, the security settings, the apps and the Gradia
  Capture service.

It takes about 4 minutes once everything is built.

Keep `hosts/elitebook/user.json` at `null` in the repo. On an installed
laptop, that file in `/etc/nixos` must name its own account and hostname.

Other hardware: the disk (`/dev/nvme0n1`), `hardware.nix` and the HP-specific
Secure Boot hints are EliteBook-specific; the rest is generic NixOS.

## Known limits

- Flatpaks and Gradia Capture need internet; until then they retry in the
  background.
- The user account and hostname become part of the declared configuration
  only after the first update, which needs internet. Until then they work as
  normal mutable settings.
- The USB stick does not boot while Secure Boot is on. To reinstall, turn
  Secure Boot off first.

---

## Nederlands

**nixbook-elite** maakt van de HP EliteBook 840 G10 een laptop die werkt als een
Chromebook: updates, apps en back-ups regelen zichzelf. Daaronder zit een
volledige NixOS met terminal, containers en virtuele machines.

- **Installeren:** zet in het BIOS (F10) Secure Boot en *Sure Start Secure Boot
  Keys Protection* uit, start van de USB-stick (F9) en typ `sudo nixbook-install`.
  Je kiest een gebruikersnaam, wachtwoord en een lange wachtzin voor de
  schijfversleuteling. Internet is niet nodig.
- **Secure Boot:** de laptop maakt zelf eigen sleutels aan en schrijft ze in.
  Zet Secure Boot pas aan als `nixbook-secureboot` zegt dat je eigen sleutels in
  de firmware staan.
- **Updates:** gaan vanzelf op de achtergrond (aan de lader, met internet) en
  zijn actief na een herstart. Mislukt een update, dan krijg je een melding en
  blijft alles zoals het was. Direct bijwerken: de tegels *Bijwerken en
  herstarten* of *Bijwerken en afsluiten*.
- **Back-ups:** dagelijks snapshots op de SSD. Steek een schijf met het label
  `NIXBACKUP` in en `/home` gaat er elk uur naartoe. Bewaar de Secure Boot-sleutels
  en LUKS-header op een USB-stick: `sudo nixbook-backup-recovery /pad/op/stick`.
- **Privacy:** willekeurig MAC-adres per wifi-netwerk, een willekeurige
  Windows-achtige computernaam, geen telemetrie, geen DNS-terugval naar Google of
  Cloudflare, NordVPN ingebouwd.
