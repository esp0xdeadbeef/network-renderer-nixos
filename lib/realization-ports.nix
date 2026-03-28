{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  realizationNodesFor = inventory:
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  logicalNodeForRealizationNode = node:
    if node ? logicalNode && builtins.isAttrs node.logicalNode then
      node.logicalNode
    else
      { };

  namespaceSegmentsForNode = node:
    let
      logicalNode = logicalNodeForRealizationNode node;
    in
    lib.filter
      builtins.isString
      [
        (logicalNode.enterprise or null)
        (logicalNode.site or null)
      ];

  namespacedDirectBridgeName =
    {
      node,
      linkName,
    }:
    let
      namespaceSegments = namespaceSegmentsForNode node;
      segments =
        if namespaceSegments == [ ] then
          [ linkName ]
        else
          namespaceSegments ++ [ linkName ];
    in
    builtins.concatStringsSep "--" segments;

  nodeForUnit =
    {
      inventory,
      unitName,
      file ? "lib/realization-ports.nix",
    }:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    if builtins.hasAttr unitName realizationNodes
      && builtins.isAttrs realizationNodes.${unitName}
    then
      realizationNodes.${unitName}
    else
      throw ''
        ${file}: missing realization node for unit '${unitName}'

        known realization nodes:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ sortedAttrNames realizationNodes)}
      '';

  portsForUnit =
    {
      inventory,
      unitName,
      file ? "lib/realization-ports.nix",
    }:
    let
      node = nodeForUnit {
        inherit inventory unitName file;
      };
    in
    if node ? ports && builtins.isAttrs node.ports then
      node.ports
    else
      throw ''
        ${file}: realization node '${unitName}' is missing ports

        node:
        ${builtins.toJSON node}
      '';

  attachForPort =
    {
      node,
      port,
      unitName ? "<unknown>",
      portName ? "<unknown>",
      file ? "lib/realization-ports.nix",
    }:
    let
      attach =
        if port ? attach && builtins.isAttrs port.attach then
          port.attach
        else
          { };

      logicalNode = logicalNodeForRealizationNode node;

      logicalName =
        if logicalNode ? name && builtins.isString logicalNode.name then
          logicalNode.name
        else
          unitName;

      enterprise =
        if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
          logicalNode.enterprise
        else
          null;

      site =
        if logicalNode ? site && builtins.isString logicalNode.site then
          logicalNode.site
        else
          null;
    in
    if (attach.kind or null) == "bridge"
      && attach ? bridge
      && builtins.isString attach.bridge
    then
      {
        kind = "bridge";
        name = attach.bridge;
        originalName = attach.bridge;
        hostBridgeName = attach.bridge;
        identity = {
          inherit enterprise site logicalName unitName portName;
          attachmentKind = "bridge";
        };
      }
    else if (attach.kind or null) == "direct"
      && port ? link
      && builtins.isString port.link
    then
      let
        hostBridgeName = namespacedDirectBridgeName {
          inherit node;
          linkName = port.link;
        };
      in
      {
        kind = "direct";
        name = hostBridgeName;
        originalName = port.link;
        hostBridgeName = hostBridgeName;
        identity = {
          inherit enterprise site logicalName unitName portName;
          attachmentKind = "direct";
        };
      }
    else
      throw ''
        ${file}: could not resolve attach target for unit '${unitName}', port '${portName}'

        port:
        ${builtins.toJSON port}
      '';

  attachMapForUnit =
    {
      inventory,
      unitName,
      file ? "lib/realization-ports.nix",
    }:
    let
      node = nodeForUnit {
        inherit inventory unitName file;
      };

      ports = portsForUnit {
        inherit inventory unitName file;
      };
    in
    builtins.listToAttrs (
      map
        (portName: {
          name = portName;
          value = attachForPort {
            inherit node unitName portName file;
            port = ports.${portName};
          };
        })
        (sortedAttrNames ports)
    );

  attachMapForInventory =
    {
      inventory,
      file ? "lib/realization-ports.nix",
    }:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    builtins.listToAttrs (
      map
        (unitName: {
          name = unitName;
          value = attachMapForUnit {
            inherit inventory unitName file;
          };
        })
        (sortedAttrNames realizationNodes)
    );

  unitNamesForDeploymentHost =
    {
      inventory,
      deploymentHostName,
    }:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    lib.filter
      (unitName:
        let
          node = realizationNodes.${unitName};
        in
        (node.host or null) == deploymentHostName)
      (sortedAttrNames realizationNodes);

  attachTargetsForDeploymentHost =
    {
      inventory,
      deploymentHostName,
      file ? "lib/realization-ports.nix",
    }:
    let
      unitNames = unitNamesForDeploymentHost {
        inherit inventory deploymentHostName;
      };

      attachTargetsByHostBridgeName =
        builtins.listToAttrs (
          lib.concatMap
            (unitName:
              let
                attachMap = attachMapForUnit {
                  inherit inventory unitName file;
                };
              in
              map
                (portName: {
                  name = attachMap.${portName}.hostBridgeName;
                  value = attachMap.${portName};
                })
                (sortedAttrNames attachMap))
            unitNames
        );
    in
    map
      (hostBridgeName: attachTargetsByHostBridgeName.${hostBridgeName})
      (sortedAttrNames attachTargetsByHostBridgeName);

in
{
  inherit
    realizationNodesFor
    nodeForUnit
    portsForUnit
    attachForPort
    attachMapForUnit
    attachMapForInventory
    unitNamesForDeploymentHost
    attachTargetsForDeploymentHost
    ;
}
