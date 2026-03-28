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

  realizationNodes = flake.lib.realizationPorts.realizationNodesFor inventory;

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

  hostRenderings =
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

  renderHosts =
    builtins.listToAttrs (
      map
        (hostName:
          let
            hostRendering = hostRenderings.${hostName};
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
        (sortedAttrNames hostRenderings)
    );

  renderNodes =
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
                null;

            attachMap = flake.lib.realizationPorts.attachMapForUnit {
              inherit inventory unitName;
              file = "render-dry-config";
            };

            hostBridgeNameMap =
              if deploymentHostName != null && builtins.hasAttr deploymentHostName hostRenderings then
                hostRenderings.${deploymentHostName}.bridgeNameMap
              else
                { };

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
                          null;
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

  debugOutput = {
    inputs = {
      inherit intent inventory;
    };

    hardware = {
      inherit deploymentHosts;
    };

    realization = realizationNodes;

    portAttachTargets = flake.lib.realizationPorts.attachMapForInventory {
      inherit inventory;
      file = "render-dry-config";
    };

    inherit enterprises hostRenderings;
  };
in
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
    hosts = renderHosts;
    nodes = renderNodes;
  };
}
// (
  if debug then
    {
      debug = debugOutput;
    }
  else
    { }
)
