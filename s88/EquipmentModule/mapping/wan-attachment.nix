{
  lib,
  hostName,
  deploymentHostName,
  deploymentHost,
  renderHostConfig,
  cpm,
  inventory ? { },
  attachTargetsBase,
}:

let
  runtimeContext = import ../../Unit/lookup/runtime-context.nix { inherit lib; };
  hostNaming = import ../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  forceAll = values: builtins.foldl' (acc: value: builtins.seq value acc) true values;

  sourceKindForTarget =
    target:
    if
      target ? connectivity
      && builtins.isAttrs target.connectivity
      && target.connectivity ? sourceKind
      && builtins.isString target.connectivity.sourceKind
    then
      target.connectivity.sourceKind
    else
      null;

  logicalNodeIdentityForTarget =
    target:
    runtimeContext.logicalNodeIdentityForUnit {
      inherit cpm inventory;
      unitName = target.unitName;
      file = "s88/EquipmentModule/mapping/wan-attachment.nix";
    };

  wanGroupNameForTarget =
    target: if sourceKindForTarget target == "wan" then logicalNodeIdentityForTarget target else null;

  uplinksRaw =
    if !(deploymentHost ? uplinks) then
      { }
    else if builtins.isAttrs deploymentHost.uplinks then
      deploymentHost.uplinks
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has non-attr uplinks

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';

  hostHasUplinks = uplinksRaw != { };

  uplinkNames = sortedAttrNames uplinksRaw;

  uplinkBridgeNamesRaw = lib.unique (
    lib.filter builtins.isString (map (uplinkName: uplinksRaw.${uplinkName}.bridge or null) uplinkNames)
  );

  uplinkBridgeNameMap = hostNaming.ensureUnique uplinkBridgeNamesRaw;

  wanGroupNames = lib.sort builtins.lessThan (
    lib.unique (lib.filter builtins.isString (map wanGroupNameForTarget attachTargetsBase))
  );

  configuredWanUplinkName =
    if !hostHasUplinks then
      null
    else if renderHostConfig ? wanUplink then
      if
        builtins.isString renderHostConfig.wanUplink
        && builtins.hasAttr renderHostConfig.wanUplink uplinksRaw
      then
        renderHostConfig.wanUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has invalid wanUplink '${
            builtins.toJSON (renderHostConfig.wanUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON uplinkNames}
        ''
    else if deploymentHost ? wanUplink then
      if
        builtins.isString deploymentHost.wanUplink && builtins.hasAttr deploymentHost.wanUplink uplinksRaw
      then
        deploymentHost.wanUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has invalid wanUplink '${
            builtins.toJSON (deploymentHost.wanUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON uplinkNames}
        ''
    else if builtins.length uplinkNames == 1 then
      builtins.head uplinkNames
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
      else if !builtins.hasAttr uplinkName uplinksRaw then
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' references unknown uplink '${uplinkName}'

          known uplinks:
          ${builtins.toJSON uplinkNames}
        ''
      else
        true
    ) (sortedAttrNames configuredWanGroupToUplink)
  );

  wanTargetsForGroup =
    wanGroupName: lib.filter (target: wanGroupNameForTarget target == wanGroupName) attachTargetsBase;

  upstreamNamesForWanGroup =
    wanGroupName:
    let
      upstreamNames = lib.unique (
        lib.filter builtins.isString (
          map (target: target.connectivity.upstream or null) (wanTargetsForGroup wanGroupName)
        )
      );
    in
    if builtins.length upstreamNames <= 1 then
      upstreamNames
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: WAN group '${wanGroupName}' resolved to multiple upstream identities on host '${hostName}'

        upstream names:
        ${builtins.toJSON upstreamNames}

        targets:
        ${builtins.toJSON (wanTargetsForGroup wanGroupName)}
      '';

  uplinkMatchKeys =
    uplinkName:
    let
      uplink = uplinksRaw.${uplinkName};
    in
    lib.unique (
      lib.filter builtins.isString [
        uplinkName
        (uplink.name or null)
        (uplink.uplink or null)
        (uplink.upstream or null)
        (uplink.external or null)
        (uplink.provider or null)
        (uplink.bridge or null)
      ]
    );

  candidateUplinkNamesForWanGroup =
    wanGroupName:
    let
      groupKeys = lib.unique (
        lib.filter builtins.isString ([ wanGroupName ] ++ (upstreamNamesForWanGroup wanGroupName))
      );
    in
    lib.filter (
      uplinkName:
      let
        keys = uplinkMatchKeys uplinkName;
      in
      lib.any (key: builtins.elem key keys) groupKeys
    ) uplinkNames;

  autoMatchedWanGroups = builtins.listToAttrs (
    lib.concatMap (
      wanGroupName:
      let
        candidates = candidateUplinkNamesForWanGroup wanGroupName;
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
    ) wanGroupNames
  );

  autoMatchedUplinkNames = lib.unique (builtins.attrValues autoMatchedWanGroups);

  remainingWanGroupsForAuto = lib.filter (
    wanGroupName: !builtins.hasAttr wanGroupName autoMatchedWanGroups
  ) wanGroupNames;

  remainingUplinkNamesForAuto = lib.filter (
    uplinkName: !(builtins.elem uplinkName autoMatchedUplinkNames)
  ) uplinkNames;

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
        }) wanGroupNames
      )
    else
      autoWanGroupToUplink
  );

  missingWanGroupAssignments = lib.filter (
    wanGroupName: !builtins.hasAttr wanGroupName wanGroupToUplinkName
  ) wanGroupNames;

  _validateStrictWanRendering =
    if !hostHasUplinks || wanGroupNames == [ ] || missingWanGroupAssignments == [ ] then
      true
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: strict rendering requires explicit WAN uplink assignment for host '${hostName}'

        missing wan groups:
        ${builtins.toJSON missingWanGroupAssignments}

        known uplinks:
        ${builtins.toJSON uplinkNames}

        set either:
        render.hosts.${hostName}.wanUplink
        or:
        render.hosts.${hostName}.wanGroupToUplink
        or:
        deployment.hosts.${deploymentHostName}.wanUplink
        or:
        deployment.hosts.${deploymentHostName}.wanGroupToUplink
      '';

  renderedHostBridgeNameForWanGroup =
    wanGroupName:
    let
      uplinkName = wanGroupToUplinkName.${wanGroupName};
      uplink = uplinksRaw.${uplinkName};

      originalBridge =
        if uplink ? bridge && builtins.isString uplink.bridge then
          uplink.bridge
        else
          throw ''
            s88/EquipmentModule/mapping/wan-attachment.nix: uplink '${uplinkName}' assigned to WAN group '${wanGroupName}' is missing bridge

            uplink:
            ${builtins.toJSON uplink}
          '';
    in
    uplinkBridgeNameMap.${originalBridge};

  attachTargets = builtins.seq _validateStrictWanRendering (
    map (
      target:
      let
        wanGroupName = wanGroupNameForTarget target;

        assignedUplinkName =
          if wanGroupName != null && builtins.hasAttr wanGroupName wanGroupToUplinkName then
            wanGroupToUplinkName.${wanGroupName}
          else
            null;
      in
      target
      // {
        inherit assignedUplinkName;
        renderedHostBridgeName =
          if assignedUplinkName != null then
            renderedHostBridgeNameForWanGroup wanGroupName
          else
            target.baseRenderedHostBridgeName;
      }
    ) attachTargetsBase
  );

  localAttachTargets = attachTargets;

  maybePreferredAttachTarget =
    predicate:
    let
      matches = lib.filter predicate localAttachTargets;
    in
    if builtins.length matches == 1 then builtins.head matches else null;

  wanAttachTarget = maybePreferredAttachTarget (target: sourceKindForTarget target == "wan");

  fabricAttachTarget = maybePreferredAttachTarget (target: sourceKindForTarget target == "p2p");

  renderedHostBridgeNameForAssignedUplink =
    uplinkName:
    let
      matches = lib.filter (target: (target.assignedUplinkName or null) == uplinkName) localAttachTargets;

      renderedNames = lib.unique (map (target: target.renderedHostBridgeName) matches);
    in
    if renderedNames == [ ] then
      null
    else if builtins.length renderedNames == 1 then
      builtins.head renderedNames
    else
      throw ''
        s88/EquipmentModule/mapping/wan-attachment.nix: uplink '${uplinkName}' resolved to multiple rendered WAN bridges

        matches:
        ${builtins.toJSON matches}
      '';

  wanUplinkName = configuredWanUplinkName;

  fabricUplinkName =
    if !hostHasUplinks then
      null
    else if renderHostConfig ? fabricUplink then
      if
        builtins.isString renderHostConfig.fabricUplink
        && builtins.hasAttr renderHostConfig.fabricUplink uplinksRaw
      then
        renderHostConfig.fabricUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: render host '${hostName}' has invalid fabricUplink '${
            builtins.toJSON (renderHostConfig.fabricUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON uplinkNames}
        ''
    else if deploymentHost ? fabricUplink then
      if
        builtins.isString deploymentHost.fabricUplink
        && builtins.hasAttr deploymentHost.fabricUplink uplinksRaw
      then
        deploymentHost.fabricUplink
      else
        throw ''
          s88/EquipmentModule/mapping/wan-attachment.nix: deployment host '${deploymentHostName}' has invalid fabricUplink '${
            builtins.toJSON (deploymentHost.fabricUplink or null)
          }'

          known uplinks:
          ${builtins.toJSON uplinkNames}
        ''
    else
      let
        candidates = lib.filter (name: name != wanUplinkName && name != "management") uplinkNames;
      in
      if builtins.length candidates == 1 then builtins.head candidates else null;

  uplinks = builtins.mapAttrs (
    uplinkName: uplink:
    let
      originalBridge =
        if uplink ? bridge && builtins.isString uplink.bridge then
          uplink.bridge
        else
          throw ''
            s88/EquipmentModule/mapping/wan-attachment.nix: uplink '${uplinkName}' is missing bridge

            uplink:
            ${builtins.toJSON uplink}
          '';

      assignedWanRenderedBridge = renderedHostBridgeNameForAssignedUplink uplinkName;

      renderedBridge =
        if assignedWanRenderedBridge != null then
          assignedWanRenderedBridge
        else if uplinkName == wanUplinkName && wanAttachTarget != null then
          wanAttachTarget.renderedHostBridgeName
        else if
          fabricUplinkName != null && uplinkName == fabricUplinkName && fabricAttachTarget != null
        then
          fabricAttachTarget.renderedHostBridgeName
        else
          uplinkBridgeNameMap.${originalBridge};
    in
    uplink
    // {
      inherit originalBridge;
      bridge = renderedBridge;
    }
  ) uplinksRaw;
in
{
  inherit
    attachTargets
    localAttachTargets
    uplinks
    hostHasUplinks
    wanUplinkName
    fabricUplinkName
    ;
}
