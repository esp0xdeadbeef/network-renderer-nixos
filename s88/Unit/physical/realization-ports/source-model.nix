{ lib }:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  # NOTE: CMC-NIXOS-INTENT-CLEANUP: renamed from 'inventory' to 'source'.
  # Per SMS-100/SMS-101, renderers consume CPM output. This function accepts
  # any source container with a .realization.nodes structure — whether from
  # CPM (cpm.control_plane_model) or CPM-preserved inventory data.
  realizationNodesFor =
    source:
    if
      source ? realization
      && builtins.isAttrs source.realization
      && source.realization ? nodes
      && builtins.isAttrs source.realization.nodes
    then
      source.realization.nodes
    else
      { };

  logicalNodeForRealizationNode =
    node: if node ? logicalNode && builtins.isAttrs node.logicalNode then node.logicalNode else { };

  namespaceSegmentsForNode =
    node:
    let
      logicalNode = logicalNodeForRealizationNode node;
    in
    lib.filter builtins.isString [
      (logicalNode.site or null)
    ];

  namespacedDirectBridgeName =
    { node
    , linkName
    ,
    }:
    let
      namespaceSegments = namespaceSegmentsForNode node;
      segments = if namespaceSegments == [ ] then [ linkName ] else namespaceSegments ++ [ linkName ];
    in
    builtins.concatStringsSep "--" segments;

  nodeForUnit =
    { source
    , unitName
    , file ? "s88/Unit/physical/realization-ports.nix"
    ,
    }:
    let
      realizationNodes = realizationNodesFor source;
    in
    if builtins.hasAttr unitName realizationNodes && builtins.isAttrs realizationNodes.${unitName} then
      realizationNodes.${unitName}
    else
      throw ''
        ${file}: missing realization node for unit '${unitName}'

        known realization nodes:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ sortedAttrNames realizationNodes)}
      '';

  portsForUnit =
    { source
    , unitName
    , file ? "s88/Unit/physical/realization-ports.nix"
    ,
    }:
    let
      node = nodeForUnit {
        inherit source unitName file;
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
    { node
    , port
    , unitName ? "<unknown>"
    , portName ? "<unknown>"
    , file ? "s88/Unit/physical/realization-ports.nix"
    ,
    }:
    let
      attach = if port ? attach && builtins.isAttrs port.attach then port.attach else { };

      logicalNode = logicalNodeForRealizationNode node;

      logicalName =
        if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else unitName;

      site = if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;
    in
    if (attach.kind or null) == "bridge" && attach ? bridge && builtins.isString attach.bridge then
      {
        kind = "bridge";
        name = attach.bridge;
        originalName = attach.bridge;
        hostBridgeName = attach.bridge;
        identity = {
          inherit
            site
            logicalName
            unitName
            portName
            ;
          attachmentKind = "bridge";
        };
      }
    else if (attach.kind or null) == "direct" && port ? link && builtins.isString port.link then
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
          inherit
            site
            logicalName
            unitName
            portName
            ;
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
    { source
    , unitName
    , file ? "s88/Unit/physical/realization-ports.nix"
    ,
    }:
    let
      node = nodeForUnit {
        inherit source unitName file;
      };

      ports = portsForUnit {
        inherit source unitName file;
      };
    in
    builtins.listToAttrs (
      map
        (portName: {
          name = portName;
          value = attachForPort {
            inherit
              node
              unitName
              portName
              file
              ;
            port = ports.${portName};
          };
        })
        (sortedAttrNames ports)
    );

  attachMapForSource =
    { source
    , file ? "s88/Unit/physical/realization-ports.nix"
    ,
    }:
    let
      realizationNodes = realizationNodesFor source;
    in
    builtins.listToAttrs (
      map
        (unitName: {
          name = unitName;
          value = attachMapForUnit {
            inherit source unitName file;
          };
        })
        (sortedAttrNames realizationNodes)
    );

  # Legacy alias for backward compatibility (used by deployment-host.nix)
  attachMapForInventory = attachMapForSource;

  deploymentHostHelpers = import ./inventory/deployment-host.nix {
    inherit lib;
    helpers = {
      inherit
        attachMapForUnit
        realizationNodesFor
        sortedAttrNames
        ;
    };
  };
in
{
  inherit
    sortedAttrNames
    realizationNodesFor
    logicalNodeForRealizationNode
    nodeForUnit
    portsForUnit
    attachForPort
    attachMapForUnit
    attachMapForSource
    attachMapForInventory
    ;
  inherit (deploymentHostHelpers) unitNamesForDeploymentHost attachTargetsForDeploymentHost;
}
