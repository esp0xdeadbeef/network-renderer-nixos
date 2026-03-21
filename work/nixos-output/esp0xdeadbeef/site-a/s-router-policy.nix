{ lib, pkgs, ... }:
let
  generatedNetworkScript = pkgs.writeShellScript "s-router-policy-network" ''
set -euo pipefail
sh -c 'for i in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 0 > "$i"; done'
ip link set eth0 up
ip link set eth1 up
ip link set eth2 up
ip link set eth3 up
ip link set eth4 up
ip link set lo up
ip addr replace 10.10.0.1/31 peer 10.10.0.0/31 dev eth0
ip -6 addr replace fd42:dead:beef:1000::1/127 peer fd42:dead:beef:1000::/127 dev eth0
ip addr replace 10.10.0.3/31 peer 10.10.0.2/31 dev eth1
ip -6 addr replace fd42:dead:beef:1000::3/127 peer fd42:dead:beef:1000::2/127 dev eth1
ip addr replace 10.10.0.5/31 peer 10.10.0.4/31 dev eth2
ip -6 addr replace fd42:dead:beef:1000::5/127 peer fd42:dead:beef:1000::4/127 dev eth2
ip addr replace 10.10.0.10/31 peer 10.10.0.11/31 dev eth3
ip -6 addr replace fd42:dead:beef:1000::a/127 peer fd42:dead:beef:1000::b/127 dev eth3
ip addr replace 10.19.0.6/32 dev eth4
ip -6 addr replace fd42:dead:beef:1900::6/128 dev eth4
ip addr replace 10.19.0.6/32 dev lo
ip -6 addr replace fd42:dead:beef:1900::6/128 dev lo
ip route replace 10.19.0.1/32 via 10.10.0.0 dev eth0 onlink
ip route replace 10.20.15.0/24 via 10.10.0.0 dev eth0 onlink
ip -6 route replace fd42:dead:beef:15::/64 via fd42:dead:beef:1000:0:0:0:0 dev eth0 onlink
ip -6 route replace fd42:dead:beef:1900::1/128 via fd42:dead:beef:1000:0:0:0:0 dev eth0 onlink
ip route replace 10.19.0.2/32 via 10.10.0.2 dev eth1 onlink
ip route replace 10.20.20.0/24 via 10.10.0.2 dev eth1 onlink
ip -6 route replace fd42:dead:beef:20::/64 via fd42:dead:beef:1000:0:0:0:2 dev eth1 onlink
ip -6 route replace fd42:dead:beef:1900::2/128 via fd42:dead:beef:1000:0:0:0:2 dev eth1 onlink
ip route replace 10.19.0.3/32 via 10.10.0.4 dev eth2 onlink
ip route replace 10.20.10.0/24 via 10.10.0.4 dev eth2 onlink
ip -6 route replace fd42:dead:beef:10::/64 via fd42:dead:beef:1000:0:0:0:4 dev eth2 onlink
ip -6 route replace fd42:dead:beef:1900::3/128 via fd42:dead:beef:1000:0:0:0:4 dev eth2 onlink
ip route replace 10.10.0.6/31 via 10.10.0.11 dev eth3 onlink
ip route replace 10.10.0.8/31 via 10.10.0.11 dev eth3 onlink
ip route replace 10.19.0.4/32 via 10.10.0.11 dev eth3 onlink
ip route replace 10.19.0.5/32 via 10.10.0.11 dev eth3 onlink
ip route replace 10.19.0.7/32 via 10.10.0.11 dev eth3 onlink
ip -6 route replace ::/0 via fd42:dead:beef:1000:0:0:0:b dev eth3 onlink
ip -6 route replace fd42:dead:beef:1000::6/127 via fd42:dead:beef:1000:0:0:0:b dev eth3 onlink
ip -6 route replace fd42:dead:beef:1000::8/127 via fd42:dead:beef:1000:0:0:0:b dev eth3 onlink
ip -6 route replace fd42:dead:beef:1900::4/128 via fd42:dead:beef:1000:0:0:0:b dev eth3 onlink
ip -6 route replace fd42:dead:beef:1900::5/128 via fd42:dead:beef:1000:0:0:0:b dev eth3 onlink
ip -6 route replace fd42:dead:beef:1900::7/128 via fd42:dead:beef:1000:0:0:0:b dev eth3 onlink
ip route replace default via 10.10.0.11 dev eth3 onlink
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
echo '[FW] policy firewall starting'
nft add table inet fw
nft 'add chain inet fw forward { type filter hook forward priority 0 ; policy drop ; }'
nft add rule inet fw forward ct state established,related accept
nft add rule inet fw forward ct state invalid drop
nft add rule inet fw forward iifname "eth1" oifname "eth2" counter drop
nft add rule inet fw forward iifname "eth1" oifname "eth3" counter accept
nft list table inet fw
  '';
in
{
  networking.hostName = "s-router-policy";
  networking.usePredictableInterfaceNames = false;
  boot.kernelParams = [ "net.ifnames=0" "biosdevname=0" ];
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = lib.mkDefault 0;
    "net.ipv4.conf.default.rp_filter" = lib.mkDefault 0;
  };
  environment.systemPackages = with pkgs; [ bash coreutils findutils gnugrep gnused iproute2 nftables procps python3 ] ++ lib.optionals true [ frr ];
  systemd.services."generated-network-s-router-policy" = {
    description = "Generated network bootstrap for s-router-policy";
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
