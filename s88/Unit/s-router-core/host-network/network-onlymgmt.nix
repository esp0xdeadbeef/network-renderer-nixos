{
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    dhcpcd
  ];

  networking.useNetworkd = true;
  networking.networkmanager.enable = false;

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
