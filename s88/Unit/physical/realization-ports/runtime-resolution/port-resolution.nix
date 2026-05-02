{ lib, inventoryModel, nodes, linkMatches }:

let
  inherit (inventoryModel) realizationNodesFor sortedAttrNames;

  directPortMatchesOnNodeNames =
    { inventory, nodeNames, ifName }:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    lib.concatMap (
      nodeName:
      let
        node = realizationNodes.${nodeName};
        ports = if node ? ports && builtins.isAttrs node.ports then node.ports else { };
      in
      lib.concatMap (
        portName:
        let
          port = ports.${portName};
          portIfName = if port ? interface && builtins.isAttrs port.interface then port.interface.name or null else null;
          portLogicalIf = port.logicalInterface or null;
        in
        if portName == ifName || portIfName == ifName || portLogicalIf == ifName then
          [ { inherit nodeName node portName port; } ]
        else
          [ ]
      ) (sortedAttrNames ports)
    ) nodeNames;
in
{
  resolvePortForRuntimeInterface =
    { inventory, normalizedRuntimeTargets, unitName, ifName, iface, file ? "s88/Unit/physical/realization-ports.nix" }:
    let
      backingRef = iface.backingRef or { };
      backingRefKind =
        if backingRef ? kind && builtins.isString backingRef.kind then
          backingRef.kind
        else
          throw ''
            ${file}: interface '${ifName}' for runtime unit '${unitName}' is missing backingRef.kind

            interface:
            ${builtins.toJSON iface}
          '';
      candidateNodeNames = nodes.candidateRealizationNodeNamesForRuntimeUnit { inherit inventory normalizedRuntimeTargets unitName file; };
      scopedNodeNames = nodes.scopedNodeNamesForRuntimeUnit { inherit inventory normalizedRuntimeTargets unitName file; };
      globalNodeNames = sortedAttrNames (realizationNodesFor inventory);
      directLocal = directPortMatchesOnNodeNames { inherit inventory ifName; nodeNames = candidateNodeNames; };
      directScoped = if directLocal != [ ] then [ ] else directPortMatchesOnNodeNames { inherit inventory ifName; nodeNames = scopedNodeNames; };
      directGlobal = if directLocal != [ ] || directScoped != [ ] then [ ] else directPortMatchesOnNodeNames { inherit inventory ifName; nodeNames = globalNodeNames; };
      directMatches = if directLocal != [ ] then directLocal else if directScoped != [ ] then directScoped else directGlobal;
      linkMatches' =
        if backingRefKind == "link" then
          linkMatches.linkPortMatchesForRuntimeInterface { inherit inventory normalizedRuntimeTargets unitName ifName iface file; }
        else
          [ ];
    in
    if backingRefKind == "link" then
      if builtins.length linkMatches' == 1 then
        builtins.head linkMatches'
      else if linkMatches' == [ ] then
        throw ''
          ${file}: interface '${ifName}' for runtime unit '${unitName}' could not resolve a realization port from backingRef

          backingRef:
          ${builtins.toJSON backingRef}

          candidate realization nodes:
          ${builtins.toJSON candidateNodeNames}

          scoped realization nodes:
          ${builtins.toJSON scopedNodeNames}
        ''
      else
        throw ''
          ${file}: interface '${ifName}' for runtime unit '${unitName}' matched multiple realization ports

          backingRef:
          ${builtins.toJSON backingRef}

          matches:
          ${builtins.toJSON (map (match: { nodeName = match.nodeName; portName = match.portName; link = match.port.link or null; }) linkMatches')}
        ''
    else if builtins.length directMatches == 1 then
      builtins.head directMatches
    else if directMatches == [ ] then
      null
    else
      throw ''
        ${file}: interface '${ifName}' for runtime unit '${unitName}' matched multiple realization ports (direct name match)

        backingRef:
        ${builtins.toJSON backingRef}

        matches:
        ${builtins.toJSON (
          map (match: {
            nodeName = match.nodeName;
            portName = match.portName;
            logicalInterface = match.port.logicalInterface or null;
            ifName = if match.port ? interface && builtins.isAttrs match.port.interface then match.port.interface.name or null else null;
          }) directMatches
        )}
      '';
}
