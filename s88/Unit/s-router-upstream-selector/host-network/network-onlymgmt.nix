{
  config,
  pkgs,
  lib,
  ...
}:

let
  management_interface = "ens18";
  upstream_VPN_interface = "ens19";
  vpnNATInterface = "ens20";

  vpnInterface = "tun0";
  vpnConfBasePath = "/etc/vpn";
  vpnConfPath = "${vpnConfBasePath}/${vpnInterface}.conf";
  vpnIPv4WithMask = "10.90.0.1/24";
  vpnIPv6WithMask = "fd90:dead:beef::100/64";

  vrf_table_vpn = 10;
  vrf_name_vpn = "vrf-vpn";

in
{

  environment.systemPackages = with pkgs; [
    dnsutils
    openvpn
    wireguard-tools
    tcpdump
    traceroute
    nftables
    dhcpcd
    tmux
  ];

  networking.networkmanager.enable = false;

  systemd.network.networks."10-mgmt" = {
    matchConfig.Name = management_interface;
    networkConfig.DHCP = "yes";
    routingPolicyRules = [
      {
        Priority = 100;
        From = "192.168.1.0/24";
        Table = "main";
      }
    ];
  };

  networking.useNetworkd = true;

  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
