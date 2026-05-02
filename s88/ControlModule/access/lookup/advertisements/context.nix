{ containerModel }:

let
  roleName = containerModel.roleName or null;
  roleConfig =
    if containerModel ? roleConfig && builtins.isAttrs containerModel.roleConfig then
      containerModel.roleConfig
    else
      { };
  containerRoleConfig =
    if roleConfig ? container && builtins.isAttrs roleConfig.container then roleConfig.container else { };
  advertiseDefaults =
    if containerRoleConfig ? advertise && builtins.isAttrs containerRoleConfig.advertise then
      containerRoleConfig.advertise
    else
      { };
  currentSite =
    if containerModel ? site && builtins.isAttrs containerModel.site then containerModel.site else { };
  currentInventorySite =
    if containerModel ? inventorySite && builtins.isAttrs containerModel.inventorySite then
      containerModel.inventorySite
    else
      { };
in
rec {
  inherit roleName;

  containerDisplayName = containerModel.containerName or (containerModel.unitName or "<unknown>");

  defaultDhcp4Advertise =
    if advertiseDefaults ? dhcp4 && builtins.isBool advertiseDefaults.dhcp4 then
      advertiseDefaults.dhcp4
    else
      roleName == "access";

  defaultRadvdAdvertise =
    if advertiseDefaults ? radvd && builtins.isBool advertiseDefaults.radvd then
      advertiseDefaults.radvd
    else
      roleName == "access";

  containerInterfaces =
    if containerModel ? interfaces && builtins.isAttrs containerModel.interfaces then
      containerModel.interfaces
    else
      { };

  runtimeTarget =
    if containerModel ? runtimeTarget && builtins.isAttrs containerModel.runtimeTarget then
      containerModel.runtimeTarget
    else
      { };

  runtimeInterfaces =
    if runtimeTarget ? interfaces && builtins.isAttrs runtimeTarget.interfaces then
      runtimeTarget.interfaces
    else
      { };

  currentSiteIpv6 = if currentSite ? ipv6 && builtins.isAttrs currentSite.ipv6 then currentSite.ipv6 else { };

  currentInventorySiteIpv6 =
    if currentInventorySite ? ipv6 && builtins.isAttrs currentInventorySite.ipv6 then
      currentInventorySite.ipv6
    else
      { };
}
