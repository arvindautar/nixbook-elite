# End-to-end install test, fully offline:
#  1. boot an installer VM with an empty NVMe disk, run `nixbook-install`
#  2. boot the installed disk with Secure Boot firmware in Setup Mode
#  3. unlock LUKS, let lanzaboote generate + enroll keys (auto reboot)
#  4. verify Secure Boot, desktop, security, zram, VPN, AI tools, ...
{
  pkgs,
  lib,
  nixbook,
  flakeSource,
}:

let
  # The real system plus the test backdoor so the driver can run commands in it
  target = nixbook.extendModules {
    modules = [
      (
        { modulesPath, pkgs, ... }:
        {
          imports = [ "${modulesPath}/testing/test-instrumentation.nix" ];
          # lsattr checks the No_COW flag on the libvirt subvolume.
          environment.systemPackages = [ pkgs.e2fsprogs ];
          boot.initrd.availableKernelModules = [ "virtio_console" ];
          # The LUKS prompt goes to the serial console so the test can answer it.
          boot.plymouth.enable = lib.mkForce false;
          # This VM has no network. Don't retry Flathub for the whole test.
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
      # cryptsetup is how the test reads the LUKS header back. Disko brings its
      # own copy for the install, which is not on PATH afterwards.
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
        # Refused before anything is wiped: names the system already uses, and
        # a full name that useradd would only reject after the install.
        for env in ["NB_USER=gdm NB_FULLNAME=x", "NB_USER=nordvpn NB_FULLNAME=x",
                    "NB_USER=bob NB_FULLNAME='Bob: Test'"]:
            out = installer.fail(
                f"{env} NB_PASSWORD=foobar123 NB_LUKS='${luks}' NB_CONFIRM=yes nixbook-install 2>&1"
            )
            assert "Ongeldige" in out, out
        installer.fail("test -e /dev/nvme0n1p1")
        print(installer.succeed(
            "NB_USER=alice NB_FULLNAME='Alice Test' NB_PASSWORD=foobar123 "
            "NB_LUKS='${luks}' NB_CONFIRM=yes nixbook-install 2>&1"
        ))
        installer.succeed("test ! -e /tmp/nixbook-luks.key")
        installer.succeed("cryptsetup luksDump /dev/nvme0n1p2 | grep -q 'Version:.*2'")
        installer.succeed("cryptsetup luksDump /dev/nvme0n1p2 | grep -q argon2id")
        installer.succeed("test -f /mnt/etc/nixos/flake.nix -a -f /mnt/etc/nixos/flake.lock")
        installer.shutdown()

    # Secure Boot capable firmware with empty key store (= Setup Mode)
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
        # Boot 1's backdoor banner stays in the virtio-console buffer across
        # the reboot. connect() would treat that old banner as a live shell
        # and then read the Secure Boot enroll screen as a command result.
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
        # allow_reboot keeps QEMU alive across the lanzaboote reboot. The
        # kernel prints "Restarting system" (no "reboot:" prefix).
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

    with subtest("user from the installer"):
        out = laptop.succeed("id alice")
        print(out)
        laptop.succeed("test $(id -u alice) = 1000")
        laptop.fail("id gebruiker")
        laptop.succeed("test $(stat -c %a /home/alice) = 700")
        for g in ["wheel", "networkmanager", "libvirtd", "nordvpn"]:
            assert g in out, f"alice not in {g}"
        laptop.succeed("passwd -S root | grep -qE ' (L|NP|LK) '")

    with subtest("a generation that would delete the installed user is refused"):
        # The installed generation was built before alice existed and never
        # declared her, so it passes.
        laptop.succeed("/run/current-system/bin/switch-to-configuration check")
        # Once a generation has declared her, NixOS deletes her from any later
        # generation without her. The pre-switch check must stop that.
        laptop.succeed("cp /var/lib/nixos/declarative-users /tmp/decl")
        laptop.succeed("printf ' alice' >> /var/lib/nixos/declarative-users")
        out = laptop.fail("/run/current-system/bin/switch-to-configuration check 2>&1")
        assert "alice" in out, out
        laptop.succeed("cp /tmp/decl /var/lib/nixos/declarative-users")

    with subtest("security"):
        laptop.succeed("cat /sys/kernel/security/lsm | grep -q apparmor")
        laptop.succeed("nft list ruleset | grep -q 'chain input'")
        laptop.succeed("test $(sysctl -n kernel.kptr_restrict) = 2")
        laptop.fail("systemctl is-active sshd")
        print(laptop.succeed("ss -tulpn"))

    with subtest("desktop and apps"):
        laptop.wait_for_unit("display-manager.service")
        for b in ["firefox", "ghostty", "nautilus", "bazaar", "flatpak", "claude", "codex",
                  "grok", "nordvpn", "nordvpn-gui", "distrobox", "podman", "virsh", "nixbook-update",
                  "gnome-disks", "gnome-system-monitor", "nixbook-secureboot", "nixbook-enroll",
                  "nixbook-backup-recovery", "nixbook-backup-home"]:
            laptop.succeed(f"command -v {b}")
        laptop.fail("command -v gnome-software")
        laptop.fail("command -v gnome-text-editor")
        laptop.succeed("systemctl is-active nordvpnd.socket")

    with subtest("gradia-capture installs in the graphical user's home"):
        # The VM has no internet, so the clone itself is not run here. The
        # installed system must still carry the exact steps: clone the repo,
        # bash build.sh (NixOS has no /bin/bash), then install the zip.
        laptop.succeed(
            "test -L /etc/systemd/user/graphical-session.target.wants/nixbook-gradia-capture.service"
        )
        script = laptop.succeed(
            "sed -n 's/^ExecStart=//p' /etc/systemd/user/nixbook-gradia-capture.service"
        ).strip()
        assert script, "no ExecStart"
        laptop.succeed(
            f"grep -q 'flatpak info --system be.alexandervanhee.gradia' {script}; "
            f"grep -q 'git clone https://github.com/AlexanderVanhee/gradia-capture' {script}; "
            f"grep -q 'Downloads/gradia-capture' {script}; "
            f"grep -q 'bash build.sh' {script}; "
            f"grep -q 'gnome-extensions install --force' {script}"
        )
        laptop.fail("grep -E '^(User|Group)=' /etc/systemd/user/nixbook-gradia-capture.service")
        # The GDM greeter session (uid above 29999) is skipped without retries.
        laptop.succeed(f"runuser -u nobody -- env HOME=/tmp/greeter {script}")
        laptop.fail("test -e /tmp/greeter/Downloads")
        # A real user waits for the Gradia Flatpak, which this offline VM lacks.
        laptop.fail(f"runuser -u alice -- env HOME=/home/alice {script}")
        laptop.fail("test -e /home/alice/Downloads/gradia-capture")
        laptop.fail("test -e /etc/systemd/system/nixbook-gradia-capture.service")
        laptop.fail("test -e /run/current-system/sw/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io")

    with subtest("the flake and the installer's user.json are in /etc/nixos"):
        laptop.succeed("test -f /etc/nixos/flake.nix -a -f /etc/nixos/flake.lock")
        laptop.succeed("grep -q '\"name\": \"alice\"' /etc/nixos/hosts/elitebook/user.json")
        laptop.succeed("grep -q '\"fullName\": \"Alice Test\"' /etc/nixos/hosts/elitebook/user.json")

    with subtest("random Windows-style hostname from the installer"):
        host = laptop.succeed("hostname").strip()
        print(host)
        assert re.fullmatch(r"DESKTOP-[A-HJ-NP-Z0-9]{7}", host), host
        laptop.succeed(f"test \"$(cat /etc/hostname)\" = {host}")
        laptop.succeed(f"grep -q '\"hostName\": \"{host}\"' /etc/nixos/hosts/elitebook/user.json")

    with subtest("report"):
        print(laptop.succeed("systemctl --failed --no-legend || true"))
        print(laptop.succeed("systemd-analyze || true"))
        print(laptop.succeed("systemd-analyze blame | head -15 || true"))
        laptop.shutdown()
  '';
}
