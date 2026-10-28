# Random MACs, no hostname in DHCP, IPv6 privacy addresses. DNS comes from the
# network on purpose, resolved just makes sure it doesn't go anywhere else.
{ ... }:

{
  networking.networkmanager = {
    wifi = {
      # per-SSID MAC, stable so captive portals don't ask again
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
        # the default DUID comes from machine-id, i.e. the same on every network
        "ipv6.dhcp-duid" = "stable-uuid";
        "connection.llmnr" = 0;
        # avahi does mDNS (printers)
        "connection.mdns" = 0;
      };
      # no connectivity check pings
      connectivity.enabled = false;
    };
    dns = "systemd-resolved";
    # Wi-Fi only. Also covers USB-C docks/monitors with a network port and USB
    # tethering. Remove to use a cable again.
    unmanaged = [ "type:ethernet" ];
  };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      # no fallback to Google/Cloudflare
      FallbackDNS = "";
      LLMNR = "no";
      MulticastDNS = "no";
    };
  };

  networking.tempAddresses = "default";
}
