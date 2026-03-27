# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/container-router-access/node-from-topology.nix
# FILE: container-router-access/node-from-topology.nix
{ ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # the new-style services (kea + dns + ra) are imported by container-settings.nix
}
