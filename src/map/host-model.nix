{ lib }:
{
  boxName,
  deploymentHostDef,
}:
let
  uplinks =
    if builtins.isAttrs deploymentHostDef && deploymentHostDef ? uplinks then
      deploymentHostDef.uplinks
    else
      { };

  bridgeNetworks =
    if builtins.isAttrs deploymentHostDef && deploymentHostDef ? bridgeNetworks then
      deploymentHostDef.bridgeNetworks
    else
      { };

  vlanInterfaceNameFor =
    parent: vlanId:
    if builtins.isString parent && parent != "" && builtins.isInt vlanId then
      "${parent}.${toString vlanId}"
    else
      throw "network-renderer-nixos: deployment host '${boxName}' VLAN uplink requires string parent and integer vlan id";

  mapUplink =
    name: uplink:
    let
      parent =
        if builtins.isAttrs uplink && uplink ? parent && builtins.isString uplink.parent then
          uplink.parent
        else
          throw "network-renderer-nixos: deployment host '${boxName}' uplink '${name}' is missing parent";

      bridgeName =
        if builtins.isAttrs uplink && uplink ? bridge && builtins.isString uplink.bridge then
          uplink.bridge
        else
          throw "network-renderer-nixos: deployment host '${boxName}' uplink '${name}' is missing bridge";

      mode =
        if builtins.isAttrs uplink && uplink ? mode && builtins.isString uplink.mode then
          uplink.mode
        else
          "bridge";
    in
    if mode == "vlan" then
      let
        vlanId =
          if uplink ? vlan && builtins.isInt uplink.vlan then
            uplink.vlan
          else
            throw "network-renderer-nixos: deployment host '${boxName}' uplink '${name}' is missing vlan";
      in
      {
        inherit
          name
          parent
          bridgeName
          mode
          vlanId
          ;
        kind = "vlan-bridge";
        vlanInterfaceName = vlanInterfaceNameFor parent vlanId;
        networkOptions = bridgeNetworks.${bridgeName} or { };
      }
    else
      {
        inherit
          name
          parent
          bridgeName
          mode
          ;
        kind = "bridge";
        networkOptions = bridgeNetworks.${bridgeName} or { };
      };

  uplinkModels = lib.mapAttrs mapUplink uplinks;
in
{
  hostName = boxName;
  deploymentHostName = boxName;
  wanUplink = deploymentHostDef.wanUplink or null;
  uplinks = uplinkModels;
  debug = {
    hostName = boxName;
    uplinks = builtins.attrNames uplinkModels;
    bridgeNetworks = builtins.attrNames bridgeNetworks;
  };
}
