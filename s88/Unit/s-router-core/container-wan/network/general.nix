{ lib, pkgs, ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.services.systemd-networkd.enable = true;
  #networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;

  services.resolved.enable = true;

  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
