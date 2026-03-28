{
  repoRoot,
  intentPath,
  inventoryPath,
  exampleDir ? null,
  debug ? false,
}:

let
  flake = builtins.getFlake (toString (builtins.toPath repoRoot));

  sortedAttrNames = attrs:
    builtins.sort builtins.lessThan (builtins.attrNames attrs);

  uniqueStrings =
    values:
    sortedAttrNames (
      builtins.listToAttrs (
        map
          (value: {
            name = value;
            value = true;
          })
          (builtins.filter builtins.isString values)
      )
    );

  selectAttrs =
    names: attrs:
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = attrs.${name};
        })
        (builtins.filter (name: builtins.hasAttr name attrs) names)
    );

  siteTreeForEnterprise =
    enterprise:
    if builtins.isAttrs enterprise
      && enterprise ? site
      && builtins.isAttrs enterprise.site
    then
      enterprise.site
    else if builtins.isAttrs enterprise then
      enterprise
    else
      { };

  logicalField =
    field: node:
    if node ? logicalNode
      && builtins.isAttrs node.logicalNode
      && builtins.hasAttr field node.logicalNode
      && builtins.isString node.logicalNode.${field}
    then
      node.logicalNode.${field}
    else
      null;

  shortenIfName =
    name:
    if builtins.stringLength name <= 15 then
      name
    else
      let
        hash = builtins.hashString "sha256" name;
      in
      "${builtins.substring 0 8 name}-${builtins.substring 0 6 hash}";

  intent = flake.lib.renderer.loadIntent (builtins.toPath intentPath);
  inventory = flake.lib.renderer.loadInventory (builtins.toPath inventoryPath);

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  hasDeploymentHosts = deploymentHosts != { };

  hasLegacyFabricLayer =
    inventory ? fabric
    && builtins.isAttrs inventory.fabric
    && inventory.fabric != { };

  realizationNodes = flake.lib.realizationPorts.realizationNodesFor inventory;

  hasRealizationLayer =
    realizationNodes != { };

  useLegacyFabric =
    hasLegacyFabricLayer && !hasDeploymentHosts && !hasRealizationLayer;

  matchingRealizationNodes =
    predicate:
    builtins.listToAttrs (
      map
        (nodeName: {
          name = nodeName;
          value = realizationNodes.${nodeName};
        })
        (builtins.filter
          (nodeName: predicate realizationNodes.${nodeName})
          (sortedAttrNames realizationNodes))
    );

  hostNamesFromNodes =
    nodes:
    uniqueStrings (
      map
        (nodeName:
          let
            node = nodes.${nodeName};
          in
            if node ? host && builtins.isString node.host then node.host else null)
        (sortedAttrNames nodes)
    );

  enterpriseNames =
    if builtins.isAttrs intent then
      sortedAttrNames intent
    else
      [ ];

  enterprises =
    builtins.listToAttrs (
      map
        (enterpriseName:
          let
            enterpriseNodes =
              matchingRealizationNodes (
                node: logicalField "enterprise" node == enterpriseName
              );

            enterpriseHostNames = hostNamesFromNodes enterpriseNodes;
          in
            {
              name = enterpriseName;
              value = {
                intent =
                  if builtins.hasAttr enterpriseName intent then
                    intent.${enterpriseName}
                  else
                    { };

                siteNames =
                  if builtins.hasAttr enterpriseName intent then
                    sortedAttrNames (siteTreeForEnterprise intent.${enterpriseName})
                  else
                    [ ];

                realizationNodes = enterpriseNodes;
                deploymentHostNames = enterpriseHostNames;
                deploymentHosts = selectAttrs enterpriseHostNames deploymentHosts;
              };
            })
        enterpriseNames
    );

  normalizedHostRenderings =
    if deploymentHosts == { } then
      { }
    else
      builtins.listToAttrs (
        map
          (hostName: {
            name = hostName;
            value = flake.lib.renderer.renderHostNetwork {
              inherit inventory hostName;
            };
          })
          (sortedAttrNames deploymentHosts)
      );

  normalizedRenderHosts =
    builtins.listToAttrs (
      map
        (hostName:
          let
            hostRendering = normalizedHostRenderings.${hostName};
          in
            {
              name = hostName;
              value = {
                network = {
                  bridges = hostRendering.bridges;
                  netdevs = hostRendering.netdevs;
                  networks = hostRendering.networks;
                };
              };
            })
        (sortedAttrNames normalizedHostRenderings)
    );

  normalizedRenderNodes =
    if !hasRealizationLayer then
      { }
    else
      builtins.listToAttrs (
        map
          (unitName:
            let
              realizationNode = realizationNodes.${unitName};

              logicalNode =
                if realizationNode ? logicalNode && builtins.isAttrs realizationNode.logicalNode then
                  realizationNode.logicalNode
                else
                  { };

              deploymentHostName =
                if realizationNode ? host && builtins.isString realizationNode.host then
                  realizationNode.host
                else
                  throw ''
                    render-dry-config: unit '${unitName}' has no deployment host
                  '';

              attachMap = flake.lib.realizationPorts.attachMapForUnit {
                inherit inventory unitName;
                file = "render-dry-config";
              };

              hostBridgeNameMap =
                if builtins.hasAttr deploymentHostName normalizedHostRenderings then
                  normalizedHostRenderings.${deploymentHostName}.bridgeNameMap
                else
                  throw ''
                    render-dry-config: unit '${unitName}' references unknown host '${deploymentHostName}'
                  '';

              ports =
                builtins.listToAttrs (
                  map
                    (portName:
                      let
                        attachment = attachMap.${portName};
                        renderedHostBridgeName =
                          if builtins.hasAttr attachment.hostBridgeName hostBridgeNameMap then
                            hostBridgeNameMap.${attachment.hostBridgeName}
                          else
                            throw ''
                              render-dry-config: missing rendered bridge for '${attachment.hostBridgeName}' (unit ${unitName})
                            '';
                      in
                        {
                          name = portName;
                          value = {
                            attachment =
                              attachment
                              // {
                                inherit renderedHostBridgeName;
                              };
                          };
                        })
                    (sortedAttrNames attachMap)
                );
            in
              {
                name = unitName;
                value = {
                  inherit logicalNode deploymentHostName ports;
                };
              })
          (sortedAttrNames realizationNodes)
      );

  connectedHostNames =
    uniqueStrings (
      map
        (unitName:
          let
            n = realizationNodes.${unitName};
          in
            if n ? host && builtins.isString n.host then n.host else null)
        (sortedAttrNames realizationNodes)
    );

  legacyEnterpriseName =
    if builtins.length enterpriseNames == 1 then
      builtins.head enterpriseNames
    else
      null;

  legacySiteNames =
    if legacyEnterpriseName != null && builtins.hasAttr legacyEnterpriseName intent then
      sortedAttrNames (siteTreeForEnterprise intent.${legacyEnterpriseName})
    else
      [ ];

  legacySiteName =
    if builtins.length legacySiteNames == 1 then
      builtins.head legacySiteNames
    else
      null;

  legacySiteIntent =
    if legacyEnterpriseName != null
      && legacySiteName != null
      && builtins.hasAttr legacyEnterpriseName intent
      && builtins.hasAttr legacySiteName (siteTreeForEnterprise intent.${legacyEnterpriseName})
    then
      (siteTreeForEnterprise intent.${legacyEnterpriseName}).${legacySiteName}
    else
      { };

  legacyHostName = "legacy-fabric";

  legacyP2PLinks =
    if !useLegacyFabric then
      [ ]
    else
      uniqueStrings (
        builtins.concatLists (
          map
            (unitName:
              let
                node = inventory.fabric.${unitName};
                ports =
                  if node ? ports && builtins.isAttrs node.ports then
                    node.ports
                  else
                    { };
              in
                map
                  (portName:
                    let
                      port = ports.${portName};
                    in
                      if port ? kind
                        && builtins.isString port.kind
                        && port.kind == "p2p"
                        && port ? link
                        && builtins.isString port.link
                      then
                        port.link
                      else
                        null)
                  (sortedAttrNames ports))
            (sortedAttrNames inventory.fabric)
        )
      );

  legacyHostBridgeNameForLink =
    linkName:
    if legacyEnterpriseName != null && legacySiteName != null then
      "${legacyEnterpriseName}--${legacySiteName}--${linkName}"
    else
      linkName;

  legacyBridgeNameMap =
    if !useLegacyFabric then
      { }
    else
      builtins.listToAttrs (
        map
          (linkName:
            let
              hostBridgeName = legacyHostBridgeNameForLink linkName;
            in
              {
                name = hostBridgeName;
                value = shortenIfName hostBridgeName;
              })
          legacyP2PLinks
      );

  legacyHostRendering =
    if !useLegacyFabric then
      null
    else
      {
        bridgeNameMap = legacyBridgeNameMap;

        bridges =
          builtins.listToAttrs (
            map
              (linkName:
                let
                  hostBridgeName = legacyHostBridgeNameForLink linkName;
                in
                  {
                    name = hostBridgeName;
                    value = {
                      originalName = hostBridgeName;
                      renderedName = legacyBridgeNameMap.${hostBridgeName};
                    };
                  })
              legacyP2PLinks
          );

        netdevs =
          builtins.listToAttrs (
            map
              (linkName:
                let
                  hostBridgeName = legacyHostBridgeNameForLink linkName;
                  renderedName = legacyBridgeNameMap.${hostBridgeName};
                in
                  {
                    name = "10-${renderedName}";
                    value = {
                      netdevConfig = {
                        Kind = "bridge";
                        Name = renderedName;
                      };
                    };
                  })
              legacyP2PLinks
          );

        networks =
          builtins.listToAttrs (
            map
              (linkName:
                let
                  hostBridgeName = legacyHostBridgeNameForLink linkName;
                  renderedName = legacyBridgeNameMap.${hostBridgeName};
                in
                  {
                    name = "30-${renderedName}";
                    value = {
                      matchConfig = {
                        Name = renderedName;
                      };
                      networkConfig = {
                        ConfigureWithoutCarrier = true;
                      };
                    };
                  })
              legacyP2PLinks
          );
      };

  legacyRenderHosts =
    if !useLegacyFabric then
      { }
    else
      {
        "${legacyHostName}" = {
          network = {
            bridges = legacyHostRendering.bridges;
            netdevs = legacyHostRendering.netdevs;
            networks = legacyHostRendering.networks;
          };
        };
      };

  legacyLogicalNodeForUnit =
    unitName:
    let
      topologyNodes =
        if legacySiteIntent ? topology
          && builtins.isAttrs legacySiteIntent.topology
          && legacySiteIntent.topology ? nodes
          && builtins.isAttrs legacySiteIntent.topology.nodes
        then
          legacySiteIntent.topology.nodes
        else
          { };

      topoNode =
        if builtins.hasAttr unitName topologyNodes then
          topologyNodes.${unitName}
        else
          { };
    in
      {
        enterprise = legacyEnterpriseName;
        site = legacySiteName;
        name = unitName;
      }
      // (
        if topoNode ? role && builtins.isString topoNode.role then
          { role = topoNode.role; }
        else
          { }
      );

  legacyPortsForUnit =
    unitName:
    let
      node = inventory.fabric.${unitName};
      ports =
        if node ? ports && builtins.isAttrs node.ports then
          node.ports
        else
          { };

      p2pPortNames =
        builtins.filter
          (portName:
            let
              port = ports.${portName};
            in
              port ? kind
              && builtins.isString port.kind
              && port.kind == "p2p"
              && port ? link
              && builtins.isString port.link)
          (sortedAttrNames ports);
    in
      builtins.listToAttrs (
        map
          (portName:
            let
              port = ports.${portName};
              linkName = port.link;
              hostBridgeName = legacyHostBridgeNameForLink linkName;
            in
              {
                name = portName;
                value = {
                  attachment = {
                    hostBridgeName = hostBridgeName;
                    identity = {
                      attachmentKind = "direct";
                      enterprise = legacyEnterpriseName;
                      logicalName = unitName;
                      portName = portName;
                      site = legacySiteName;
                      unitName = unitName;
                    };
                    kind = "direct";
                    name = hostBridgeName;
                    originalName = linkName;
                    renderedHostBridgeName = legacyBridgeNameMap.${hostBridgeName};
                  };
                };
              })
          p2pPortNames
      );

  legacyRenderNodes =
    if !useLegacyFabric then
      { }
    else
      builtins.listToAttrs (
        map
          (unitName: {
            name = unitName;
            value = {
              logicalNode = legacyLogicalNodeForUnit unitName;
              deploymentHostName = legacyHostName;
              ports = legacyPortsForUnit unitName;
            };
          })
          (sortedAttrNames inventory.fabric)
      );

  effectiveHostRenderings =
    if useLegacyFabric then
      {
        "${legacyHostName}" = legacyHostRendering;
      }
    else
      normalizedHostRenderings;

  effectiveRenderHosts =
    if useLegacyFabric then
      legacyRenderHosts
    else
      normalizedRenderHosts;

  effectiveRenderNodes =
    if useLegacyFabric then
      legacyRenderNodes
    else
      normalizedRenderNodes;

  debugOutput = {
    inputs = {
      inherit intent inventory;
    };

    hardware = {
      inherit deploymentHosts;
    };

    realization = realizationNodes;

    portAttachTargets =
      if hasRealizationLayer then
        flake.lib.realizationPorts.attachMapForInventory {
          inherit inventory;
          file = "render-dry-config";
        }
      else
        { };

    inherit
      enterprises
      hasDeploymentHosts
      hasLegacyFabricLayer
      hasRealizationLayer
      useLegacyFabric
      connectedHostNames
      effectiveHostRenderings
      legacyEnterpriseName
      legacySiteName
      legacyP2PLinks
      ;
  };

  output =
    {
      metadata = {
        sourcePaths = {
          inherit repoRoot intentPath inventoryPath;
          exampleDir =
            if exampleDir != null then
              exampleDir
            else
              builtins.dirOf intentPath;
        };
      };

      render = {
        hosts = effectiveRenderHosts;
        nodes = effectiveRenderNodes;
      };
    }
    // (
      if debug then
        {
          debug = debugOutput;
        }
      else
        { }
    );

  validation =
    builtins.seq
      (
        if enterpriseNames == [ ] then
          throw "render-dry-config: empty intent"
        else
          null
      )
      (
        builtins.seq
          (
            if useLegacyFabric
              && (legacyEnterpriseName == null || legacySiteName == null)
            then
              throw ''
                render-dry-config: legacy fabric rendering requires exactly one enterprise and one site in intent

                enterprises: ${builtins.toJSON enterpriseNames}
                sites: ${builtins.toJSON legacySiteNames}
              ''
            else
              null
          )
          (
            builtins.seq
              (
                if !useLegacyFabric && !hasDeploymentHosts && !hasRealizationLayer then
                  throw ''
                    render-dry-config: no deployment hosts or realization nodes found
                  ''
                else
                  null
              )
              (
                builtins.seq
                  (
                    if hasRealizationLayer && connectedHostNames == [ ] then
                      throw "render-dry-config: no hosts referenced by realization"
                    else
                      null
                  )
                  (
                    builtins.seq
                      (
                        if hasRealizationLayer && realizationNodes == { } then
                          throw "render-dry-config: no nodes realized"
                        else
                          null
                      )
                      (
                        builtins.seq
                          (
                            if output.render.hosts == { } && output.render.nodes == { } then
                              throw "render-dry-config: empty render output"
                            else
                              null
                          )
                          true
                      )
                  )
              )
          )
      );
in
builtins.seq validation output
