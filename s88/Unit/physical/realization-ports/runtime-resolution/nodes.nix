{ lib, inventoryModel, common }:

let
  inherit
    (inventoryModel)
    realizationNodesFor
    logicalNodeForRealizationNode
    ;
  inherit
    (common)
    sortedAttrNames
    runtimeTargetForUnitFromNormalized
    runtimeLogicalNodeForUnitFromNormalized
    ;

  runtimeTargetIdForUnitFromNormalized =
    { normalizedRuntimeTargets, unitName, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      runtimeTarget = runtimeTargetForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
      logicalNode = runtimeLogicalNodeForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
    in
    if runtimeTarget ? runtimeTargetId && builtins.isString runtimeTarget.runtimeTargetId then
      runtimeTarget.runtimeTargetId
    else if logicalNode ? name && builtins.isString logicalNode.name then
      logicalNode.name
    else
      unitName;

  nodeScopeMatchesRuntimeUnit =
    { normalizedRuntimeTargets, unitName, node, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      runtimeLogical = runtimeLogicalNodeForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
      nodeLogical = logicalNodeForRealizationNode node;
      runtimeSite = runtimeLogical.site or null;
      runtimeEnterprise = runtimeLogical.enterprise or null;
    in
    (runtimeSite == null || (nodeLogical.site or null) == runtimeSite)
    && (runtimeEnterprise == null || (nodeLogical.enterprise or null) == runtimeEnterprise);
in
{
  candidateRealizationNodeNamesForRuntimeUnit =
    { inventory, normalizedRuntimeTargets, unitName, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      realizationNodes = realizationNodesFor inventory;
      logicalNode = runtimeLogicalNodeForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
      logicalName = if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else null;
      logicalSite = if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;
      logicalEnterprise = if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then logicalNode.enterprise else null;
      runtimeTargetId = runtimeTargetIdForUnitFromNormalized { inherit normalizedRuntimeTargets unitName file; };
      exactNames = lib.unique (
        lib.filter (name: builtins.isString name && builtins.hasAttr name realizationNodes) [
          unitName
          runtimeTargetId
          logicalName
        ]
      );
      logicalMatches = lib.filter (
        nodeName:
        let
          nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
        in
        logicalName != null
        && (nodeLogical.name or null) == logicalName
        && (logicalSite == null || (nodeLogical.site or null) == logicalSite)
        && (logicalEnterprise == null || (nodeLogical.enterprise or null) == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);
      prefixMatches = lib.filter (
        nodeName:
        let
          nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
        in
        lib.hasSuffix nodeName runtimeTargetId
        && (logicalSite == null || (nodeLogical.site or null) == logicalSite)
        && (logicalEnterprise == null || (nodeLogical.enterprise or null) == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);
      candidateNames = lib.unique (exactNames ++ logicalMatches ++ prefixMatches);
    in
    if candidateNames != [ ] then
      candidateNames
    else
      throw ''
        ${file}: could not resolve candidate realization nodes for runtime unit '${unitName}'

        runtimeTargetId:
        ${builtins.toJSON runtimeTargetId}

        logicalNode:
        ${builtins.toJSON logicalNode}

        known realization nodes:
        ${builtins.toJSON (sortedAttrNames realizationNodes)}
      '';

  scopedNodeNamesForRuntimeUnit =
    { inventory, normalizedRuntimeTargets, unitName, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      realizationNodes = realizationNodesFor inventory;
      scopedNames = lib.filter (
        nodeName:
        nodeScopeMatchesRuntimeUnit {
          inherit normalizedRuntimeTargets unitName file;
          node = realizationNodes.${nodeName};
        }
      ) (sortedAttrNames realizationNodes);
    in
    if scopedNames != [ ] then scopedNames else sortedAttrNames realizationNodes;
}
