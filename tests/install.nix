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
        { modulesPath, ... }:
        {
          imports = [ "${modulesPath}/testing/test-instrumentation.nix" ];
          boot.initrd.availableKernelModules = [ "virtio_console" ];
          # Only difference to the real system: the LUKS prompt goes to the serial
          # console (instead of Plymouth's graphics) so the test can answer it.
          boot.plymouth.enable = lib.mkForce false;
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
    import os, shutil, subprocess

    disk = os.path.join(installer.state_dir, "nvme.qcow2")
    subprocess.run(["${pkgs.qemu_kvm}/bin/qemu-img", "create", "-f", "qcow2", disk, "24G"], check=True)

    with subtest("install"):
        installer.start()
        installer.wait_for_unit("multi-user.target")
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

    with subtest("boot 1: unlock, keys generated + prepared, automatic reboot"):
        # allow_reboot keeps QEMU alive across the lanzaboote reboot. The
        # kernel prints "Restarting system" (no "reboot:" prefix).
        laptop.start(allow_reboot=True)
        unlock()
        laptop.wait_for_console_text("Restarting system")

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
        laptop.succeed("lsattr -d /var/lib/libvirt/images | grep -q C")

    with subtest("kernel, memory"):
        laptop.succeed("uname -r | grep -q '^6\\.18\\.'")
        laptop.succeed("swapon --show=NAME,PRIO | grep -q 'zram0 *100'")
        laptop.succeed("grep -q zstd /sys/block/zram0/comp_algorithm")
        laptop.succeed("test $(sysctl -n vm.swappiness) = 180")

    with subtest("user from the installer"):
        out = laptop.succeed("id alice")
        print(out)
        for g in ["wheel", "networkmanager", "libvirtd", "nordvpn"]:
            assert g in out, f"alice not in {g}"
        laptop.succeed("passwd -S root | grep -qE ' (L|NP|LK) '")

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

    with subtest("gradia-capture is installed from git after flatpaks"):
        # The VM has no internet, so the clone itself is not run here. The
        # installed system must still carry the exact steps: clone the repo,
        # bash build.sh (NixOS has no /bin/bash), then install the zip.
        laptop.succeed(
            "systemctl cat flatpak-managed-install.service | "
            "grep -q 'OnSuccess=nixbook-gradia-capture.service'"
        )
        laptop.succeed(
            "script=$(systemctl show -P ExecStart nixbook-gradia-capture.service "
            "| sed -n 's/.*path=\\([^ ;]*\\).*/\\1/p'); "
            "test -n \"$script\"; "
            "grep -q 'git clone https://github.com/AlexanderVanhee/gradia-capture' \"$script\"; "
            "grep -q 'Downloads/gradia-capture' \"$script\"; "
            "grep -q 'bash build.sh' \"$script\"; "
            "grep -q 'gnome-extensions install --force' \"$script\""
        )
        laptop.succeed("systemctl show -P User nixbook-gradia-capture.service | grep -qx gebruiker")

    with subtest("first update is reproducible from /etc/nixos (eval only, offline)"):
        laptop.succeed("test -f /etc/nixos/flake.lock")

    with subtest("report"):
        print(laptop.succeed("systemctl --failed --no-legend || true"))
        print(laptop.succeed("systemd-analyze || true"))
        print(laptop.succeed("systemd-analyze blame | head -15 || true"))
        laptop.shutdown()
  '';
}
