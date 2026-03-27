{
  config,
  lib,
  globalInventory,
  controlPlaneOut,
  ...
}:

let
  inventory = globalInventory;
  hostname = config.networking.hostName;

  renderHosts =
    if inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  renderHostConfig =
    if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
      renderHosts.${hostname}
    else
      { };

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      throw ''
        host-network:

        inventory.deployment.hosts missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  deploymentHostNames = lib.sort builtins.lessThan (builtins.attrNames deploymentHosts);

  deploymentHostName =
    if renderHostConfig ? deploymentHost
      && builtins.isString renderHostConfig.deploymentHost
      && builtins.hasAttr renderHostConfig.deploymentHost deploymentHosts
    then
      renderHostConfig.deploymentHost
    else if builtins.hasAttr hostname deploymentHosts then
      hostname
    else if builtins.length deploymentHostNames == 1 then
      builtins.head deploymentHostNames
    else
      throw ''
        host-network:

        inventory.deployment host for '${hostname}' missing, and fallback is ambiguous.

        Current hostname:
        ${hostname}

        Known deployment hosts:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ deploymentHostNames)}
      '';

  hostConfig = deploymentHosts.${deploymentHostName};

  uplinks =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw ''
        host-network:

        inventory.deployment.hosts.${deploymentHostName}.uplinks missing.

        host config:
        ${builtins.toJSON hostConfig}
      '';

  bridgeNetworks =
    if hostConfig ? bridgeNetworks && builtins.isAttrs hostConfig.bridgeNetworks then
      hostConfig.bridgeNetworks
    else
      { };

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  cpmData =
    if controlPlaneOut ? control_plane_model
      && builtins.isAttrs controlPlaneOut.control_plane_model
      && controlPlaneOut.control_plane_model ? data
      && builtins.isAttrs controlPlaneOut.control_plane_model.data
    then
      controlPlaneOut.control_plane_model.data
    else
      { };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  siteEntries =
    lib.concatMap (
      enterpriseName:
      let
        enterprise = cpmData.${enterpriseName};
      in
      map (
        siteName:
        {
          inherit enterpriseName siteName;
          site = enterprise.${siteName};
        }
      ) (sortedAttrNames enterprise)
    ) (sortedAttrNames cpmData);

  runtimeTargets =
    lib.foldl' (
      acc: entry:
      acc // (
        if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
          entry.site.runtimeTargets
        else
          { }
      )
    ) { } siteEntries;

  runtimeTargetNames = sortedAttrNames runtimeTargets;

  tenantNameForUnit =
    unitName:
    let
      target =
        if builtins.hasAttr unitName runtimeTargets then
          runtimeTargets.${unitName}
        else
          { };

      logicalName =
        if target ? logicalNode
          && builtins.isAttrs target.logicalNode
          && target.logicalNode ? name
          && builtins.isString target.logicalNode.name
        then
          target.logicalNode.name
        else if builtins.hasAttr unitName realizationNodes
          && realizationNodes.${unitName} ? logicalNode
          && builtins.isAttrs realizationNodes.${unitName}.logicalNode
          && realizationNodes.${unitName}.logicalNode ? name
          && builtins.isString realizationNodes.${unitName}.logicalNode.name
        then
          realizationNodes.${unitName}.logicalNode.name
        else
          unitName;
    in
    if lib.hasPrefix "s-router-access-" logicalName then
      builtins.substring
        (builtins.stringLength "s-router-access-")
        (builtins.stringLength logicalName - builtins.stringLength "s-router-access-")
        logicalName
    else
      null;

  siteEntryForUnit =
    unitName:
    let
      tenantName = tenantNameForUnit unitName;

      matches =
        builtins.filter (
          entry:
          tenantName != null
          && entry.site ? attachments
          && builtins.isList entry.site.attachments
          && builtins.any (
            attachment:
            builtins.isAttrs attachment
            && (attachment.kind or null) == "tenant"
            && (attachment.name or null) == tenantName
            && (attachment.unit or null) == unitName
          ) entry.site.attachments
        ) siteEntries;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      null;

  tenantDomainForUnit =
    unitName:
    let
      tenantName = tenantNameForUnit unitName;
      siteEntry = siteEntryForUnit unitName;
      site =
        if siteEntry != null then
          siteEntry.site
        else
          null;

      domains =
        if site != null
          && site ? domains
          && builtins.isAttrs site.domains
          && site.domains ? tenants
          && builtins.isList site.domains.tenants
        then
          site.domains.tenants
        else
          [ ];

      matches =
        builtins.filter (
          domain:
          builtins.isAttrs domain
          && (domain.name or null) == tenantName
          && domain ? ipv4
          && builtins.isString domain.ipv4
        ) domains;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      null;

  vlanFromCIDR =
    cidr:
    let
      addr = builtins.elemAt (lib.splitString "/" cidr) 0;
      octets = lib.splitString "." addr;
    in
    if builtins.length octets == 4 then
      builtins.fromJSON (builtins.elemAt octets 2)
    else
      throw ''
        host-network:

        Cannot derive VLAN from IPv4 CIDR '${cidr}'.
      '';

  localAccessUnits =
    lib.filter (
      unitName:
      let
        target =
          if builtins.hasAttr unitName runtimeTargets then
            runtimeTargets.${unitName}
          else
            { };

        logicalName =
          if target ? logicalNode
            && builtins.isAttrs target.logicalNode
            && target.logicalNode ? name
            && builtins.isString target.logicalNode.name
          then
            target.logicalNode.name
          else
            null;

        role =
          if target ? role && builtins.isString target.role then
            target.role
          else
            null;

        placementHost =
          if target ? placement
            && builtins.isAttrs target.placement
            && target.placement ? host
            && builtins.isString target.placement.host
          then
            target.placement.host
          else
            null;

        realizationHost =
          if builtins.hasAttr unitName realizationNodes
            && realizationNodes.${unitName} ? host
            && builtins.isString realizationNodes.${unitName}.host
          then
            realizationNodes.${unitName}.host
          else
            null;
      in
      (role == "access" || (logicalName != null && lib.hasPrefix "s-router-access-" logicalName))
      && (
        placementHost == deploymentHostName
        || realizationHost == deploymentHostName
      )
    ) runtimeTargetNames;

  uplinkNames = lib.sort builtins.lessThan (builtins.attrNames uplinks);

  trunkParent =
    let
      names = lib.unique (map (uplinkName: uplinks.${uplinkName}.parent) uplinkNames);
    in
    if builtins.length names == 1 then
      builtins.head names
    else
      throw ''
        host-network:

        Expected exactly 1 parent uplink for access host.

        Parents:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ names)}
      '';

  tenantBridgeSpecs =
    lib.unique (
      map (
        unitName:
        let
          domain = tenantDomainForUnit unitName;
          vlan =
            if domain != null then
              vlanFromCIDR domain.ipv4
            else
              throw ''
                host-network:

                Could not resolve tenant domain for local access unit '${unitName}'.
              '';
        in
        {
          bridge = "br-lan-${toString vlan}";
          vlanIf = "${trunkParent}.${toString vlan}";
          vlan = vlan;
        }
      ) localAccessUnits
    );

  synthesizedTransitLinks =
    lib.unique (
      lib.concatMap (
        nodeName:
        let
          node = realizationNodes.${nodeName};
          ports =
            if node ? ports && builtins.isAttrs node.ports then
              node.ports
            else
              { };
        in
        if (node.host or null) == deploymentHostName then
          lib.concatMap (
            portName:
            let
              port = ports.${portName};
            in
            lib.optionals (
              builtins.isAttrs port
              && port ? link
              && builtins.isString port.link
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
            ) [
              port.link
            ]
          ) (builtins.attrNames ports)
        else
          [ ]
      ) (builtins.attrNames realizationNodes)
    );

  transitBridges =
    if hostConfig ? transitBridges && builtins.isAttrs hostConfig.transitBridges then
      hostConfig.transitBridges
    else
      builtins.listToAttrs (
        map (
          linkName:
          {
            name = linkName;
            value = {
              name = linkName;
            };
          }
        ) synthesizedTransitLinks
      );

  transitNames = lib.sort builtins.lessThan (builtins.attrNames transitBridges);

  parentNames =
    lib.unique (
      map (uplinkName: uplinks.${uplinkName}.parent) uplinkNames
    );

  bridgeNetworkFor =
    bridge:
    if builtins.hasAttr bridge bridgeNetworks then
      bridgeNetworks.${bridge}
    else
      { ConfigureWithoutCarrier = true; };

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
    if (uplink.mode or "") == "vlan" then
      "${uplink.parent}.${toString uplink.vlan}"
    else
      null;

  uplinkNetdevsBase = builtins.listToAttrs (
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

  tenantNetdevs =
    builtins.listToAttrs (
      lib.concatMap (
        spec:
        [
          {
            name = "13-${spec.bridge}";
            value = {
              netdevConfig = {
                Name = spec.bridge;
                Kind = "bridge";
              };
            };
          }
          {
            name = "14-${spec.vlanIf}";
            value = {
              netdevConfig = {
                Name = spec.vlanIf;
                Kind = "vlan";
              };
              vlanConfig.Id = spec.vlan;
            };
          }
        ]
      ) tenantBridgeSpecs
    );

  uplinkNetdevs = uplinkNetdevsBase // tenantNetdevs;

  uplinkParentNetworks =
    builtins.listToAttrs (
      let
        parentEntries =
          map (
            parentIf:
            let
              uplinksOnParent =
                lib.filter (uplinkName: uplinks.${uplinkName}.parent == parentIf) uplinkNames;

              vlanChildren =
                (lib.filter (name: name != null) (map vlanIfNameFor uplinksOnParent))
                ++ (map (spec: spec.vlanIf) tenantBridgeSpecs);

              directBridgeUplinks =
                lib.filter (
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
                    host-network: multiple non-vlan uplinks on parent '${parentIf}' are not supported

                    uplinks:
                    ${builtins.concatStringsSep "\n  - " ([ "" ] ++ directBridgeUplinks)}
                  '';
            in
            {
              name = "20-${parentIf}";
              value = {
                matchConfig.Name = parentIf;
                networkConfig =
                  {
                    ConfigureWithoutCarrier = true;
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

        vlanBridgeEntries =
          lib.concatMap (
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
                  networkConfig = {
                    Bridge = uplink.bridge;
                    ConfigureWithoutCarrier = true;
                  };
                };
              }
            ]
          ) uplinkNames;

        tenantBridgeEntries =
          map (
            spec:
            {
              name = "22-${spec.vlanIf}";
              value = {
                matchConfig.Name = spec.vlanIf;
                networkConfig = {
                  Bridge = spec.bridge;
                  ConfigureWithoutCarrier = true;
                };
              };
            }
          ) tenantBridgeSpecs;
      in
      parentEntries ++ vlanBridgeEntries ++ tenantBridgeEntries
    );

  uplinkBridgeNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = uplinks.${uplinkName};
        transitNamesOnUplink = transitNamesForUplink uplinkName;
      in
      {
        name = "30-${uplink.bridge}";
        value = {
          matchConfig.Name = uplink.bridge;
          networkConfig =
            bridgeNetworkFor uplink.bridge
            // lib.optionalAttrs ((uplink.mode or "") == "trunk" && transitNamesOnUplink != [ ]) {
              VLAN = map (
                transitName:
                let
                  transit = transitBridges.${transitName};
                in
                "${uplink.bridge}.${toString transit.vlan}"
              ) transitNamesOnUplink;
            };
        };
      }
    ) uplinkNames
  );

  tenantBridgeNetworks =
    builtins.listToAttrs (
      map (
        spec:
        {
          name = "31-${spec.bridge}";
          value = {
            matchConfig.Name = spec.bridge;
            networkConfig = {
              ConfigureWithoutCarrier = true;
            };
          };
        }
      ) tenantBridgeSpecs
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
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
      ++ lib.optionals (parentUplink != null && builtins.hasAttr parentUplink uplinks && (uplinks.${parentUplink}.mode or "") == "trunk") [
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
              networkConfig = {
                Bridge = transit.name;
                ConfigureWithoutCarrier = true;
              };
            };
        }
      ]
    ) transitNames
  );
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.netdevs = uplinkNetdevs // transitNetdevs;
  systemd.network.networks =
    uplinkParentNetworks
    // uplinkBridgeNetworks
    // tenantBridgeNetworks
    // transitNetworks;
}
