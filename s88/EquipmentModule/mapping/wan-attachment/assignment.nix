{
  lib,
  hostName,
  deploymentHostName,
  deploymentHost,
  renderHostConfig,
  lookup,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  forceAll = values: builtins.foldl' (acc: value: builtins.seq value acc) true values;

  configuredWanUplinkName =
    if !lookup.hostHasUplinks then
      null
    else if renderHostConfig ? wanUplink then
      if
        builtins.isString renderHostConfig.wanUplink
        && builtins.hasAttr renderHostConfig.wanUplink lookup.uplinksRaw
      then
        renderHostConfig.wanUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has invalid wanUplink '${
            builtins.toJSON (renderHostConfig.wanUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON lookup.uplinkNames}
        ''
    else if deploymentHost ? wanUplink then
      if
        builtins.isString deploymentHost.wanUplink
        && builtins.hasAttr deploymentHost.wanUplink lookup.uplinksRaw
      then
        deploymentHost.wanUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has invalid wanUplink '${
            builtins.toJSON (deploymentHost.wanUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON lookup.uplinkNames}
        ''
    else if builtins.length lookup.uplinkNames == 1 then
      builtins.head lookup.uplinkNames
    else
      null;

  configuredWanGroupToUplink =
    if renderHostConfig ? wanGroupToUplink then
      if builtins.isAttrs renderHostConfig.wanGroupToUplink then
        renderHostConfig.wanGroupToUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has non-attr wanGroupToUplink

          render host config:
          ${builtins.toJSON renderHostConfig}
        ''
    else if deploymentHost ? wanGroupToUplink then
      if builtins.isAttrs deploymentHost.wanGroupToUplink then
        deploymentHost.wanGroupToUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has non-attr wanGroupToUplink

          deployment host:
          ${builtins.toJSON deploymentHost}
        ''
    else
      { };

  _validateConfiguredWanGroupToUplink = forceAll (
    map (
      wanGroupName:
      let
        uplinkName = configuredWanGroupToUplink.${wanGroupName};
      in
      if !builtins.isString uplinkName then
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' must map to a string uplink name
        ''
      else if !builtins.hasAttr uplinkName lookup.uplinksRaw then
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' references unknown uplink '${uplinkName}'

          known uplinks:
          ${builtins.toJSON lookup.uplinkNames}
        ''
      else
        true
    ) (sortedAttrNames configuredWanGroupToUplink)
  );

  autoMatchedWanGroups = builtins.listToAttrs (
    lib.concatMap (
      wanGroupName:
      let
        candidates = lookup.candidateUplinkNamesForWanGroup wanGroupName;
      in
      if builtins.length candidates == 1 then
        [
          {
            name = wanGroupName;
            value = builtins.head candidates;
          }
        ]
      else
        [ ]
    ) lookup.wanGroupNames
  );

  autoMatchedUplinkNames = lib.unique (builtins.attrValues autoMatchedWanGroups);

  remainingWanGroupsForAuto = lib.filter (
    wanGroupName: !builtins.hasAttr wanGroupName autoMatchedWanGroups
  ) lookup.wanGroupNames;

  remainingUplinkNamesForAuto = lib.filter (
    uplinkName: !(builtins.elem uplinkName autoMatchedUplinkNames)
  ) lookup.uplinkNames;

  zippedWanGroupToUplink =
    let
      count = builtins.length remainingWanGroupsForAuto;
    in
    if count == 0 then
      { }
    else if count == builtins.length remainingUplinkNamesForAuto then
      builtins.listToAttrs (
        builtins.genList (idx: {
          name = builtins.elemAt remainingWanGroupsForAuto idx;
          value = builtins.elemAt remainingUplinkNamesForAuto idx;
        }) count
      )
    else
      { };

  autoWanGroupToUplink = autoMatchedWanGroups // zippedWanGroupToUplink;

  wanGroupToUplinkName = builtins.seq _validateConfiguredWanGroupToUplink (
    if configuredWanGroupToUplink != { } then
      configuredWanGroupToUplink
    else if configuredWanUplinkName != null then
      builtins.listToAttrs (
        map (wanGroupName: {
          name = wanGroupName;
          value = configuredWanUplinkName;
        }) lookup.wanGroupNames
      )
    else
      autoWanGroupToUplink
  );

  missingWanGroupAssignments = lib.filter (
    wanGroupName: !builtins.hasAttr wanGroupName wanGroupToUplinkName
  ) lookup.wanGroupNames;

  validateStrictWanRendering =
    if !lookup.hostHasUplinks || lookup.wanGroupNames == [ ] || missingWanGroupAssignments == [ ] then
      true
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: strict rendering requires explicit WAN uplink assignment for host '${hostName}'

        missing wan groups:
        ${builtins.toJSON missingWanGroupAssignments}

        known uplinks:
        ${builtins.toJSON lookup.uplinkNames}

        set either:
        render.hosts.${hostName}.wanUplink
        or:
        render.hosts.${hostName}.wanGroupToUplink
        or:
        deployment.hosts.${deploymentHostName}.wanUplink
        or:
        deployment.hosts.${deploymentHostName}.wanGroupToUplink
      '';

  wanUplinkName = configuredWanUplinkName;

  fabricUplinkName =
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
      if builtins.length candidates == 1 then builtins.head candidates else null;
in
{
  inherit
    configuredWanUplinkName
    wanGroupToUplinkName
    missingWanGroupAssignments
    validateStrictWanRendering
    wanUplinkName
    fabricUplinkName
    ;
}
