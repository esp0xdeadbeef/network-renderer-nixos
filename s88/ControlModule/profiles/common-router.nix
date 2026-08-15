{
  lib,
  pkgs,
  config,
  ...
}:

let
  debugTools = import ../debug-tools.nix { inherit pkgs; };
in

{
  boot.isContainer = true;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkDefault false;
  networking.useHostResolvConf = lib.mkForce false;

  services.resolved.enable = lib.mkIf (
    !(config.services.network-renderer-wireguard.providerRuntime.enable or false)
  ) (lib.mkForce false);
  networking.firewall.enable = lib.mkForce false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  system.stateVersion = "25.11";

  environment.systemPackages = debugTools;
}
