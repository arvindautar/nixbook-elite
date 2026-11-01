# What the laptop really tells a DHCP server, read from the wire at the other
# end. A value NetworkManager can't parse is ignored without a word, and
# `--print-config` just repeats it, so looking at the config proves nothing.
#
# Only privacy.nix is loaded, so this takes minutes, not a whole install. The
# laptop is Wi-Fi only; here a cable stands in for it, because the DHCP client
# and these settings are the same on both.
{ pkgs, lib }:

pkgs.testers.runNixOSTest {
  name = "nixbook-privacy";

  nodes.router = {
    virtualisation.vlans = [ 1 ];
    environment.systemPackages = [ pkgs.tcpdump ];
    networking = {
      useDHCP = false;
      firewall.enable = false;
      interfaces.eth1.ipv6.addresses = [
        {
          address = "fd00:1::1";
          prefixLength = 64;
        }
      ];
    };
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        port = 0; # DHCP only
        interface = "eth1";
        bind-interfaces = true;
        dhcp-range = [
          "192.168.1.100,192.168.1.200"
          "fd00:1::100,fd00:1::200,64"
        ];
        # tells the laptop to use DHCPv6, not only SLAAC
        enable-ra = true;
      };
    };
  };

  nodes.laptop = {
    imports = [ ../modules/privacy.nix ];
    virtualisation.vlans = [ 1 ];
    networking = {
      useDHCP = false;
      # only NetworkManager configures eth1
      interfaces = lib.mkForce { eth1 = { }; };
      networkmanager = {
        enable = true;
        # privacy.nix ignores wired ports; eth0 is the test driver's own
        unmanaged = lib.mkForce [ "interface-name:eth0" ];
        settings.main.no-auto-default = "*";
      };
    };
  };

  # The laptop with a USB-C monitor's network port. privacy.nix as it ships, so
  # wired ports are ignored; to NetworkManager a USB adapter is ethernet too.
  nodes.docked = {
    imports = [ ../modules/privacy.nix ];
    virtualisation.vlans = [ 1 ];
    networking = {
      # no static test address
      interfaces = lib.mkForce { };
      networkmanager.enable = true;
    };
  };

  testScript = ''
    router.start()
    laptop.start()
    router.wait_for_unit("dnsmasq.service")
    laptop.wait_for_unit("NetworkManager.service")
    laptop.succeed("nmcli connection add type ethernet ifname eth1 con-name uplink autoconnect no")
    hostname = laptop.succeed("hostname").strip()

    def lease(name):
        """Get IPv4 and DHCPv6 leases, return what each protocol sent as text."""
        pcap = f"/tmp/{name}.pcap"
        router.succeed(
            f"systemd-run --unit=capture-{name} tcpdump -Z root -U --immediate-mode -ni eth1 -w {pcap} "
            "udp port 67 or udp port 68 or udp port 546 or udp port 547"
        )
        router.wait_until_succeeds(f"journalctl -u capture-{name} | grep -q 'listening on'")
        laptop.succeed("nmcli connection up uplink")
        laptop.wait_until_succeeds("ip -4 addr show eth1 | grep -qE 'inet 192\\.168\\.1\\.[12][0-9]{2}/'", timeout=60)
        laptop.wait_until_succeeds("ip -6 addr show eth1 | grep -q 'inet6 fd00:1::.*/128'", timeout=60)
        laptop.succeed("nmcli connection down uplink")
        router.succeed(f"systemctl stop capture-{name}")
        v4 = router.succeed(f"tcpdump -nn -A -r {pcap} 'udp port 67 or udp port 68'")
        v6 = router.succeed(f"tcpdump -nn -A -r {pcap} 'udp port 546 or udp port 547'")
        print(v4, v6)
        assert v4 and v6, "no DHCP traffic captured"
        return v4, v6

    with subtest("the hostname stays off the wire"):
        v4, v6 = lease("private")
        assert hostname not in v4, v4
        assert hostname not in v6, v6

    with subtest("the capture would have seen it"):
        # without this the test above also passes if the name is just not
        # readable in the capture
        laptop.succeed(
            "nmcli connection modify uplink "
            "ipv4.dhcp-send-hostname true ipv6.dhcp-send-hostname true"
        )
        v4, v6 = lease("control")
        assert hostname in v4, v4
        assert hostname in v6, v6

    with subtest("settings the wire can't show"):
        # NetworkManager's fallback for a mode it can't read is the same mode
        conf = laptop.succeed("NetworkManager --print-config")
        for setting in [
            "ipv6.addr-gen-mode=1",
            "ipv4.dhcp-client-id=stable",
            "ipv6.dhcp-iaid=stable",
            "hostname-mode=none",
        ]:
            assert setting in conf, (setting, conf)

    with subtest("a live network cable is ignored"):
        router.succeed("systemd-run --unit=capture-docked tcpdump -Z root -U -ni eth1 -w /tmp/docked.pcap")
        router.wait_until_succeeds("journalctl -u capture-docked | grep -q 'listening on'")
        docked.start()
        docked.wait_for_unit("multi-user.target")
        docked.wait_for_unit("NetworkManager.service")
        # long enough for any DHCP client to have started
        docked.sleep(30)
        docked.succeed("nmcli -t -f DEVICE,STATE device | grep -qx 'eth1:unmanaged'")
        docked.succeed("ip -o link show eth1 | grep -q 'state DOWN'")
        docked.fail("ip -o addr show eth1 | grep -q inet")
        mac = docked.succeed("cat /sys/class/net/eth1/address").strip()
        frames = router.succeed(f"tcpdump -nn -r /tmp/docked.pcap ether src {mac}")
        assert not frames, frames

    with subtest("the capture would have seen a frame from that port"):
        docked.succeed("ip link set eth1 up")
        router.wait_until_succeeds(f"tcpdump -nn -r /tmp/docked.pcap ether src {mac} | grep -q .", timeout=60)
  '';
}
