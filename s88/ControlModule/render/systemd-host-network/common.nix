{ lib, hostPlan, hostNaming }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);
in
rec {
  inherit sortedAttrNames hostNaming;

  deploymentHost = hostPlan.deploymentHost or { };
  bridges = hostPlan.bridges or { };
  uplinks = hostPlan.uplinks or { };
  transitBridges = hostPlan.transitBridges or { };
  hostHasUplinks = hostPlan.hostHasUplinks or false;

  bridgeNetworks =
    if deploymentHost ? bridgeNetworks && builtins.isAttrs deploymentHost.bridgeNetworks then
      deploymentHost.bridgeNetworks
    else
      { };

  uplinkNames = sortedAttrNames uplinks;
  transitNames = sortedAttrNames transitBridges;

  transitNameRendered =
    transitName:
    let
      transit = transitBridges.${transitName};
    in
    if transit ? name && builtins.isString transit.name then transit.name else hostNaming.shorten transitName;

  transitNamesForUplink =
    uplinkName:
    lib.filter (
      transitName:
      let transit = transitBridges.${transitName};
      in (transit.parentUplink or null) == uplinkName
    ) transitNames;

  vlanIfNameFor =
    uplinkName:
    let uplink = uplinks.${uplinkName};
    in if (uplink.mode or "") == "vlan" then "${uplink.parent}.${toString uplink.vlan}" else null;
}
