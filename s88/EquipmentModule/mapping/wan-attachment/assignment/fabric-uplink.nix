{ lib
, hostName
, deploymentHostName
, deploymentHost
, renderHostConfig
, lookup
, wanUplinkName
,
}:

if !lookup.hostHasUplinks then
  null
else if renderHostConfig ? fabricUplink then
  if
    builtins.isString renderHostConfig.fabricUplink
      && builtins.hasAttr renderHostConfig.fabricUplink lookup.uplinksRaw
  then
    renderHostConfig.fabricUplink
  else
    throw ''
      s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has invalid fabricUplink '${
        builtins.toJSON (renderHostConfig.fabricUplink or null)
      }'

      known uplinks:
      ${builtins.toJSON lookup.uplinkNames}
    ''
else if deploymentHost ? fabricUplink then
  if
    builtins.isString deploymentHost.fabricUplink
      && builtins.hasAttr deploymentHost.fabricUplink lookup.uplinksRaw
  then
    deploymentHost.fabricUplink
  else
    throw ''
      s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has invalid fabricUplink '${
        builtins.toJSON (deploymentHost.fabricUplink or null)
      }'

      known uplinks:
      ${builtins.toJSON lookup.uplinkNames}
    ''
else
  let
    candidates = lib.filter (name: name != wanUplinkName && name != "management") lookup.uplinkNames;
  in
  if builtins.length candidates == 1 then builtins.head candidates else null
