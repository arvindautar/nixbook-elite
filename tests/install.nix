# End-to-end install test, offline:
# install from the ISO onto an empty NVMe disk, boot it with Secure Boot
# firmware in Setup Mode, let lanzaboote enroll its keys, then check the
# installed system.
{
  pkgs,
  lib,
  nixbook,
  flakeSource,
}:

let
  # the real system plus the test backdoor
  target = nixbook.extendModules {
    modules = [
      (
        { modulesPath, pkgs, ... }:
        {
          imports = [ "${modulesPath}/testing/test-instrumentation.nix" ];
          # lsattr, for the No_COW check on the libvirt subvolume
          environment.systemPackages = [ pkgs.e2fsprogs ];
          boot.initrd.availableKernelModules = [ "virtio_console" ];
          # LUKS prompt on the serial console so the test can answer it
          boot.plymouth.enable = lib.mkForce false;
          # no network here, don't keep retrying Flathub
          systemd.services.flatpak-managed-install.serviceConfig.Restart = lib.mkForce "no";
          systemd.user.services.nixbook-gradia-capture.serviceConfig.Restart = lib.mkForce "no";
        }
      )
    ];
  };

  installScript = import ../installer/script.nix {
    inherit
      pkgs
      lib
      flakeSource
      target
      ;
  };

  ovmf = pkgs.OVMFFull.fd;
  luks = "correct horse battery staple";
  installEnv = "NB_USER=alice NB_FULLNAME='Alice Test' NB_PASSWORD=foobar123 NB_LUKS='${luks}' NB_CONFIRM=yes";
in
pkgs.testers.runNixOSTest {
  name = "nixbook-install";
  globalTimeout = 2 * 60 * 60;

  nodes.installer =
    { ... }:
    {
      virtualisation = {
        useEFIBoot = true;
        memorySize = 4096;
        cores = 4;
        additionalPaths = [ target.config.system.build.toplevel ];
        qemu.options = [
          "-drive file=nvme.qcow2,if=none,id=nvm,format=qcow2"
          "-device nvme,serial=nixbook0,drive=nvm"
        ];
      };
      # to read the LUKS header back; disko's copy isn't on PATH after the install
      environment.systemPackages = [
        installScript
        pkgs.cryptsetup
      ];
      nix.settings.substituters = lib.mkForce [ ];
    };

  testScript = ''
    import os, re, select, shutil, subprocess

    disk = os.path.join(installer.state_dir, "nvme.qcow2")
    subprocess.run(["${pkgs.qemu_kvm}/bin/qemu-img", "create", "-f", "qcow2", disk, "24G"], check=True)

    with subtest("install"):
        installer.start()
        installer.wait_for_unit("multi-user.target")
        # must fail before anything is wiped
        installer.fail("${installEnv} NB_PASSWORD= nixbook-install < /dev/null")
        installer.fail("${installEnv} NB_LUKS= nixbook-install < /dev/null")
        installer.fail("${installEnv} NB_USER=nordvpn nixbook-install < /dev/null")
        installer.fail("${installEnv} NB_USER=Alice nixbook-install < /dev/null")
        installer.fail("${installEnv} NB_FULLNAME=a:b nixbook-install < /dev/null")
        installer.fail("test -e /dev/nvme0n1p1")
        print(installer.succeed("${installEnv} nixbook-install 2>&1"))
        installer.succeed("test ! -e /tmp/nixbook-luks.key")
        installer.succeed("cryptsetup luksDump /dev/nvme0n1p2 | grep -q 'Version:.*2'")
        installer.succeed("cryptsetup luksDump /dev/nvme0n1p2 | grep -q argon2id")
        installer.succeed("test -f /mnt/etc/nixos/flake.nix -a -f /mnt/etc/nixos/flake.lock")
        # groups are there before the first boot
        for g in ["wheel", "networkmanager", "libvirtd", "nordvpn", "video", "audio"]:
            installer.succeed(f"grep -E '^{g}:.*[:,]alice(,|$)' /mnt/etc/group")
        installer.shutdown()

    # Secure Boot capable firmware with an empty key store (Setup Mode)
    vars = os.path.join(installer.state_dir, "OVMF_VARS.fd")
    shutil.copy("${ovmf}/FV/OVMF_VARS.fd", vars)
    os.chmod(vars, 0o644)
    start_cmd = (
        "${pkgs.qemu_kvm}/bin/qemu-kvm -cpu max -m 4096 -smp 4 -enable-kvm "
        "-machine type=q35,smm=on -global driver=cfi.pflash01,property=secure,value=on "
        "-drive if=pflash,format=raw,unit=0,readonly=on,file=${ovmf}/FV/OVMF_CODE.fd "
        f"-drive if=pflash,format=raw,unit=1,file={vars} "
        f"-drive file={disk},if=none,id=nvm,format=qcow2 -device nvme,serial=nixbook0,drive=nvm "
    )
    laptop = create_machine(start_cmd, name="laptop")

    def unlock():
        laptop.wait_for_console_text("Please enter passphrase for disk")
        laptop.send_console("${luks}\n")

    def drop_stale_shell():
        # The backdoor banner from boot 1 is still in the virtio-console buffer.
        # connect() would take it for a live shell and then read the enroll
        # screen as command output.
        laptop.connected = False
        if laptop.shell is None:
            return
        while True:
            ready, _, _ = select.select([laptop.shell], [], [], 0.2)
            if not ready:
                break
            if not laptop.shell.recv(4096):
                break

    with subtest("boot 1: unlock, keys generated + prepared, automatic reboot"):
        # allow_reboot keeps QEMU running across the lanzaboote reboot. The kernel
        # prints "Restarting system" without the "reboot:" prefix.
        laptop.start(allow_reboot=True)
        unlock()
        laptop.wait_for_console_text("Restarting system")
        drop_stale_shell()

    with subtest("boot 2: systemd-boot enrolls the keys and resets; boot 3: Secure Boot on"):
        unlock()
        laptop.wait_for_unit("multi-user.target")
        print(laptop.succeed("bootctl status 2>&1 | head -20"))
        laptop.succeed("bootctl status 2>&1 | grep -E 'Secure Boot: enabled \\(user\\)'")
        print(laptop.succeed("sbctl status"))
        print(laptop.succeed("sbctl verify 2>&1 || true"))

    with subtest("disk layout"):
        print(laptop.succeed("lsblk -f; findmnt -no SOURCE,OPTIONS /"))
        laptop.succeed("cryptsetup status cryptroot | grep -q 'discards'")
        laptop.succeed("findmnt -no OPTIONS / | grep -q compress=zstd:1")
        for mp in ["/home", "/nix", "/var/log", "/var/lib/libvirt/images"]:
            laptop.succeed(f"findmnt {mp}")
        print(laptop.succeed("lsattr -d /var/lib/libvirt/images"))
        laptop.succeed("lsattr -d /var/lib/libvirt/images | grep -q C")

    with subtest("kernel, memory"):
        laptop.succeed("uname -r | grep -q '^6\\.18\\.'")
        laptop.succeed("swapon --show=NAME,PRIO | grep -q 'zram0 *100'")
        laptop.succeed("grep -q zstd /sys/block/zram0/comp_algorithm")
        laptop.succeed("test $(sysctl -n vm.swappiness) = 180")

    with subtest("first boot: the installed account, a normal login screen"):
        laptop.succeed("test \"$(getent passwd alice | cut -d: -f5)\" = 'Alice Test'")
        laptop.succeed("passwd -S alice | grep -q ' P '")
        laptop.wait_for_unit("display-manager.service")
        # no initial setup, neither in GDM nor at first login
        laptop.wait_until_succeeds("pgrep -f '[g]nome-shell'", timeout=300)
        laptop.fail("pgrep -af '[g]nome-initial-setup'")
        laptop.fail("test -e /etc/xdg/autostart/gnome-initial-setup-first-login.desktop")

    with subtest("the first account gets the admin groups"):
        laptop.wait_until_succeeds("id -nG alice | grep -qw nordvpn", timeout=60)
        out = laptop.succeed("id alice")
        print(out)
        laptop.succeed("test $(id -u alice) = 1000")
        laptop.fail("id gebruiker")
        laptop.succeed("test $(stat -c %a /home/alice) = 700")
        for g in ["wheel", "networkmanager", "libvirtd", "nordvpn", "video", "audio"]:
            assert g in out, f"alice not in {g}"
        laptop.succeed("passwd -S root | grep -qE ' (L|NP|LK) '")

    with subtest("a standard account gets no admin groups"):
        laptop.succeed(
            "busctl call org.freedesktop.Accounts /org/freedesktop/Accounts "
            "org.freedesktop.Accounts CreateUser ssi bob 'Bob Test' 0"
        )
        laptop.wait_until_succeeds("grep -qx 'bob:165536:65536' /etc/subuid", timeout=60)
        out = laptop.succeed("id -nG bob")
        for g in ["wheel", "libvirtd", "nordvpn"]:
            assert g not in out.split(), f"bob in {g}: {out}"

    with subtest("an administrator made in GNOME Settings gets the admin groups"):
        # adding the groups triggers the path unit again, must not hit the start limit
        laptop.succeed(
            "busctl call org.freedesktop.Accounts /org/freedesktop/Accounts "
            "org.freedesktop.Accounts CreateUser ssi carol 'Carol Test' 1"
        )
        laptop.wait_until_succeeds("id -nG carol | grep -qw nordvpn", timeout=60)
        out = laptop.succeed("id -nG carol").split()
        for g in ["wheel", "networkmanager", "libvirtd", "nordvpn", "video", "audio"]:
            assert g in out, f"carol not in {g}: {out}"
        laptop.succeed("systemctl is-active nixbook-setup-accounts.path")
        laptop.fail("systemctl is-failed nixbook-setup-accounts.service")
        laptop.succeed("userdel -r carol")

    with subtest("accounts can run rootless containers"):
        # alice isn't declared anywhere, so NixOS gives her no subuids;
        # nixbook-setup-accounts has to, also after activation
        laptop.succeed("grep -qx 'alice:100000:65536' /etc/subuid")
        laptop.succeed("grep -qx 'alice:100000:65536' /etc/subgid")
        laptop.succeed("grep -q '\"alice\":100000' /var/lib/nixos/auto-subuid-map")
        laptop.succeed("/run/current-system/activate")
        laptop.succeed("test $(grep -c '^alice:' /etc/subuid) = 1")
        laptop.succeed("grep -qx 'alice:100000:65536' /etc/subuid")
        laptop.succeed("id -nG alice | grep -qw libvirtd")
        out = laptop.succeed("runuser -u alice -- podman unshare cat /proc/self/uid_map")
        assert "100000" in out, out
        laptop.succeed("userdel -r bob")
    with subtest("a generation that would delete the installed user is refused"):
        # no generation has declared alice yet
        laptop.succeed("/run/current-system/bin/switch-to-configuration check")
        # once one has, NixOS would delete her from later generations
        laptop.succeed("cp /var/lib/nixos/declarative-users /tmp/decl")
        laptop.succeed("printf ' alice' >> /var/lib/nixos/declarative-users")
        out = laptop.fail("/run/current-system/bin/switch-to-configuration check 2>&1")
        assert "alice" in out, out
        laptop.succeed("cp /tmp/decl /var/lib/nixos/declarative-users")

    with subtest("fonts as on Omarchy, also for Flatpaks"):
        fc = "${target.pkgs.fontconfig.bin}/bin/fc-match -f '%{family}\\n'"
        for generic, family in [
            ("sans-serif", "Liberation Sans"),
            ("serif", "Liberation Serif"),
            ("monospace", "JetBrainsMono Nerd Font"),
            ("system-ui", "Liberation Sans"),
            ("emoji", "Noto Color Emoji"),
            ("Arial", "Liberation Sans"),
            ("Times New Roman", "Liberation Serif"),
            ("Courier New", "Liberation Mono"),
            ("Helvetica", "TeX Gyre Heros"),
        ]:
            out = laptop.succeed(fc + " '" + generic + "'")
            print(generic, "->", out)
            assert family in out, (generic, out)
        # the copy flatpaks read
        conf = "/home/alice/.config/fontconfig/conf.d/50-nixbook-fonts.conf"
        script = laptop.succeed(
            "sed -n 's/^ExecStart=//p' /etc/systemd/user/nixbook-fontconfig.service"
        ).strip()
        laptop.succeed(f"runuser -u alice -- env HOME=/home/alice {script}")
        laptop.succeed(f"test $(stat -c %U {conf}) = alice")
        # specifiers that need a session get skipped here, so check the result,
        # not the exit code
        laptop.execute("runuser -u alice -- env HOME=/home/alice systemd-tmpfiles --user --create")
        laptop.succeed(f"test -f {conf} && ! test -L {conf} && grep -q 'Liberation Sans' {conf}")
        laptop.succeed("grep -qx 'font-family = JetBrainsMono Nerd Font' /home/alice/.config/ghostty/config")
        laptop.succeed("grep -q 'xdg-config/fontconfig:ro' /var/lib/flatpak/overrides/global")

    with subtest("fingerprint only for login and the lock screen"):
        laptop.succeed("grep -q pam_fprintd /etc/pam.d/gdm-fingerprint")
        for svc in ["sudo", "su", "polkit-1", "systemd-run0", "passwd", "useradd", "other"]:
            laptop.succeed(f"test -f /etc/pam.d/{svc} && ! grep -q pam_fprintd /etc/pam.d/{svc}")

    with subtest("DHCPv6 identity differs per network"):
        # ask NetworkManager, not the file
        conf = laptop.succeed("NetworkManager --print-config")
        print(conf)
        assert "ipv6.dhcp-duid=stable-uuid" in conf, conf
        # Wi-Fi only
        assert "unmanaged-devices=type:ethernet" in conf, conf

    with subtest("firmware updates, reboot reminder, container image cleanup"):
        # nothing to update in the VM, so the check stays quiet
        laptop.succeed("systemctl start nixbook-firmware-check.service")
        laptop.succeed("test ! -e /var/lib/nixbook-upgrade/firmware-notified")
        tile = laptop.succeed("readlink -f $(command -v nixbook-update)").strip()
        fw = laptop.succeed(f"grep -o '/nix/store/[a-z0-9]*-nixbook-firmware-update' {tile} | head -1").strip()
        laptop.succeed(f"grep -q -- '--no-unreported-check' {fw}")
        # nothing to update counts as success
        laptop.succeed(fw)
        # booted system is the newest one, so no reminder
        laptop.succeed("systemctl start nixbook-reboot-reminder.service")
        laptop.succeed("test -f /etc/systemd/user/nixbook-podman-prune.service")
        laptop.succeed("runuser -u alice -- podman image prune --force")

    with subtest("security"):
        laptop.succeed("cat /sys/kernel/security/lsm | grep -q apparmor")
        laptop.succeed("nft list ruleset | grep -q 'chain input'")
        laptop.succeed("test $(sysctl -n kernel.kptr_restrict) = 2")
        laptop.fail("systemctl is-active sshd")
        print(laptop.succeed("ss -tulpn"))

    with subtest("desktop and apps"):
        laptop.wait_for_unit("display-manager.service")
        for b in ["ghostty", "nautilus", "bazaar", "flatpak", "claude", "codex",
                  "grok", "nordvpn", "nordvpn-gui", "distrobox", "podman", "virsh", "nixbook-update",
                  "gnome-disks", "gnome-system-monitor", "nixbook-secureboot", "nixbook-enroll",
                  "nixbook-backup-recovery", "nixbook-backup-home"]:
            laptop.succeed(f"command -v {b}")
        laptop.fail("command -v gnome-software")
        laptop.fail("command -v gnome-text-editor")
        laptop.succeed("systemctl is-active nordvpnd.socket")
        # must be a real file, flatpaks can't see /nix/store
        p = "/etc/brave/policies/managed/nixbook.json"
        laptop.succeed(f"test -f {p} && ! test -L {p} && grep -q : {p}")
        laptop.succeed(f"grep -q '\"BraveAIChatEnabled\":false' {p}")
        # en_GB is available in Settings
        laptop.succeed("locale -a | grep -qi '^en_GB.utf-\\?8$'")

    with subtest("gradia-capture installs in the graphical user's home"):
        # No internet, so the clone isn't run. Check the script has the right
        # steps: ls-remote, shallow clone into a temp dir, bash build.sh (no
        # /bin/bash on NixOS), install the zip, remove the clone.
        laptop.succeed(
            "test -L /etc/systemd/user/graphical-session.target.wants/nixbook-gradia-capture.service"
        )
        script = laptop.succeed(
            "sed -n 's/^ExecStart=//p' /etc/systemd/user/nixbook-gradia-capture.service"
        ).strip()
        assert script, "no ExecStart"
        laptop.succeed(
            f"grep -q 'flatpak info --system be.alexandervanhee.gradia' {script}; "
            f"grep -q 'repo=https://github.com/AlexanderVanhee/gradia-capture' {script}; "
            f"grep -qF 'git ls-remote \"$repo\" HEAD' {script}; "
            f"grep -qF 'src=$(mktemp -d)' {script}; "
            f"grep -qF 'git clone --depth 1 \"$repo\" \"$src\"' {script}; "
            f"grep -qF 'rm -rf \"$src\"' {script}; "
            f"grep -q 'bash build.sh' {script}; "
            f"grep -q 'gnome-extensions install --force' {script}"
        )
        laptop.fail("grep -E '^(User|Group)=' /etc/systemd/user/nixbook-gradia-capture.service")
        # the greeter (uid > 29999) is skipped without retries
        laptop.succeed(f"runuser -u nobody -- env HOME=/tmp/greeter {script}")
        laptop.fail("test -e /tmp/greeter/Downloads")
        # old ~/Downloads checkout: removed if untouched, kept if the user changed it
        old = "/home/alice/Downloads/gradia-capture"
        laptop.succeed(
            f"runuser -u alice -- sh -c 'mkdir -p {old} && cd {old} && git init -q && "
            "git remote add origin https://github.com/AlexanderVanhee/gradia-capture'"
        )
        laptop.fail(f"runuser -u alice -- env HOME=/home/alice {script}")
        laptop.fail(f"test -e {old}")
        laptop.succeed(
            f"runuser -u alice -- sh -c 'mkdir -p {old} && cd {old} && git init -q && "
            "git remote add origin https://github.com/AlexanderVanhee/gradia-capture && touch mine'"
        )
        # a real user waits for the Gradia flatpak, which isn't there offline
        laptop.fail(f"runuser -u alice -- env HOME=/home/alice {script}")
        laptop.succeed(f"test -e {old}/mine")
        laptop.succeed(f"rm -rf {old}")
        laptop.fail("test -e /etc/systemd/system/nixbook-gradia-capture.service")
        laptop.fail("test -e /run/current-system/sw/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io")

    with subtest("the flake is in /etc/nixos, without any account in it"):
        laptop.succeed("test -f /etc/nixos/flake.nix -a -f /etc/nixos/flake.lock")
        laptop.fail("test -e /etc/nixos/hosts/elitebook/user.json")

    with subtest("time zone: Amsterdam to start with, the user's choice after that"):
        def zone():
            # timedated caches the zone while it runs, restart it and also check
            # the link itself
            laptop.succeed("systemctl stop systemd-timedated.service")
            link = laptop.succeed("readlink /etc/localtime").strip()
            live = laptop.succeed("timedatectl show -p Timezone --value").strip()
            assert link.endswith("/" + live), (link, live)
            return live

        assert zone() == "Europe/Amsterdam", zone()
        # what Settings > Date & Time does
        laptop.succeed("timedatectl set-timezone Europe/London")
        assert zone() == "Europe/London", zone()
        # rebuild keeps it
        laptop.succeed("/run/current-system/activate")
        assert zone() == "Europe/London", zone()
        # no zone at all: back to Amsterdam
        laptop.succeed("rm /etc/localtime && /run/current-system/activate")
        assert zone() == "Europe/Amsterdam", zone()

    with subtest("random Windows-style hostname from the installer"):
        host = laptop.succeed("cat /etc/hostname").strip()
        print(host)
        assert re.fullmatch(r"DESKTOP-[A-HJ-NP-Z0-9]{7}", host), host
        # static hostname, not the transient IPv6 name NetworkManager would set
        assert laptop.succeed("hostnamectl --static").strip() == host, host
        assert laptop.succeed("hostname").strip() == host, host
        laptop.fail("test -L /etc/hostname")
        # rebuild keeps it
        laptop.succeed("/run/current-system/activate")
        assert laptop.succeed("hostnamectl --static").strip() == host
        laptop.succeed(f"test \"$(cat /etc/hostname)\" = {host}")
        # older installs lose the NixOS-made file on the first rebuild, the
        # running name gets written back
        laptop.succeed("rm /etc/hostname && /run/current-system/activate")
        laptop.succeed(f"test \"$(cat /etc/hostname)\" = {host}")

    with subtest("report"):
        print(laptop.succeed("systemctl --failed --no-legend || true"))
        # only the Flathub install may fail, there's no internet here
        failed = set(laptop.succeed("systemctl --failed --plain --no-legend | awk '{print $1}'").split())
        assert failed <= {"flatpak-managed-install.service"}, failed
        print(laptop.succeed("systemd-analyze || true"))
        print(laptop.succeed("systemd-analyze blame | head -15 || true"))
        laptop.shutdown()
  '';
}
