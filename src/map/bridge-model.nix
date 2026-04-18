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

  transitVlanInterfaceNameFor =
    parentLinkName: vlanId:
    if builtins.isString parentLinkName && parentLinkName != "" && builtins.isInt vlanId then
      "${parentLinkName}.${toString vlanId}"
    else
      throw "network-renderer-nixos: transit bridge on host '${boxName}' requires string parent link and integer vlan id";

  parentLinkNameForUplink =
    parentUplinkName: parentUplink:
    if
      builtins.isAttrs parentUplink
      && parentUplink ? mode
      && builtins.isString parentUplink.mode
      && parentUplink.mode == "vlan"
    then
      if
        parentUplink ? parent
        && builtins.isString parentUplink.parent
        && parentUplink.parent != ""
        && parentUplink ? vlan
        && builtins.isInt parentUplink.vlan
      then
        "${parentUplink.parent}.${toString parentUplink.vlan}"
      else
        throw "network-renderer-nixos: parent uplink '${parentUplinkName}' on host '${boxName}' is missing parent/vlan"
    else if
      builtins.isAttrs parentUplink
      && parentUplink ? parent
      && builtins.isString parentUplink.parent
      && parentUplink.parent != ""
    then
      parentUplink.parent
    else
      throw "network-renderer-nixos: parent uplink '${parentUplinkName}' on host '${boxName}' is missing parent";

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

      vlanId =
        if builtins.isAttrs bridgeDef && bridgeDef ? vlan && builtins.isInt bridgeDef.vlan then
          bridgeDef.vlan
        else
          throw "network-renderer-nixos: transit bridge '${name}' on host '${boxName}' is missing vlan";

      parentLinkName = parentLinkNameForUplink parentUplinkName parentUplink;
    in
    {
      inherit
        name
        bridgeName
        parentUplinkName
        vlanId
        parentLinkName
        ;
      vlanInterfaceName = transitVlanInterfaceNameFor parentLinkName vlanId;
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
