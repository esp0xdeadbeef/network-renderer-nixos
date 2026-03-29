{
  lib,
  hostName,
  cpm,
  inventory ? { },
}:

let
  hostNaming = import ./host-naming.nix { inherit lib; };
  hostQuery = import ./host-query.nix { inherit lib; };
  runtimeContext = import ./runtime-context.nix { inherit lib; };
  cpmAdapter = import ./cpm-runtime-adapter.nix { inherit lib; };
  roles = import ./s88-role-registry.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  forceAll = values: builtins.foldl' (acc: value: builtins.seq value acc) true values;

  resolvedHostContext =
    if inventory != { } then
      hostQuery.hostContextForHost {
        inherit inventory;
        hostname = hostName;
        file = "lib/render-host-network.nix";
      }
    else
      rec {
        hostname = hostName;
        renderHosts = { };
        renderHostConfig = { };
        deploymentHosts = { };
        deploymentHostNames = [ hostName ];
        realizationNodes = { };
        deploymentHostName = hostName;
        deploymentHost = { };
        realizationNode = null;
      };

  deploymentHostName =
    if
      resolvedHostContext ? deploymentHostName && builtins.isString resolvedHostContext.deploymentHostName
    then
      resolvedHostContext.deploymentHostName
    else
      hostName;

  deploymentHost =
    if resolvedHostContext ? deploymentHost && builtins.isAttrs resolvedHostContext.deploymentHost then
      resolvedHostContext.deploymentHost
    else
      { };

  renderHostConfig =
    if
      resolvedHostContext ? renderHostConfig && builtins.isAttrs resolvedHostContext.renderHostConfig
    then
      resolvedHostContext.renderHostConfig
    else
      { };

  realizationNodes =
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  normalizedRuntimeTargets = cpmAdapter.normalizedRuntimeTargets {
    inherit cpm;
    file = "lib/render-host-network.nix";
  };

  allUnitNames = sortedAttrNames normalizedRuntimeTargets;

  logicalNodeForUnit =
    unitName:
    let
      target = normalizedRuntimeTargets.${unitName};
    in
    if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  logicalNodeNameForUnit =
    unitName:
    let
      logicalNode = logicalNodeForUnit unitName;
    in
    if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else unitName;

  logicalNodeIdentityForUnit =
    unitName:
    let
      logicalNode = logicalNodeForUnit unitName;

      segments = lib.filter builtins.isString [
        (logicalNode.enterprise or null)
        (logicalNode.site or null)
        (logicalNode.name or null)
      ];
    in
    if segments != [ ] then builtins.concatStringsSep "::" segments else unitName;

  placementHostForUnit =
    unitName:
    let
      target = normalizedRuntimeTargets.${unitName};
    in
    if
      target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? host
      && builtins.isString target.placement.host
    then
      target.placement.host
    else
      null;

  realizationHostForUnit =
    unitName:
    if
      builtins.hasAttr unitName realizationNodes
      && builtins.isAttrs realizationNodes.${unitName}
      && realizationNodes.${unitName} ? host
      && builtins.isString realizationNodes.${unitName}.host
    then
      realizationNodes.${unitName}.host
    else
      null;

  unitBelongsToMachine =
    unitName:
    let
      logicalNodeName = logicalNodeNameForUnit unitName;
      placementHost = placementHostForUnit unitName;
      realizationHost = realizationHostForUnit unitName;
    in
    logicalNodeName == hostName
    || lib.hasPrefix "${hostName}-" logicalNodeName
    || placementHost == deploymentHostName
    || realizationHost == deploymentHostName;

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    inherit cpm inventory;
    deploymentHostName = deploymentHostName;
    file = "lib/render-host-network.nix";
  };

  selectedUnitsBase = lib.unique (
    unitsOnDeploymentHost ++ lib.filter unitBelongsToMachine allUnitNames
  );

  interfacesForUnit =
    unitName:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}.interfaces or { }
    else
      { };

  localAttachBridgeNames = lib.unique (
    lib.concatMap (
      unitName:
      let
        interfaces = interfacesForUnit unitName;
      in
      map (
        ifName:
        let
          iface = interfaces.${ifName};
        in
        if iface ? hostBridge && builtins.isString iface.hostBridge then
          iface.hostBridge
        else
          throw ''
            lib/render-host-network.nix: interface '${ifName}' for unit '${unitName}' is missing normalized hostBridge
          ''
      ) (sortedAttrNames interfaces)
    ) selectedUnitsBase
  );

  bridgeNamesRaw = lib.sort builtins.lessThan (lib.unique localAttachBridgeNames);

  bridgeNameMap = hostNaming.ensureUnique bridgeNamesRaw;

  bridgeNames = map (bridgeName: bridgeNameMap.${bridgeName}) bridgeNamesRaw;

  bridges = builtins.listToAttrs (
    map (bridgeName: {
      name = bridgeName;
      value = {
        originalName = bridgeName;
        renderedName = bridgeNameMap.${bridgeName};
      };
    }) bridgeNamesRaw
  );

  localBridgeNetdevs = builtins.listToAttrs (
    map (renderedBridgeName: {
      name = "10-${renderedBridgeName}";
      value = {
        netdevConfig = {
          Name = renderedBridgeName;
          Kind = "bridge";
        };
      };
    }) bridgeNames
  );

  localBridgeNetworks = builtins.listToAttrs (
    map (renderedBridgeName: {
      name = "30-${renderedBridgeName}";
      value = {
        matchConfig.Name = renderedBridgeName;
        networkConfig = {
          ConfigureWithoutCarrier = true;
        };
      };
    }) bridgeNames
  );

  runtimeRole =
    if renderHostConfig ? runtimeRole && builtins.isString renderHostConfig.runtimeRole then
      renderHostConfig.runtimeRole
    else
      null;

  selectedUnits = lib.filter (
    unitName:
    runtimeRole == null
    ||
      runtimeContext.roleForUnit {
        cpm = cpm;
        inventory = inventory;
        inherit unitName;
        file = "lib/render-host-network.nix";
      } == runtimeRole
  ) selectedUnitsBase;

  _selectedUnitsNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        lib/render-host-network.nix: no units matched deployment host '${deploymentHostName}'${
          if runtimeRole != null then " for runtimeRole '${runtimeRole}'" else ""
        }

        requested host:
        ${hostName}

        units on deployment host:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ unitsOnDeploymentHost)}

        available runtime targets:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ allUnitNames)}
      '';

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

  attachTargetsBase = lib.concatMap (
    unitName:
    let
      interfaces = interfacesForUnit unitName;
    in
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        hostBridgeName = iface.hostBridge;
      in
      {
        inherit unitName ifName hostBridgeName;
        baseRenderedHostBridgeName = bridgeNameMap.${hostBridgeName};
        renderedIfName = iface.renderedIfName or null;
        addresses = iface.addresses or [ ];
        routes = iface.routes or [ ];
        connectivity = iface.connectivity or { };
        interface = iface;
      }
    ) (sortedAttrNames interfaces)
  ) selectedUnitsBase;

  localAttachTargetsBase = lib.filter (
    target: builtins.elem (target.unitName or "") selectedUnits
  ) attachTargetsBase;

  logicalNodeNameForTarget = target: logicalNodeNameForUnit target.unitName;
  logicalNodeIdentityForTarget = target: logicalNodeIdentityForUnit target.unitName;

  wanGroupNameForTarget =
    target: if sourceKindForTarget target == "wan" then logicalNodeIdentityForTarget target else null;

  uplinksRaw =
    if !(deploymentHost ? uplinks) then
      { }
    else if builtins.isAttrs deploymentHost.uplinks then
      deploymentHost.uplinks
    else
      throw ''
        lib/render-host-network.nix: deployment host '${deploymentHostName}' has non-attr uplinks

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';

  hostHasUplinks = uplinksRaw != { };

  uplinkNames = sortedAttrNames uplinksRaw;

  bridgeNetworks =
    if !(deploymentHost ? bridgeNetworks) then
      { }
    else if builtins.isAttrs deploymentHost.bridgeNetworks then
      deploymentHost.bridgeNetworks
    else
      throw ''
        lib/render-host-network.nix: deployment host '${deploymentHostName}' has non-attr bridgeNetworks

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';

  wanGroupNames = lib.sort builtins.lessThan (
    lib.unique (lib.filter builtins.isString (map wanGroupNameForTarget localAttachTargetsBase))
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
          lib/render-host-network.nix: render host '${hostName}' has invalid wanUplink '${
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
          lib/render-host-network.nix: deployment host '${deploymentHostName}' has invalid wanUplink '${
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
          lib/render-host-network.nix: render host '${hostName}' has non-attr wanGroupToUplink

          render host config:
          ${builtins.toJSON renderHostConfig}
        ''
    else if deploymentHost ? wanGroupToUplink then
      if builtins.isAttrs deploymentHost.wanGroupToUplink then
        deploymentHost.wanGroupToUplink
      else
        throw ''
          lib/render-host-network.nix: deployment host '${deploymentHostName}' has non-attr wanGroupToUplink

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
          lib/render-host-network.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' must map to a string uplink name
        ''
      else if !builtins.hasAttr uplinkName uplinksRaw then
        throw ''
          lib/render-host-network.nix: wanGroupToUplink entry '${wanGroupName}' on host '${hostName}' references unknown uplink '${uplinkName}'

          known uplinks:
          ${builtins.toJSON uplinkNames}
        ''
      else
        true
    ) (sortedAttrNames configuredWanGroupToUplink)
  );

  wanTargetsForGroup =
    wanGroupName:
    lib.filter (target: wanGroupNameForTarget target == wanGroupName) localAttachTargetsBase;

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
        lib/render-host-network.nix: WAN group '${wanGroupName}' resolved to multiple upstream identities on host '${hostName}'

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
        lib/render-host-network.nix: strict rendering requires explicit WAN uplink assignment for host '${hostName}'

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
    in
    if uplink ? bridge && builtins.isString uplink.bridge then
      uplink.bridge
    else
      throw ''
        lib/render-host-network.nix: uplink '${uplinkName}' assigned to WAN group '${wanGroupName}' is missing bridge

        uplink:
        ${builtins.toJSON uplink}
      '';

  attachTargets = builtins.seq _validateStrictWanRendering (
    map (
      target:
      let
        wanGroupName = wanGroupNameForTarget target;
      in
      target
      // {
        renderedHostBridgeName =
          if wanGroupName != null && builtins.hasAttr wanGroupName wanGroupToUplinkName then
            renderedHostBridgeNameForWanGroup wanGroupName
          else
            target.baseRenderedHostBridgeName;
      }
    ) attachTargetsBase
  );

  localAttachTargets = lib.filter (
    target: builtins.elem (target.unitName or "") selectedUnits
  ) attachTargets;

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
      matches = lib.filter (
        target:
        let
          wanGroupName = wanGroupNameForTarget target;
        in
        wanGroupName != null
        && builtins.hasAttr wanGroupName wanGroupToUplinkName
        && wanGroupToUplinkName.${wanGroupName} == uplinkName
      ) localAttachTargets;

      renderedNames = lib.unique (map (target: target.renderedHostBridgeName) matches);
    in
    if renderedNames == [ ] then
      null
    else if builtins.length renderedNames == 1 then
      builtins.head renderedNames
    else
      throw ''
        lib/render-host-network.nix: uplink '${uplinkName}' resolved to multiple rendered WAN bridges

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
          lib/render-host-network.nix: render host '${hostName}' has invalid fabricUplink '${
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
          lib/render-host-network.nix: deployment host '${deploymentHostName}' has invalid fabricUplink '${
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
            lib/render-host-network.nix: uplink '${uplinkName}' is missing bridge

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
        else if builtins.hasAttr originalBridge bridgeNameMap then
          bridgeNameMap.${originalBridge}
        else
          originalBridge;
    in
    uplink
    // {
      inherit originalBridge;
      bridge = renderedBridge;
    }
  ) uplinksRaw;

  bridgeNetworkFor =
    uplink:
    let
      originalBridge =
        if uplink ? originalBridge && builtins.isString uplink.originalBridge then
          uplink.originalBridge
        else
          uplink.bridge;
    in
    if builtins.hasAttr originalBridge bridgeNetworks then
      bridgeNetworks.${originalBridge}
    else
      { ConfigureWithoutCarrier = true; };

  synthesizedTransitLinks = lib.unique (
    lib.concatMap (
      nodeName:
      let
        node = realizationNodes.${nodeName};
        ports = if node ? ports && builtins.isAttrs node.ports then node.ports else { };
      in
      if (node.host or null) == deploymentHostName then
        lib.concatMap (
          portName:
          let
            port = ports.${portName};
          in
          lib.optionals
            (
              builtins.isAttrs port
              && port ? link
              && builtins.isString port.link
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
            )
            [
              port.link
            ]
        ) (builtins.attrNames ports)
      else
        [ ]
    ) (builtins.attrNames realizationNodes)
  );

  transitBridges =
    if !(deploymentHost ? transitBridges) then
      builtins.listToAttrs (
        map (linkName: {
          name = linkName;
          value = {
            name = linkName;
          };
        }) synthesizedTransitLinks
      )
    else if builtins.isAttrs deploymentHost.transitBridges then
      deploymentHost.transitBridges
    else
      throw ''
        lib/render-host-network.nix: deployment host '${deploymentHostName}' has non-attr transitBridges

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';

  transitNames = sortedAttrNames transitBridges;

  parentNames = lib.unique (
    lib.filter builtins.isString (map (uplinkName: uplinks.${uplinkName}.parent or null) uplinkNames)
  );

  transitNamesForUplink =
    uplinkName:
    lib.filter (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      (transit.parentUplink or null) == uplinkName
    ) transitNames;

  vlanIfNameFor =
    uplinkName:
    let
      uplink = uplinks.${uplinkName};
    in
    if (uplink.mode or "") == "vlan" then "${uplink.parent}.${toString uplink.vlan}" else null;

  uplinkNetdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        vlanIfName = vlanIfNameFor uplinkName;
      in
      [
        {
          name = "10-${uplink.bridge}";
          value = {
            netdevConfig = {
              Name = uplink.bridge;
              Kind = "bridge";
            };
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "vlan") [
        {
          name = "11-${vlanIfName}";
          value = {
            netdevConfig = {
              Name = vlanIfName;
              Kind = "vlan";
            };
            vlanConfig.Id = uplink.vlan;
          };
        }
      ]
      ++ lib.optionals ((uplink.mode or "") == "trunk") (
        map (
          transitName:
          let
            transit = transitBridges.${transitName};
            transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
          in
          {
            name = "12-${transitVlanIfName}";
            value = {
              netdevConfig = {
                Name = transitVlanIfName;
                Kind = "vlan";
              };
              vlanConfig.Id = transit.vlan;
            };
          }
        ) transitNamesOnUplink
      )
    ) uplinkNames
  );

  uplinkParentNetworks = builtins.listToAttrs (
    let
      parentEntries = map (
        parentIf:
        let
          uplinksOnParent = lib.filter (uplinkName: uplinks.${uplinkName}.parent == parentIf) uplinkNames;

          vlanChildren = lib.filter (name: name != null) (map vlanIfNameFor uplinksOnParent);

          directBridgeUplinks = lib.filter (
            uplinkName:
            let
              mode = uplinks.${uplinkName}.mode or "";
            in
            mode != "vlan"
          ) uplinksOnParent;

          _singleDirectBridge =
            if builtins.length directBridgeUplinks <= 1 then
              true
            else
              throw ''
                lib/render-host-network.nix: multiple non-vlan uplinks on parent '${parentIf}' are not supported

                uplinks:
                ${builtins.concatStringsSep "\n  - " ([ "" ] ++ directBridgeUplinks)}
              '';
        in
        {
          name = "20-${parentIf}";
          value = {
            matchConfig.Name = parentIf;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig = {
              ConfigureWithoutCarrier = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA = false;
            }
            // lib.optionalAttrs (vlanChildren != [ ]) {
              VLAN = vlanChildren;
            }
            // lib.optionalAttrs (builtins.length directBridgeUplinks == 1) {
              Bridge = uplinks.${builtins.head directBridgeUplinks}.bridge;
            };
          };
        }
      ) parentNames;

      vlanBridgeEntries = lib.concatMap (
        uplinkName:
        let
          uplink = uplinks.${uplinkName};
          vlanIfName = vlanIfNameFor uplinkName;
        in
        lib.optionals ((uplink.mode or "") == "vlan") [
          {
            name = "21-${vlanIfName}";
            value = {
              matchConfig.Name = vlanIfName;
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
              networkConfig = {
                Bridge = uplink.bridge;
                ConfigureWithoutCarrier = true;
                LinkLocalAddressing = "no";
                IPv6AcceptRA = false;
              };
            };
          }
        ]
      ) uplinkNames;
    in
    parentEntries ++ vlanBridgeEntries
  );

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
        baseBridgeNetworkConfig = bridgeNetworkFor uplink;
        bridgeNetworkConfig = {
          ConfigureWithoutCarrier = true;
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        }
        // baseBridgeNetworkConfig
        // lib.optionalAttrs ((uplink.mode or "") == "trunk" && transitNamesOnUplink != [ ]) {
          VLAN = map (
            transitName:
            let
              transit = transitBridges.${transitName};
            in
            "${uplink.bridge}.${toString transit.vlan}"
          ) transitNamesOnUplink;
        };
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = bridgeNetworkConfig;
        };
      }
    ) uplinkNames
  );

  transitNetdevs = builtins.listToAttrs (
    map (
      transitName:
      let
        transit = transitBridges.${transitName};
      in
      {
        name = "40-${transit.name}";
        value = {
          netdevConfig = {
            Name = transit.name;
            Kind = "bridge";
          };
        };
      }
    ) transitNames
  );

  transitNetworks = builtins.listToAttrs (
    lib.concatMap (
      transitName:
      let
        transit = transitBridges.${transitName};
        parentUplink = transit.parentUplink or null;
      in
      [
        {
          name = "50-${transit.name}";
          value = {
            matchConfig.Name = transit.name;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++
        lib.optionals
          (
            parentUplink != null
            && builtins.hasAttr parentUplink uplinks
            && (uplinks.${parentUplink}.mode or "") == "trunk"
          )
          [
            {
              name =
                let
                  uplink = uplinks.${parentUplink};
                  transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
                in
                "51-${transitVlanIfName}";
              value =
                let
                  uplink = uplinks.${parentUplink};
                  transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
                in
                {
                  matchConfig.Name = transitVlanIfName;
                  linkConfig = {
                    ActivationPolicy = "always-up";
                    RequiredForOnline = "no";
                  };
                  networkConfig = {
                    Bridge = transit.name;
                    ConfigureWithoutCarrier = true;
                    LinkLocalAddressing = "no";
                    IPv6AcceptRA = false;
                  };
                };
            }
          ]
    ) transitNames
  );

  synthesizedNetdevs =
    if hostHasUplinks then
      localBridgeNetdevs // uplinkNetdevs // transitNetdevs
    else
      localBridgeNetdevs;

  synthesizedNetworks =
    if hostHasUplinks then
      localBridgeNetworks // uplinkParentNetworks // uplinkBridgeNetworks // transitNetworks
    else
      localBridgeNetworks;

  mkRoute =
    route:
    if !builtins.isAttrs route then
      null
    else
      let
        gateway =
          if route ? via4 && route.via4 != null then
            route.via4
          else if route ? via6 && route.via6 != null then
            route.via6
          else
            null;
      in
      if gateway == null then
        null
      else
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (route ? dst && route.dst != null) {
          Destination = route.dst;
        };

  mkDynamicWanNetworkConfig =
    iface:
    let
      connectivity = iface.connectivity or { };
      isWan = (connectivity.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];

      wanUplink =
        if isWan && wanUplinkName != null && builtins.hasAttr wanUplinkName uplinks then
          uplinks.${wanUplinkName}
        else
          { };

      ipv4Enabled =
        wanUplink ? ipv4 && builtins.isAttrs wanUplink.ipv4 && (wanUplink.ipv4.enable or false);

      ipv4Dhcp =
        ipv4Enabled
        && wanUplink ? ipv4
        && builtins.isAttrs wanUplink.ipv4
        && (wanUplink.ipv4.dhcp or false);

      ipv6Enabled =
        wanUplink ? ipv6 && builtins.isAttrs wanUplink.ipv6 && (wanUplink.ipv6.enable or false);

      ipv6Dhcp =
        ipv6Enabled
        && wanUplink ? ipv6
        && builtins.isAttrs wanUplink.ipv6
        && (wanUplink.ipv6.dhcp or false);

      ipv6AcceptRA =
        ipv6Enabled
        && wanUplink ? ipv6
        && builtins.isAttrs wanUplink.ipv6
        && (wanUplink.ipv6.acceptRA or false);

      dhcpMode =
        if ipv4Dhcp && ipv6Dhcp then
          "yes"
        else if ipv4Dhcp then
          "ipv4"
        else if ipv6Dhcp then
          "ipv6"
        else
          "no";
    in
    if isWan && addresses == [ ] then
      {
        DHCP = dhcpMode;
        IPv6AcceptRA = ipv6AcceptRA;
        LinkLocalAddressing = if ipv6AcceptRA || ipv6Dhcp then "ipv6" else "no";
      }
    else
      {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };

  mkContainerNetworks =
    {
      interfaces,
      loopback,
      interfaceNameMap,
    }:
    let
      interfaceNames = sortedAttrNames interfaces;

      loopbackAddresses = lib.filter builtins.isString [
        (loopback.addr4 or null)
        (loopback.addr6 or null)
      ];

      loopbackUnit = lib.optionalAttrs (loopbackAddresses != [ ]) {
        "00-lo" = {
          matchConfig.Name = "lo";
          address = loopbackAddresses;
          linkConfig.RequiredForOnline = "no";
          networkConfig.ConfigureWithoutCarrier = true;
        };
      };

      interfaceUnits = builtins.listToAttrs (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            renderedName = interfaceNameMap.${ifName};
            routes = lib.filter (route: route != null) (map mkRoute (iface.routes or [ ]));
            dynamicWanNetworkConfig = mkDynamicWanNetworkConfig iface;
          in
          {
            name = "10-${renderedName}";
            value = {
              matchConfig.Name = renderedName;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              }
              // dynamicWanNetworkConfig;
              address = iface.addresses or [ ];
              routes = routes;
            };
          }
        ) interfaceNames
      );
    in
    loopbackUnit // interfaceUnits;

  attachTargetForInterface =
    {
      unitName,
      ifName,
      iface,
    }:
    let
      matches = lib.filter (
        target:
        (target.unitName or null) == unitName
        && (
          (target.ifName or null) == ifName
          || ((target.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.hostBridgeName or null) == (iface.hostBridge or null))
        )
      ) attachTargets;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.hasAttr iface.hostBridge bridgeNameMap then
      {
        renderedHostBridgeName = bridgeNameMap.${iface.hostBridge};
      }
    else
      throw ''
        lib/render-host-network.nix: could not resolve rendered host bridge for unit '${unitName}', interface '${ifName}'

        iface.hostBridge:
        ${iface.hostBridge}

        available bridgeNameMap keys:
        ${builtins.toJSON (builtins.attrNames bridgeNameMap)}

        attachTargets:
        ${builtins.toJSON attachTargets}
      '';

  selectedRoleNames = lib.filter (roleName: builtins.hasAttr roleName roles) (
    lib.unique (
      map (
        unitName:
        runtimeContext.roleForUnit {
          cpm = cpm;
          inventory = inventory;
          inherit unitName;
          file = "lib/render-host-network.nix";
        }
      ) selectedUnits
    )
  );

  selectedRoles = builtins.listToAttrs (
    map (roleName: {
      name = roleName;
      value = roles.${roleName};
    }) selectedRoleNames
  );

  containerEnabledUnitNames = lib.filter (
    unitName:
    let
      roleName = runtimeContext.roleForUnit {
        cpm = cpm;
        inventory = inventory;
        inherit unitName;
        file = "lib/render-host-network.nix";
      };
    in
    builtins.hasAttr roleName selectedRoles
    && selectedRoles.${roleName} ? container
    && builtins.isAttrs selectedRoles.${roleName}.container
    && (selectedRoles.${roleName}.container.enable or false)
  ) selectedUnits;

  mkContainer =
    unitName:
    let
      runtimeTarget = cpmAdapter.normalizedRuntimeTargetForUnit {
        cpm = cpm;
        inherit unitName;
        file = "lib/render-host-network.nix";
      };

      interfaces = runtimeTarget.interfaces or { };
      interfaceNames = sortedAttrNames interfaces;

      interfaceNameMap = builtins.listToAttrs (
        map (ifName: {
          name = ifName;
          value =
            let
              iface = interfaces.${ifName};
            in
            if iface ? renderedIfName && builtins.isString iface.renderedIfName then
              iface.renderedIfName
            else
              ifName;
        }) interfaceNames
      );

      roleName = runtimeContext.roleForUnit {
        cpm = cpm;
        inventory = inventory;
        inherit unitName;
        file = "lib/render-host-network.nix";
      };

      roleConfig = if builtins.hasAttr roleName selectedRoles then selectedRoles.${roleName} else { };

      profilePath =
        if
          roleConfig ? container
          && builtins.isAttrs roleConfig.container
          && roleConfig.container ? profilePath
        then
          roleConfig.container.profilePath
        else
          null;

      additionalCapabilities =
        if
          roleConfig ? container
          && builtins.isAttrs roleConfig.container
          && roleConfig.container ? additionalCapabilities
          && builtins.isList roleConfig.container.additionalCapabilities
        then
          roleConfig.container.additionalCapabilities
        else
          [ ];

      bindMounts =
        if
          roleConfig ? container
          && builtins.isAttrs roleConfig.container
          && roleConfig.container ? bindMounts
          && builtins.isAttrs roleConfig.container.bindMounts
        then
          roleConfig.container.bindMounts
        else
          { };

      allowedDevices =
        if
          roleConfig ? container
          && builtins.isAttrs roleConfig.container
          && roleConfig.container ? allowedDevices
          && builtins.isList roleConfig.container.allowedDevices
        then
          roleConfig.container.allowedDevices
        else
          [ ];

      interfaceSourceKindFor =
        ifName:
        let
          iface = interfaces.${ifName};
        in
        if
          iface ? connectivity && builtins.isAttrs iface.connectivity && iface.connectivity ? sourceKind
        then
          iface.connectivity.sourceKind
        else
          null;

      wanInterfaceNames = map (ifName: interfaceNameMap.${ifName}) (
        lib.filter (ifName: interfaceSourceKindFor ifName == "wan") interfaceNames
      );

      lanInterfaceNames = map (ifName: interfaceNameMap.${ifName}) (
        lib.filter (ifName: interfaceSourceKindFor ifName != "wan") interfaceNames
      );

      nftQuotedIfNames = names: builtins.concatStringsSep ", " (map (name: ''"${name}"'') names);

      nftIfSet = names: "{ ${nftQuotedIfNames names} }";

      coreNftRuleset =
        if roleName == "core" && wanInterfaceNames != [ ] && lanInterfaceNames != [ ] then
          ''
            table inet filter {
              chain forward {
                type filter hook forward priority 0; policy drop;
                ct state { established, related } accept
                iifname ${nftIfSet lanInterfaceNames} oifname ${nftIfSet wanInterfaceNames} accept
              }
            }

            table ip nat {
              chain postrouting {
                type nat hook postrouting priority 100; policy accept;
                oifname ${nftIfSet wanInterfaceNames} masquerade
              }
            }
          ''
        else
          null;

      extraVeths = builtins.listToAttrs (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            attachTarget = attachTargetForInterface {
              inherit unitName ifName iface;
            };
          in
          {
            name = interfaceNameMap.${ifName};
            value = {
              hostBridge = attachTarget.renderedHostBridgeName;
            };
          }
        ) interfaceNames
      );

      containerNetworks = mkContainerNetworks {
        inherit interfaces interfaceNameMap;
        loopback = runtimeTarget.loopback or { };
      };
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        inherit bindMounts allowedDevices extraVeths;

        additionalCapabilities = lib.unique (
          [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ]
          ++ additionalCapabilities
        );

        specialArgs = {
          inherit unitName deploymentHostName runtimeTarget;
          controlPlaneOut = cpm;
          globalInventory = inventory;
          hostContext = resolvedHostContext;
          s88Role = roleConfig;
          s88RoleName = roleName;
        };

        config =
          { pkgs, ... }:
          {
            imports = [
              ../s88/CM/network/profiles/common-router.nix
              ../s88/CM/network/../../mount-utils.nix
            ]
            ++ lib.optionals (profilePath != null) [
              profilePath
            ];

            environment.systemPackages = with pkgs; [
              bindfs
              gron
              traceroute
            ];

            networking.hostName = unitName;
            networking.useNetworkd = true;
            systemd.network.enable = true;
            networking.useDHCP = false;
            networking.useHostResolvConf = lib.mkForce false;
            services.resolved.enable = lib.mkForce false;
            networking.nftables = lib.mkIf (coreNftRuleset != null) {
              enable = true;
              ruleset = coreNftRuleset;
            };
            system.stateVersion = lib.mkDefault "25.11";

            systemd.network.networks = containerNetworks;
          };
      };
    };

  containers = builtins.seq _selectedUnitsNonEmpty (
    builtins.listToAttrs (map mkContainer containerEnabledUnitNames)
  );
in
{
  inherit
    hostName
    deploymentHostName
    deploymentHost
    renderHostConfig
    bridgeNameMap
    bridges
    attachTargets
    localAttachTargets
    selectedUnits
    selectedRoleNames
    selectedRoles
    containers
    resolvedHostContext
    ;

  runtimeRole = runtimeRole;

  netdevs = builtins.seq _selectedUnitsNonEmpty synthesizedNetdevs;
  networks = builtins.seq _selectedUnitsNonEmpty synthesizedNetworks;

  uplinks = uplinks;
  transitBridges = transitBridges;

  debug = {
    inherit
      hostName
      deploymentHostName
      runtimeRole
      selectedUnits
      ;
    localBridgeNameMap = bridgeNameMap;
    localAttachTargets = localAttachTargets;
    uplinks = uplinks;
    transitBridges = transitBridges;
  };
}
