{
  lib,
  hostName,
  deploymentHostName,
  deploymentHost,
  renderHostConfig,
  lookup,
}: let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  forceAll = values: builtins.foldl' (acc: value: builtins.seq value acc) true values;

  configuredWanUplinkName =
    if !lookup.hostHasUplinks
    then null
    else if renderHostConfig ? wanUplink
    then
      if
        builtins.isString renderHostConfig.wanUplink
        && builtins.hasAttr renderHostConfig.wanUplink lookup.uplinksRaw
      then renderHostConfig.wanUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has invalid wanUplink '${
            builtins.toJSON (renderHostConfig.wanUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON lookup.uplinkNames}
        ''
    else if deploymentHost ? wanUplink
    then
      if
        builtins.isString deploymentHost.wanUplink
        && builtins.hasAttr deploymentHost.wanUplink lookup.uplinksRaw
      then deploymentHost.wanUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has invalid wanUplink '${
            builtins.toJSON (deploymentHost.wanUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON lookup.uplinkNames}
        ''
    else if builtins.length lookup.uplinkNames == 1
    then builtins.head lookup.uplinkNames
    else null;

  configuredWanGroupToUplink =
    if renderHostConfig ? wanGroupToUplink
    then
      if builtins.isAttrs renderHostConfig.wanGroupToUplink
      then renderHostConfig.wanGroupToUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has non-attr wanGroupToUplink

          render host config:
          ${builtins.toJSON renderHostConfig}
        ''
    else if deploymentHost ? wanGroupToUplink
    then
      if builtins.isAttrs deploymentHost.wanGroupToUplink
      then deploymentHost.wanGroupToUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has non-attr wanGroupToUplink

          deployment host:
          ${builtins.toJSON deploymentHost}
        ''
    else {};

  _validateConfiguredWanGroupToUplink = forceAll (
    map
    (
      wanGroupName: let
        uplinkName = configuredWanGroupToUplink.${wanGroupName};
      in
        if !builtins.isString uplinkName
        then
          throw ''
            s88/EquipmentModule/mapping/wan-attachment.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' must map to a string uplink name
          ''
        else if !builtins.hasAttr uplinkName lookup.uplinksRaw
        then
          throw ''
            s88/EquipmentModule/mapping/wan-attachment.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' references unknown uplink '${uplinkName}'

            known uplinks:
            ${builtins.toJSON lookup.uplinkNames}
          ''
        else true
    )
    (sortedAttrNames configuredWanGroupToUplink)
  );

  candidateWanGroupToUplink = let
    candidateUplinkNamesForWanGroup =
      lookup.candidateUplinkNamesForWanGroup or (_wanGroupName: []);
  in
    builtins.listToAttrs (
      lib.filter (entry: entry.value != null) (
        map
        (
          wanGroupName: let
            candidates = candidateUplinkNamesForWanGroup wanGroupName;
          in {
            name = wanGroupName;
            value =
              if builtins.length candidates == 1
              then builtins.head candidates
              else null;
          }
        )
        lookup.wanGroupNames
      )
    );

  wanGroupToUplinkName = builtins.seq _validateConfiguredWanGroupToUplink (
    if configuredWanGroupToUplink != {}
    then configuredWanGroupToUplink
    else if configuredWanUplinkName != null
    then
      candidateWanGroupToUplink
      // builtins.listToAttrs
      (
        map
        (wanGroupName: {
          name = wanGroupName;
          value =
            if builtins.hasAttr wanGroupName candidateWanGroupToUplink
            then candidateWanGroupToUplink.${wanGroupName}
            else configuredWanUplinkName;
        })
        lookup.wanGroupNames
      )
    else candidateWanGroupToUplink
  );

  candidateUplinkNameForTarget = target: let
    candidates = lookup.candidateUplinkNamesForTarget target;
  in
    if builtins.length candidates == 1
    then builtins.head candidates
    else null;

  assignedUplinkNameForTarget = target: let
    targetCandidate = candidateUplinkNameForTarget target;
    wanGroupName = lookup.wanGroupNameForTarget target;
  in
    if targetCandidate != null
    then targetCandidate
    else if wanGroupName != null && builtins.hasAttr wanGroupName wanGroupToUplinkName
    then wanGroupToUplinkName.${wanGroupName}
    else null;

  wanAttachTargets = lib.concatMap lookup.wanTargetsForGroup lookup.wanGroupNames;

  missingWanTargetAssignments =
    lib.filter
    (
      target: assignedUplinkNameForTarget target == null
    )
    wanAttachTargets;

  missingWanGroupAssignments =
    lib.filter
    (
      wanGroupName: !builtins.hasAttr wanGroupName wanGroupToUplinkName
    )
    lookup.wanGroupNames;

  validateStrictWanRendering =
    if !lookup.hostHasUplinks || wanAttachTargets == [] || missingWanTargetAssignments == []
    then true
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: strict rendering requires explicit WAN uplink assignment for host '${hostName}'

        missing WAN attach targets:
        ${builtins.toJSON missingWanTargetAssignments}

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

  fabricUplinkName = import ./assignment/fabric-uplink.nix {
    inherit
      lib
      hostName
      deploymentHostName
      deploymentHost
      renderHostConfig
      lookup
      wanUplinkName
      ;
  };
in {
  inherit
    configuredWanUplinkName
    wanGroupToUplinkName
    assignedUplinkNameForTarget
    missingWanTargetAssignments
    missingWanGroupAssignments
    validateStrictWanRendering
    wanUplinkName
    fabricUplinkName
    ;
}
