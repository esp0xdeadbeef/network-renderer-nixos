{
  lib,
  boxContext,
  globalInventory,
  ...
}:

let
  rendered = import ../../s-router-policy-only/lib/renderer/render-host-network.nix {
    inherit lib;
    inventory = globalInventory;
    hostName = boxContext.deploymentHostName;
  };
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = rendered.netdevs;
  systemd.network.networks = rendered.networks;
}
