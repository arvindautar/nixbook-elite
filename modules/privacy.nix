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
      # NetworkManager reads these as numbers and silently ignores anything else,
      # so `false` still sends the hostname. tests/privacy.nix watches the wire.
      connection = {
        "ipv4.dhcp-send-hostname" = 0;
        "ipv6.dhcp-send-hostname" = 0;
        "ipv6.ip6-privacy" = 2;
        "ipv6.addr-gen-mode" = 1; # stable-privacy
        # the default DUID comes from machine-id, i.e. the same on every network
        "ipv6.dhcp-duid" = "stable-uuid";
        # same idea for the other DHCP identifiers: one per network
        "ipv4.dhcp-client-id" = "stable";
        "ipv6.dhcp-iaid" = "stable";
        "connection.llmnr" = 0;
        # avahi does mDNS (printers)
        "connection.mdns" = 0;
      };
      # a network can't name this laptop through DHCP
      main.hostname-mode = "none";
      # no connectivity check pings
      connectivity.enabled = false;
    };
    dns = "systemd-resolved";
    # Wi-Fi only. Also covers USB-C docks/monitors with a network port and USB
    # tethering. Power and display over USB-C aren't affected. Remove to use a
    # cable again.
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
