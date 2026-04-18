{ lib }:
{
  boxName,
  deploymentHostDef,
}:
let
  transitBridges =
    if builtins.isAttrs deploymentHostDef && deploymentHostDef ? transitBridges then
      deploymentHostDef.transitBridges
    else
      { };

  uplinks =
    if builtins.isAttrs deploymentHostDef && deploymentHostDef ? uplinks then
      deploymentHostDef.uplinks
    else
      { };

  transitVlanInterfaceNameFor = name: "vt-${name}";

  mapBridge =
    name: bridgeDef:
    let
      bridgeName =
        if builtins.isAttrs bridgeDef && bridgeDef ? name && builtins.isString bridgeDef.name then
          bridgeDef.name
        else
          name;

      parentUplinkName =
        if
          builtins.isAttrs bridgeDef && bridgeDef ? parentUplink && builtins.isString bridgeDef.parentUplink
        then
          bridgeDef.parentUplink
        else
          throw "network-renderer-nixos: transit bridge '${name}' on host '${boxName}' is missing parentUplink";

      parentUplink =
        if builtins.hasAttr parentUplinkName uplinks then
          uplinks.${parentUplinkName}
        else
          throw "network-renderer-nixos: transit bridge '${name}' on host '${boxName}' references unknown uplink '${parentUplinkName}'";

      parentBridgeName =
        if
          builtins.isAttrs parentUplink && parentUplink ? bridge && builtins.isString parentUplink.bridge
        then
          parentUplink.bridge
        else
          throw "network-renderer-nixos: transit bridge '${name}' on host '${boxName}' requires parent uplink '${parentUplinkName}' to expose a bridge";

      vlanId =
        if builtins.isAttrs bridgeDef && bridgeDef ? vlan then
          bridgeDef.vlan
        else
          throw "network-renderer-nixos: transit bridge '${name}' on host '${boxName}' is missing vlan";
    in
    {
      inherit
        name
        bridgeName
        parentUplinkName
        parentBridgeName
        vlanId
        ;
      vlanInterfaceName = transitVlanInterfaceNameFor name;
    };

  bridgeModels = lib.mapAttrs mapBridge transitBridges;
in
{
  bridgeNameMap = lib.mapAttrs (_: bridgeModel: bridgeModel.bridgeName) bridgeModels;
  bridges = bridgeModels;
  debug = {
    hostName = boxName;
    bridges = builtins.attrNames bridgeModels;
  };
}
