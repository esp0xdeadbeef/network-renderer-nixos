{ lib, common, targets }:

let
  inherit (common) sortedAttrNames;
  inherit
    (targets)
    runtimeTargetIdForUnit
    logicalNodeForUnit
    ;

  # CMC-NIXOS-INTENT-CLEANUP: realizationNodesFor takes cpm or source, not inventory.
  # Per SMS-100/SMS-101, CPM is the sole data source. Inventory fallback removed.
  realizationNodesFor =
    { cpm ? null, source ? { } }:
    if
      cpm != null
      && builtins.isAttrs cpm
      && cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? realization
      && builtins.isAttrs cpm.control_plane_model.realization
      && builtins.isAttrs (cpm.control_plane_model.realization.nodes or null)
    then
      cpm.control_plane_model.realization.nodes
    else if cpm != null && builtins.isAttrs cpm && cpm ? realization && builtins.isAttrs cpm.realization && builtins.isAttrs (cpm.realization.nodes or null) then
      cpm.realization.nodes
    else if builtins.isAttrs source && source ? realization && builtins.isAttrs source.realization && builtins.isAttrs (source.realization.nodes or null) then
      source.realization.nodes
    else
      { };

  logicalNodeForRealizationNode =
    node: if node ? logicalNode && builtins.isAttrs node.logicalNode then node.logicalNode else { };
in
rec {
  inherit realizationNodesFor logicalNodeForRealizationNode;

  candidateRealizationNodeNamesForUnit =
    { cpm ? null, source ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      realizationNodes = realizationNodesFor { inherit cpm source; };
      runtimeTargetId = if cpm != null then runtimeTargetIdForUnit { inherit cpm source unitName file; } else null;
      logicalNode = if cpm != null then logicalNodeForUnit { inherit cpm source unitName file; } else { };
      logicalName = if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else null;
      logicalSite = if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;
      logicalEnterprise = if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then logicalNode.enterprise else null;
      exactNames = lib.unique (
        lib.filter (name: builtins.isString name && builtins.hasAttr name realizationNodes) [
          unitName
          runtimeTargetId
          logicalName
        ]
      );
      logicalMatches = lib.filter
        (
          nodeName:
          let nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
          in
          logicalName != null
          && (nodeLogical.name or null) == logicalName
          && (logicalSite == null || (nodeLogical.site or null) == logicalSite)
          && (logicalEnterprise == null || (nodeLogical.enterprise or null) == logicalEnterprise)
        )
        (sortedAttrNames realizationNodes);
      prefixMatches = lib.filter
        (
          nodeName:
          let nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
          in
          runtimeTargetId != null
          && lib.hasSuffix runtimeTargetId nodeName
          && (logicalSite == null || (nodeLogical.site or null) == logicalSite)
          && (logicalEnterprise == null || (nodeLogical.enterprise or null) == logicalEnterprise)
        )
        (sortedAttrNames realizationNodes);
    in
    lib.unique (exactNames ++ logicalMatches ++ prefixMatches);

  realizationNodeForUnit =
    { cpm ? null, source ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      realizationNodes = realizationNodesFor { inherit cpm source; };
      candidates = candidateRealizationNodeNamesForUnit { inherit cpm source unitName file; };
    in
    if builtins.hasAttr unitName realizationNodes && builtins.isAttrs realizationNodes.${unitName} then
      realizationNodes.${unitName}
    else if builtins.length candidates == 1 then
      realizationNodes.${builtins.head candidates}
    else if candidates == [ ] then
      null
    else
      throw ''
        ${file}: multiple realization nodes matched runtime unit '${unitName}'

        matching realization nodes:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ candidates)}
      '';

  realizationHostForUnit =
    { cpm ? null, source ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let node = realizationNodeForUnit { inherit cpm source unitName file; };
    in if node != null && node ? host && builtins.isString node.host then node.host else null;
}
