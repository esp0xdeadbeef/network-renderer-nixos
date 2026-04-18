{ lib, ... }:

{
  boot.isContainer = true;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = lib.mkForce false;

  services.resolved.enable = lib.mkForce false;
  networking.firewall.enable = lib.mkForce false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  system.stateVersion = "25.11";
}
