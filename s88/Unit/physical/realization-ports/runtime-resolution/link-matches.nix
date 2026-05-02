{ lib, inventoryModel, common, nodes }:

let
  inherit (inventoryModel) realizationNodesFor;
  inherit (common) sortedAttrNames lastStringSegment collapseRepeatedTrailingDashSegment;

  linkRefsForInterface =
    { backingRef }:
    let
      idTail =
        if backingRef ? id && builtins.isString backingRef.id && lib.hasPrefix "link::" backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null;
      baseNames = lib.unique (lib.filter builtins.isString [ (backingRef.name or null) idTail ]);
    in
    lib.unique (baseNames ++ map collapseRepeatedTrailingDashSegment baseNames);

  portMatchesLinkRefs = { port, linkRefs }: builtins.elem (port.link or null) linkRefs;

  linkPortMatchesOnNodeNames =
    { inventory, nodeNames, linkRefs, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    lib.concatMap (
      nodeName:
      let
        node = realizationNodes.${nodeName};
        ports =
          if node ? ports && builtins.isAttrs node.ports then
            node.ports
          else
            throw ''
              ${file}: realization node '${nodeName}' is missing ports

              node:
              ${builtins.toJSON node}
            '';
      in
      map
        (portName: {
          inherit nodeName node portName;
          port = ports.${portName};
        })
        (
          lib.filter (
            portName:
            portMatchesLinkRefs {
              port = ports.${portName};
              inherit linkRefs;
            }
          ) (sortedAttrNames ports)
        )
    ) nodeNames;
in
{
  linkPortMatchesForRuntimeInterface =
    { inventory, normalizedRuntimeTargets, unitName, ifName, iface, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      backingRef =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then
          iface.backingRef
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef

            interface:
            ${builtins.toJSON iface}
          '';
      backingRefKind =
        if backingRef ? kind && builtins.isString backingRef.kind then
          backingRef.kind
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef.kind

            interface:
            ${builtins.toJSON iface}
          '';
      linkRefs = linkRefsForInterface { inherit backingRef; };
      candidateNodeNames = nodes.candidateRealizationNodeNamesForRuntimeUnit { inherit inventory normalizedRuntimeTargets unitName file; };
      scopedNodeNames = nodes.scopedNodeNamesForRuntimeUnit { inherit inventory normalizedRuntimeTargets unitName file; };
      globalNodeNames = sortedAttrNames (realizationNodesFor inventory);
      localMatches = linkPortMatchesOnNodeNames { inherit inventory file linkRefs; nodeNames = candidateNodeNames; };
      scopedMatches = if localMatches != [ ] then [ ] else linkPortMatchesOnNodeNames { inherit inventory file linkRefs; nodeNames = scopedNodeNames; };
      globalMatches = if localMatches != [ ] || scopedMatches != [ ] then [ ] else linkPortMatchesOnNodeNames { inherit inventory file linkRefs; nodeNames = globalNodeNames; };
    in
    if backingRefKind != "link" then
      [ ]
    else if localMatches != [ ] then
      localMatches
    else if scopedMatches != [ ] then
      scopedMatches
    else
      globalMatches;
}
