{
  lib,
  hostName,
  cpm,
  inventory ? { },
}:

let
  runtimeContext = import ./runtime-context.nix { inherit lib; };
  cpmAdapter = import ./cpm-runtime-adapter.nix { inherit lib; };
  realizationPorts = import ./realization-ports.nix { inherit lib; };
  hostQuery = import ./host-query.nix { inherit lib; };
  hostNaming = import ./host-naming.nix { inherit lib; };
  bridgeRenderer = import ./tenant-bridge-renderer.nix { inherit lib; };
  roles = import ./s88-role-registry.nix { inherit lib; };
  nft = import ./s88-nftables.nix { inherit lib; };

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
      {
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

  deploymentHostName = resolvedHostContext.deploymentHostName or hostName;
  deploymentHost = resolvedHostContext.deploymentHost or { };
  renderHostConfig = resolvedHostContext.renderHostConfig or { };

  realizationNodes =
    if
      resolvedHostContext ? realizationNodes && builtins.isAttrs resolvedHostContext.realizationNodes
    then
      resolvedHostContext.realizationNodes
    else if
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

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    inherit cpm inventory deploymentHostName;
    file = "lib/render-host-network.nix";
  };

  runtimeRole =
    if renderHostConfig ? runtimeRole && builtins.isString renderHostConfig.runtimeRole then
      renderHostConfig.runtimeRole
    else
      null;

  selectedUnits = runtimeContext.selectedUnitsForHostContext {
    inherit cpm inventory runtimeRole;
    hostContext = resolvedHostContext;
    file = "lib/render-host-network.nix";
  };

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

  selectedRoleNames = runtimeContext.selectedRoleNamesForUnits {
    inherit cpm inventory selectedUnits;
    file = "lib/render-host-network.nix";
  };

  selectedRoles = builtins.listToAttrs (
    map (roleName: {
      name = roleName;
      value = roles.${roleName};
    }) (lib.filter (roleName: builtins.hasAttr roleName roles) selectedRoleNames)
  );

  attachTargetsRuntime = realizationPorts.attachTargetsForUnitsFromRuntime {
    inherit selectedUnits normalizedRuntimeTargets;
    file = "lib/render-host-network.nix";
  };

  bridgeArtifacts = bridgeRenderer.renderBridgeArtifacts {
    attachTargets = attachTargetsRuntime;
    shorten = hostNaming.shorten;
    ensureUnique = hostNaming.ensureUnique;
  };

  bridgeNameMap = bridgeArtifacts.bridgeNameMap;
  bridges = bridgeArtifacts.bridges;
  localBridgeNetdevs = bridgeArtifacts.netdevs;
  localBridgeNetworks = bridgeArtifacts.networks;

  attachTargetsBase = map (
    target:
    let
      iface = target.interface or { };
      hostBridgeName = target.hostBridgeName;
    in
    target
    // {
      baseRenderedHostBridgeName =
        if builtins.hasAttr hostBridgeName bridgeNameMap then
          bridgeNameMap.${hostBridgeName}
        else
          hostNaming.shorten hostBridgeName;
      renderedIfName = iface.renderedIfName or null;
      addresses = iface.addresses or [ ];
      routes = iface.routes or [ ];
      connectivity = target.connectivity or (iface.connectivity or { });
      interface = iface;
    }
  ) attachTargetsRuntime;

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
      file = "lib/render-host-network.nix";
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

      originalBridge =
        if uplink ? bridge && builtins.isString uplink.bridge then
          uplink.bridge
        else
          throw ''
            lib/render-host-network.nix: uplink '${uplinkName}' assigned to WAN group '${wanGroupName}' is missing bridge

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
        else
          uplinkBridgeNameMap.${originalBridge};
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

  synthesizedTransitBridgeNameMap = hostNaming.ensureUnique synthesizedTransitLinks;

  transitBridges =
    if !(deploymentHost ? transitBridges) then
      builtins.listToAttrs (
        map (linkName: {
          name = linkName;
          value = {
            name = synthesizedTransitBridgeNameMap.${linkName};
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
            transitNameRendered =
              if transit ? name && builtins.isString transit.name then
                transit.name
              else
                hostNaming.shorten transitName;
            transitVlanIfName = "${uplink.bridge}.${toString transit.vlan}";
          in
          {
            name = "12-${transitNameRendered}";
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

        transitNameRendered =
          if transit ? name && builtins.isString transit.name then
            transit.name
          else
            hostNaming.shorten transitName;
      in
      {
        name = "40-${transitNameRendered}";
        value = {
          netdevConfig = {
            Name = transitNameRendered;
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

        transitNameRendered =
          if transit ? name && builtins.isString transit.name then
            transit.name
          else
            hostNaming.shorten transitName;

        parentUplink = transit.parentUplink or null;
      in
      [
        {
          name = "50-${transitNameRendered}";
          value = {
            matchConfig.Name = transitNameRendered;
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
                    Bridge = transitNameRendered;
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
    attachTarget: iface:
    let
      connectivity = iface.connectivity or { };
      isWan = (connectivity.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];

      assignedUplink =
        if
          isWan
          && attachTarget != null
          && attachTarget ? assignedUplinkName
          && attachTarget.assignedUplinkName != null
          && builtins.hasAttr attachTarget.assignedUplinkName uplinks
        then
          uplinks.${attachTarget.assignedUplinkName}
        else if isWan && wanUplinkName != null && builtins.hasAttr wanUplinkName uplinks then
          uplinks.${wanUplinkName}
        else
          { };

      ipv4Enabled =
        assignedUplink ? ipv4
        && builtins.isAttrs assignedUplink.ipv4
        && (assignedUplink.ipv4.enable or false);

      ipv4Dhcp =
        ipv4Enabled
        && assignedUplink ? ipv4
        && builtins.isAttrs assignedUplink.ipv4
        && (assignedUplink.ipv4.dhcp or false);

      ipv6Enabled =
        assignedUplink ? ipv6
        && builtins.isAttrs assignedUplink.ipv6
        && (assignedUplink.ipv6.enable or false);

      ipv6Dhcp =
        ipv6Enabled
        && assignedUplink ? ipv6
        && builtins.isAttrs assignedUplink.ipv6
        && (assignedUplink.ipv6.dhcp or false);

      ipv6AcceptRA =
        ipv6Enabled
        && assignedUplink ? ipv6
        && builtins.isAttrs assignedUplink.ipv6
        && (assignedUplink.ipv6.acceptRA or false);

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
        assignedUplinkName = null;
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

  mkContainerNetworks =
    {
      unitName,
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
            attachTarget = attachTargetForInterface {
              inherit unitName ifName iface;
            };
            routes = lib.filter (route: route != null) (map mkRoute (iface.routes or [ ]));
            dynamicWanNetworkConfig = mkDynamicWanNetworkConfig attachTarget iface;
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

  roleForUnit =
    unitName:
    runtimeContext.roleForUnit {
      inherit cpm inventory unitName;
      file = "lib/render-host-network.nix";
    };

  containerEnabledUnitNames = lib.filter (
    unitName:
    let
      roleName = roleForUnit unitName;
    in
    builtins.hasAttr roleName selectedRoles
    && selectedRoles.${roleName} ? container
    && builtins.isAttrs selectedRoles.${roleName}.container
    && (selectedRoles.${roleName}.container.enable or false)
  ) selectedUnits;

  mkContainer =
    unitName:
    let
      runtimeTarget = normalizedRuntimeTargets.${unitName};
      interfaces = runtimeTarget.interfaces or { };
      loopback = runtimeTarget.loopback or { };

      interfaceNameMap = cpmAdapter.renderedInterfaceNamesForUnit {
        inherit cpm unitName;
        file = "lib/render-host-network.nix";
      };

      interfaceNames = sortedAttrNames interfaces;

      roleName = roleForUnit unitName;
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

      nftRuleset =
        if builtins.hasAttr roleName nft then
          nft.${roleName} {
            wanIfs = wanInterfaceNames;
            lanIfs = lanInterfaceNames;
            inherit
              unitName
              roleName
              runtimeTarget
              interfaces
              ;
          }
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
            containerIfName = interfaceNameMap.${ifName};
            hostIfName = hostNaming.shorten "${unitName}-${containerIfName}";
          in
          {
            name = containerIfName;
            value = {
              hostBridge = attachTarget.renderedHostBridgeName;
              hostInterfaceName = hostIfName;
            };
          }
        ) interfaceNames
      );

      containerNetworks = mkContainerNetworks {
        inherit
          unitName
          interfaces
          loopback
          interfaceNameMap
          ;
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
            ]
            ++ lib.optionals (profilePath != null) [
              profilePath
            ];

            environment.systemPackages = with pkgs; [
              gron
              traceroute
            ];

            networking.hostName = unitName;
            networking.useNetworkd = true;
            systemd.network.enable = true;
            networking.useDHCP = false;
            networking.useHostResolvConf = lib.mkForce false;
            services.resolved.enable = lib.mkForce false;

            networking.nftables = lib.mkIf (nftRuleset != null) {
              enable = true;
              ruleset = nftRuleset;
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
