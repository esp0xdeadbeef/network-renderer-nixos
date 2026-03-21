{ lib, pkgs, ... }:
let
  generatedNetworkScript = pkgs.writeShellScript "s-router-core-wan-network" ''
set -euo pipefail
sh -c 'for i in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 0 > "$i"; done'
ip link set eth0 up
ip link set eth1 up
ip link set eth2 up
ip link set lo up
ip addr replace 10.10.0.8/31 peer 10.10.0.9/31 dev eth0
ip -6 addr replace fd42:dead:beef:1000::8/127 peer fd42:dead:beef:1000::9/127 dev eth0
ip addr replace 10.19.0.5/32 dev eth1
ip -6 addr replace fd42:dead:beef:1900::5/128 dev eth1
ip addr replace 10.19.0.2/31 peer 10.19.0.3/31 dev eth2
ip -6 addr replace fd42:dead:beef:1900::2/127 peer fd42:dead:beef:1900::3/127 dev eth2
ip -6 addr replace fe80::3/128 dev eth2
ip addr replace 10.19.0.5/32 dev lo
ip -6 addr replace fd42:dead:beef:1900::5/128 dev lo
ip route replace 10.10.0.0/31 via 10.10.0.9 dev eth0 onlink
ip route replace 10.10.0.10/31 via 10.10.0.9 dev eth0 onlink
ip route replace 10.10.0.2/31 via 10.10.0.9 dev eth0 onlink
ip route replace 10.10.0.4/31 via 10.10.0.9 dev eth0 onlink
ip route replace 10.10.0.6/31 via 10.10.0.9 dev eth0 onlink
ip route replace 10.19.0.1/32 via 10.10.0.9 dev eth0 onlink
ip route replace 10.19.0.2/32 via 10.10.0.9 dev eth0 onlink
ip route replace 10.19.0.3/32 via 10.10.0.9 dev eth0 onlink
ip route replace 10.19.0.4/32 via 10.10.0.9 dev eth0 onlink
ip route replace 10.19.0.6/32 via 10.10.0.9 dev eth0 onlink
ip route replace 10.19.0.7/32 via 10.10.0.9 dev eth0 onlink
ip route replace 10.20.10.0/24 via 10.10.0.9 dev eth0 onlink
ip route replace 10.20.15.0/24 via 10.10.0.9 dev eth0 onlink
ip route replace 10.20.20.0/24 via 10.10.0.9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:10::/64 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:15::/64 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:20::/64 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1000::/127 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1000::2/127 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1000::4/127 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1000::6/127 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1000::a/127 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::4/128 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::6/128 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::7/128 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::1/128 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::2/128 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::3/128 via fd42:dead:beef:1000:0:0:0:9 dev eth0 onlink
ip -6 route replace ::/0 via fd42:dead:beef:1900:0:0:0:3 dev eth2 onlink
ip route replace default via 10.19.0.3 dev eth2 onlink
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
nft flush ruleset
nft add table inet filter
nft 'add chain inet filter input { type filter hook input priority 0 ; policy drop ; }'
nft 'add chain inet filter forward { type filter hook forward priority 0 ; policy accept ; }'
nft 'add chain inet filter output { type filter hook output priority 0 ; policy accept ; }'
nft add rule inet filter input iif lo accept
nft add rule inet filter input ct state established,related accept
nft add rule inet filter input ct state invalid drop
nft add rule inet filter input meta l4proto ipv6-icmp accept
nft add rule inet filter input iifname "eth1" ip saddr { 0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16,224.0.0.0/4,240.0.0.0/4 } drop
nft add rule inet filter input iifname "eth1" ip6 saddr { ::1,fc00::/7,fe80::/10 } drop
nft add rule inet filter input iifname != "eth1" tcp dport 22 accept
nft add rule inet filter forward ct state established,related accept
nft add rule inet filter forward ct state invalid drop
nft add rule inet filter forward iifname "eth1" ip saddr { 10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16 } drop
nft add rule inet filter forward iifname "eth1" ip6 saddr fc00::/7 drop
nft add table ip nat
nft 'add chain ip nat postrouting { type nat hook postrouting priority srcnat ; policy accept ; }'
nft add rule ip nat postrouting ip saddr { 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 } oifname "eth1" masquerade
nft add table inet mangle
nft 'add chain inet mangle forward { type filter hook forward priority mangle ; policy accept ; }'
nft add rule inet mangle forward oifname "eth1" tcp flags syn tcp option maxseg size set rt mtu
  '';
in
{
  networking.hostName = "s-router-core-wan";
  networking.usePredictableInterfaceNames = false;
  boot.kernelParams = [ "net.ifnames=0" "biosdevname=0" ];
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = lib.mkDefault 0;
    "net.ipv4.conf.default.rp_filter" = lib.mkDefault 0;
  };
  environment.systemPackages = with pkgs; [ bash coreutils findutils gnugrep gnused iproute2 nftables procps python3 ] ++ lib.optionals true [ frr ];
  systemd.services."generated-network-s-router-core-wan" = {
    description = "Generated network bootstrap for s-router-core-wan";
    wantedBy = [ "multi-user.target" ];
    wants = [ "systemd-udev-settle.service" ];
    after = [ "local-fs.target" "systemd-udev-settle.service" ];
    before = [ "network-online.target" ];
    path = with pkgs; [ bash coreutils findutils gnugrep gnused iproute2 nftables procps python3 ] ++ lib.optionals true [ frr systemd ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = generatedNetworkScript;
    };
  };
}
