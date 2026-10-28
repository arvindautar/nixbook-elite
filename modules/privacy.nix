# Stay anonymous on networks: random MACs, no hostname in DHCP, IPv6 privacy addresses.
# DNS comes from the network (your choice); resolved only stops it leaking elsewhere.
{ ... }:

{
  networking.networkmanager = {
    wifi = {
      # A different MAC per Wi-Fi network, stable on that network (no re-login at portals)
      macAddress = "stable-ssid";
      scanRandMacAddress = true;
      powersave = true;
    };
    ethernet.macAddress = "stable";
    settings = {
      connection = {
        "ipv4.dhcp-send-hostname" = false;
        "ipv6.dhcp-send-hostname" = false;
        "ipv6.ip6-privacy" = 2;
        "ipv6.addr-gen-mode" = "stable-privacy";
        # NetworkManager's default DHCPv6 identity (DUID) is one ID made from
        # /etc/machine-id, the same on every network. This one differs per network.
        "ipv6.dhcp-duid" = "stable-uuid";
        "connection.llmnr" = 0;
        # mDNS is avahi's job (printers); resolved has it off, see below
        "connection.mdns" = 0;
      };
      # No phoning home to a connectivity-check server
      connectivity.enabled = false;
    };
    dns = "systemd-resolved";
    # Wi-Fi only. Wired ports, including a monitor's or dock's network port
    # over USB-C and USB tethering from a phone, are left alone: no DHCP, no
    # address, nothing sent. Remove this line to use a network cable.
    unmanaged = [ "type:ethernet" ];
  };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      # Never fall back to Google/Cloudflare behind your back
      FallbackDNS = "";
      LLMNR = "no";
      MulticastDNS = "no";
    };
  };

  networking.tempAddresses = "default";
}
