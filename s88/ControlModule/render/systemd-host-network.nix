{ lib, hostPlan }:

let
  hostNaming = import ../../../lib/host-naming.nix { inherit lib; };
  common = import ./systemd-host-network/common.nix { inherit lib hostPlan hostNaming; };

  local = import ./systemd-host-network/local-bridges.nix {
    inherit lib common;
  };

  vlans = import ./systemd-host-network/bridge-network-vlans.nix {
    inherit lib common;
  };

  uplinks = import ./systemd-host-network/uplinks.nix {
    inherit lib common vlans;
  };

  transit = import ./systemd-host-network/transit.nix {
    inherit lib common;
  };

  bridgeNetdevs =
    if common.hostHasUplinks then
      local.localBridgeNetdevs // uplinks.uplinkBridgeNetdevs // vlans.bridgeNetworkVlanNetdevs // transit.transitNetdevs
    else
      local.localBridgeNetdevs // vlans.bridgeNetworkVlanNetdevs;

  bridgeNetworksRendered =
    if common.hostHasUplinks then
      local.localBridgeNetworks // uplinks.uplinkBridgeAttachmentNetworks // uplinks.uplinkBridgeNetworks // transit.transitNetworks
    else
      local.localBridgeNetworks;

  hostNetdevs = { };
  hostNetworks = if common.hostHasUplinks || vlans.bridgeNetworkVlanNames != [ ] then uplinks.uplinkParentNetworks else { };
in
{
  inherit bridgeNetdevs hostNetdevs hostNetworks;

  netdevs = hostNetdevs // bridgeNetdevs;
  networks = hostNetworks // bridgeNetworksRendered;
  bridgeNetworks = bridgeNetworksRendered;
}
