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
    in
    if (attach.kind or null) == "bridge"
      && attach ? bridge
      && builtins.isString attach.bridge
    then
      {
        kind = "bridge";
        name = attach.bridge;
      }
    else if (attach.kind or null) == "direct"
      && port ? link
      && builtins.isString port.link
    then
      {
        kind = "direct";
        name = port.link;
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
      ports = portsForUnit {
        inherit inventory unitName file;
      };
    in
    builtins.listToAttrs (
      map
        (portName: {
          name = portName;
          value = attachForPort {
            port = ports.${portName};
            inherit unitName portName file;
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

      attachTargetsByName =
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
                  name = attachMap.${portName}.name;
                  value = attachMap.${portName};
                })
                (sortedAttrNames attachMap))
            unitNames
        );
    in
    map
      (name: attachTargetsByName.${name})
      (sortedAttrNames attachTargetsByName);

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
