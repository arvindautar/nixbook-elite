# nixbook-elite

NixOS for the HP EliteBook 840 G10, set up to behave a bit like a Chromebook:
it installs offline from a USB stick, updates itself in the background and
keeps the defaults locked down. It's still a normal NixOS underneath, with a
terminal, containers, VMs and dev tools.

It started from [nixbook](https://github.com/mkellyxp/nixbook) and was
reworked for this one laptop, with Secure Boot, full-disk encryption and
stricter privacy defaults.

The installer and the notifications are in Dutch. There's a short Dutch
summary [at the bottom](#nederlands).

## Why

| | Chromebook | Plain NixOS | nixbook-elite |
|---|---|---|---|
| Updates without thinking about them | yes | no | yes, applied on the next boot |
| Go back after a bad update | partly | yes | yes, the last 8 generations stay bootable |
| Whole system in one versioned config | no | yes | yes, `/etc/nixos` is a git repo |
| App store | yes | no | Flathub through Bazaar |
| Terminal, containers, VMs | limited | yes | yes |
| Secure Boot with own keys + disk encryption | yes | manual | yes, set up automatically |

## What's in it

### Desktop

GNOME without the bundled apps. Ghostty, Nautilus, VS Code (FHS) and Bazaar
come from nixpkgs, everything else from Flathub. These get installed the first
time the laptop is online: Brave, LibreWolf, ONLYOFFICE, Papers, Loupe, Cine,
Decibels, Sound Recorder, Planify, Pinta, Gradia (plus its Gradia Capture
extension), Calculator, Smile, Extension Manager and Flatseal. Dash to Dock,
Blur my Shell and AppIndicator are enabled.

Dutch UI and formats, British English can be picked in Settings. US keyboard
with € on AltGr+5. Spell checking for Dutch and British English. The time zone
starts as Amsterdam and can be changed in Settings > Date & Time.

### Security

- Secure Boot with your own keys through
  [lanzaboote](https://github.com/nix-community/lanzaboote), generated and
  enrolled automatically. Microsoft's keys are kept for option ROMs and HP
  firmware.
- LUKS2 (aes-xts, argon2id), unlocked with a passphrase. No TPM, no PIN.
- nftables firewall that drops everything inbound and doesn't answer pings.
  AppArmor is on.
- Kernel hardening that costs next to nothing (`init_on_alloc`,
  `slab_nomerge`, kptr/dmesg/BPF/ptrace restrictions, no kexec, IOMMU for
  Thunderbolt), and unused network protocols and filesystems are blacklisted.
- Root is locked, no SSH, sudo only for `wheel`, Thunderbolt devices need
  approval, no core dumps.
- The fingerprint reader only works for the login and lock screen. sudo,
  polkit prompts and password changes always ask for the password.
- Brave and LibreWolf only see ~/Downloads.

### Privacy

- Wi-Fi only. Wired ports are ignored, including the network port of a USB-C
  dock or monitor, and USB tethering. Drop the `unmanaged` line in
  `privacy.nix` if you need a cable.
- Random MAC per Wi-Fi network (stable on that network), no hostname in DHCP,
  and a DHCPv6 DUID that differs per network.
- Hostname is a random `DESKTOP-XXXXXXX`.
- IPv6 privacy addresses, no LLMNR, no connectivity check, no fallback DNS.
- GNOME telemetry and location services are off, and there's no first-login
  wizard that could turn them back on. The laptop doesn't announce itself on
  the network.
- Brave has locked policies: no telemetry or pings, no Rewards, Wallet, VPN,
  News, Talk or Leo, no prefetching. That gets it close to Brave Origin while
  keeping the Flathub build. Safe Browsing, Tor windows, Translate and Sync are
  still there.
- LibreWolf is Firefox without telemetry, studies or captive portal checks,
  with uBlock Origin built in.
- ONLYOFFICE opens other people's documents and is online, so it only sees
  Documents, Downloads and Desktop.
- NordVPN (daemon, CLI and GUI) is installed but not configured. Log in and set
  it up in the app.

### Performance and battery

- 6.18 LTS kernel.
- zram (zstd, 50% of RAM) instead of swap on the SSD, with the VM sysctls
  ChromeOS and Fedora use for zram.
- systemd-oomd, and Nix builds run at idle CPU/IO priority.
- btrfs with zstd:1 and async discard, monthly scrub and fstrim. Smaller
  writeback bursts because the KIOXIA BG5 has no DRAM cache.
- VA-API (iHD), PCI runtime PM and power-profiles-daemon. i915, NVMe and audio
  power saving stay at the kernel defaults, which already go deepest on this
  hardware (PSR2 for the panel).
- The Nix store is deduplicated weekly instead of on every build.
- Quiet boot with Plymouth.

### Updates

- A timer checks a few times a day whether an update is due: at least 6 days
  since the last one, on AC power and online. If so it updates the flake
  inputs, commits `flake.lock` and builds the new system in the background. It
  becomes active after the next reboot.
- If the build fails, the old lock is put back and you get a notification.
- Flatpaks (also the ones installed with Bazaar) update every 4 hours. If an
  app you have open got updated, a notification asks you to restart it.
- Old generations are garbage collected depending on free disk space.
- The *Bijwerken en herstarten* and *Bijwerken en afsluiten* tiles update
  right away and then reboot or shut down. They also install firmware updates
  from LVFS (where HP publishes them); a BIOS update runs on the next boot.
- You get a notification when there's a firmware update, and when an installed
  update has been waiting for a reboot for 3 days.
- Unused container image layers are pruned weekly for every account.

### Backups

- Daily read-only btrfs snapshots of `/` (7 kept) and `/home` (14 kept) in
  `/.snapshots`.
- Plug in a disk labelled `NIXBACKUP` (ext4 or btrfs) and `/home` gets backed
  up to it with restic every hour (14 daily, 8 weekly, 12 monthly).
- `sudo nixbook-backup-recovery /path/on/usb` copies the Secure Boot keys and a
  LUKS header backup off the laptop.

### VMs and development

libvirt/KVM with swtpm (for Windows 11 guests), Podman with Docker
compatibility, Distrobox, and the Claude Code, Codex and Grok CLIs from
nixos-unstable.

## Installing

You need the EliteBook, a USB stick of 8 GB or more, and a machine with Nix
(flakes enabled) to build the ISO.

1. Build the ISO (about 4.8 GB, the whole system is on it, so the install
   doesn't need internet) and write it to the stick:
   ```sh
   nix build .#iso
   sudo dd if=result/iso/nixbook-elite-installer.iso of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
   ```
   Check the device with `lsblk` first, everything on it gets erased.

2. In the BIOS (F10 at power-on):
   - Turn Secure Boot off, the stick won't boot with it on.
   - Under *Security > Sure Start*, turn off *Sure Start Secure Boot Keys
     Protection*. Otherwise HP puts its factory keys back after yours are
     enrolled.
   - *Secure Boot Configuration > Clear Secure Boot keys* puts the firmware in
     Setup Mode, so your own keys get enrolled automatically. This can also be
     done after installing.
   - Reinstalling over an older nixbook? Clear the keys anyway. The new install
     generates new keys and the firmware still has the old ones, so it won't
     boot once Secure Boot is back on.

3. Boot from the stick (F9) and run:
   ```sh
   sudo nixbook-install
   ```
   It asks for a username, full name, password (8+ characters) and a disk
   passphrase (12+ characters, a few words works well). Type `WISSEN` to
   erase `/dev/nvme0n1` and install.

4. First boots:
   - Unlock the disk with the passphrase and log in with the account from the
     installer.
   - If the firmware is in Setup Mode, the system generates its Secure Boot
     keys, signs itself and reboots once. On the next boot systemd-boot
     enrolls them.
   - Run `nixbook-secureboot`. Only turn Secure Boot on in the BIOS once it
     says your own keys are in the firmware; with HP's keys still there the
     laptop won't boot.
   - Copy the keys and LUKS header somewhere else:
     `sudo nixbook-backup-recovery /path/on/usb`.

5. The Flatpaks install in the background once the laptop is online.

## Day to day

| Command | |
|---|---|
| `nixbook-update [reboot\|poweroff]` | update system, apps and firmware now, then reboot or shut down (same as the two tiles) |
| `nixbook-secureboot` | whose Secure Boot keys are in the firmware and what to do next |
| `sudo nixbook-enroll` | enroll the keys by hand (firmware has to be in Setup Mode) |
| `sudo nixbook-backup-recovery DIR` | copy the Secure Boot keys and LUKS header backup to `DIR` |
| `sudo nixbook-backup-home` | back up `/home` to the `NIXBACKUP` disk now |
| `journalctl -u nixbook-upgrade` | why an automatic update failed |

To change the system, edit `/etc/nixos` and run
`sudo nixos-rebuild switch --flake /etc/nixos#nixbook`. The updater commits
local changes before it updates.

## Layout

```
flake.nix                  the system, the installer ISO and the VM test
hosts/elitebook/
  default.nix              module list, hostname
  hardware.nix             EliteBook 840 G10 hardware
  disko.nix                GPT: 1 GiB ESP + LUKS2 with btrfs subvolumes
installer/
  install.sh               nixbook-install
  iso.nix, script.nix      the ISO and how the installer gets built
modules/
  base.nix                 Nix, locale, printing
  fonts.nix                Ubuntu 26.04's font matching, also in Flatpaks; Adwaita Sans UI (Noto Sans in the browsers), JetBrainsMono Nerd Font
  fontconfig-ubuntu/       Ubuntu 26.04's fontconfig files, unchanged
  accounts.nix             groups and subuid ranges for every account
  boot.nix                 lanzaboote, kernel, quiet boot
  desktop.nix              GNOME, apps, Brave policies, defaults
  flatpak.nix              Flathub apps and overrides, Gradia Capture
  security.nix, privacy.nix, performance.nix, power.nix
  updates.nix              system, Flatpak and firmware updates, gc
  backup.nix, recovery.nix snapshots, restic, key and header backup
  virtualisation.nix, ai.nix, nordvpn.nix, spelling.nix, extensions.nix
tests/install.nix          offline end-to-end install test
```

Accounts aren't in the flake. The installer creates the first one (an admin)
and more can be added in GNOME Settings. `accounts.nix` gives every account its
subuid/subgid ranges, and admins also get `networkmanager`, `libvirtd`,
`nordvpn`, `video` and `audio`. The installer writes a random hostname to
`/etc/hostname`; the flake doesn't set one, so rebuilds leave it alone.

Laptops installed with the older `user.json` setup had their account declared
in the flake. NixOS would delete it from a generation that no longer declares
it, so such a rebuild is refused with instructions. Their hostname is written
to `/etc/hostname` on the first rebuild.

## Development

```sh
nix build .#toplevel                          # the system
nix build .#iso                               # the installer ISO
nix build .#checks.x86_64-linux.install -L    # end-to-end test (needs KVM)
nix fmt
```

The test runs offline in QEMU and takes about 5 minutes once everything is
built. It runs the installer (including the cases it has to refuse before
touching the disk), boots the result with Secure Boot firmware in Setup Mode,
lets lanzaboote enroll its keys and checks for `Secure Boot: enabled (user)`.
Then it goes through the installed system: accounts and groups (also an admin
created the way GNOME Settings does it), rootless containers, the disk layout,
zram, fonts, PAM, NetworkManager settings, firmware check, time zone,
hostname, security settings and apps. It fails if any unit failed, except the
Flathub install, which can't work without internet.

Most of this is generic NixOS. The EliteBook-specific parts are the disk
(`/dev/nvme0n1`), `hardware.nix` and the HP Secure Boot hints.

### Updating lanzaboote and disko

The automatic updates move nixpkgs, nixos-unstable and nix-flatpak.
lanzaboote and disko are pinned to a release tag on purpose: lanzaboote signs
what the laptop boots, and an untested change there can leave it unbootable.

Check the [lanzaboote](https://github.com/nix-community/lanzaboote/releases)
and [disko](https://github.com/nix-community/disko/releases) releases every
few months. To move to a new release, in `/etc/nixos` on the laptop:

1. Change the tag in `flake.nix`, e.g. `github:nix-community/lanzaboote/v1.3.0`.
2. `sudo nix flake update lanzaboote --flake /etc/nixos` (or `disko`).
3. Optionally run the test: `nix build /etc/nixos#checks.x86_64-linux.install -L`.
4. `sudo nixos-rebuild boot --flake /etc/nixos#nixbook` and reboot. If it
   doesn't come up, hold space at power-on and pick the previous entry.

disko is only used by the installer, so it only matters for new installs.

## Known limitations

- Flatpaks and Gradia Capture need internet. Until then they keep retrying in
  the background.
- The USB stick doesn't boot with Secure Boot on. Turn it off before
  reinstalling.

## License

[MIT](LICENSE). The update, garbage collection and quiet boot parts are
adapted from [nixbook](https://github.com/mkellyxp/nixbook) by Michael Kelly,
also MIT.

---

## Nederlands

nixbook-elite maakt van de HP EliteBook 840 G10 een laptop die zich een beetje
als een Chromebook gedraagt: updates, apps en back-ups gaan vanzelf. Daaronder
zit gewoon NixOS, met terminal, containers en virtuele machines.

- **Installeren:** zet in het BIOS (F10) Secure Boot en *Sure Start Secure Boot
  Keys Protection* uit, start van de USB-stick (F9) en typ
  `sudo nixbook-install`. Je kiest een gebruikersnaam, wachtwoord en een lange
  wachtzin voor de schijfversleuteling. Internet is niet nodig.
- **Secure Boot:** de laptop maakt zelf sleutels aan en schrijft ze in. Zet
  Secure Boot pas aan als `nixbook-secureboot` zegt dat je eigen sleutels in de
  firmware staan. Bij een herinstallatie eerst de oude sleutels wissen in het
  BIOS (*Clear Secure Boot keys*).
- **Updates:** gaan op de achtergrond (aan de lader, met internet) en zijn
  actief na een herstart. Mislukt er een, dan krijg je een melding en blijft
  alles zoals het was. Meteen bijwerken kan met de tegels *Bijwerken en
  herstarten* en *Bijwerken en afsluiten*, die ook firmware bijwerken.
- **Back-ups:** dagelijks snapshots op de SSD. Steek een schijf met het label
  `NIXBACKUP` in en `/home` gaat er elk uur naartoe. Zet de Secure
  Boot-sleutels en de LUKS-header op een USB-stick met
  `sudo nixbook-backup-recovery /pad/op/stick`.
- **Privacy:** alleen wifi (de netwerkkabel wordt niet gebruikt), een
  willekeurig MAC-adres per wifi-netwerk, een willekeurige Windows-achtige
  computernaam, geen telemetrie en geen DNS-terugval naar Google of Cloudflare.
  NordVPN staat erop, die stel je zelf in.
