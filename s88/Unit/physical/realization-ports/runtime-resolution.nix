{ lib }:

let
  inventoryModel = import ./inventory.nix { inherit lib; };

  sortedAttrNames = inventoryModel.sortedAttrNames;
  realizationNodesFor = inventoryModel.realizationNodesFor;
  logicalNodeForRealizationNode = inventoryModel.logicalNodeForRealizationNode;
  attachForPort = inventoryModel.attachForPort;

  runtimeTargetForUnitFromNormalized =
    {
      normalizedRuntimeTargets,
      unitName,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}
    else
      throw ''
        ${file}: missing normalized runtime target for unit '${unitName}'
      '';

  runtimeLogicalNodeForUnitFromNormalized =
    {
      normalizedRuntimeTargets,
      unitName,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      runtimeTarget = runtimeTargetForUnitFromNormalized {
        inherit normalizedRuntimeTargets unitName file;
      };
    in
    if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
      runtimeTarget.logicalNode
    else
      { };

  runtimeTargetIdForUnitFromNormalized =
    {
      normalizedRuntimeTargets,
      unitName,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      runtimeTarget = runtimeTargetForUnitFromNormalized {
        inherit normalizedRuntimeTargets unitName file;
      };

      logicalNode = runtimeLogicalNodeForUnitFromNormalized {
        inherit normalizedRuntimeTargets unitName file;
      };
    in
    if runtimeTarget ? runtimeTargetId && builtins.isString runtimeTarget.runtimeTargetId then
      runtimeTarget.runtimeTargetId
    else if logicalNode ? name && builtins.isString logicalNode.name then
      logicalNode.name
    else
      unitName;

  lastStringSegment =
    separator: value:
    let
      pieces = lib.splitString separator value;
      count = builtins.length pieces;
    in
    if count == 0 then null else builtins.elemAt pieces (count - 1);

  collapseRepeatedTrailingDashSegment =
    value:
    let
      pieces = lib.splitString "-" value;
      count = builtins.length pieces;
      last = if count >= 1 then builtins.elemAt pieces (count - 1) else null;
      prev = if count >= 2 then builtins.elemAt pieces (count - 2) else null;
    in
    if count >= 2 && last == prev then
      builtins.concatStringsSep "-" (lib.take (count - 1) pieces)
    else
      value;

  candidateRealizationNodeNamesForRuntimeUnit =
    {
      inventory,
      normalizedRuntimeTargets,
      unitName,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      realizationNodes = realizationNodesFor inventory;

      logicalNode = runtimeLogicalNodeForUnitFromNormalized {
        inherit normalizedRuntimeTargets unitName file;
      };

      logicalName =
        if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else null;
      logicalSite =
        if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;
      logicalEnterprise =
        if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
          logicalNode.enterprise
        else
          null;

      runtimeTargetId = runtimeTargetIdForUnitFromNormalized {
        inherit normalizedRuntimeTargets unitName file;
      };

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
          nodeLogicalName = nodeLogical.name or null;
          nodeLogicalSite = nodeLogical.site or null;
          nodeLogicalEnterprise = nodeLogical.enterprise or null;
        in
        logicalName != null
        && nodeLogicalName == logicalName
        && (logicalSite == null || nodeLogicalSite == logicalSite)
        && (logicalEnterprise == null || nodeLogicalEnterprise == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);

      runtimeTargetPrefixMatches = lib.filter (
        nodeName:
        let
          nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
          nodeLogicalSite = nodeLogical.site or null;
          nodeLogicalEnterprise = nodeLogical.enterprise or null;
        in
        lib.hasSuffix nodeName runtimeTargetId
        && (logicalSite == null || nodeLogicalSite == logicalSite)
        && (logicalEnterprise == null || nodeLogicalEnterprise == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);

      candidateNames = lib.unique (exactNames ++ logicalMatches ++ runtimeTargetPrefixMatches);
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

  linkRefsForInterface =
    {
      backingRef,
    }:
    let
      idTail =
        if backingRef ? id && builtins.isString backingRef.id && lib.hasPrefix "link::" backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null;

      baseNames = lib.unique (
        lib.filter builtins.isString [
          (backingRef.name or null)
          idTail
        ]
      );
    in
    lib.unique (baseNames ++ map collapseRepeatedTrailingDashSegment baseNames);

  portMatchesLinkRefs =
    {
      port,
      linkRefs,
    }:
    builtins.elem (port.link or null) linkRefs;

  nodeScopeMatchesRuntimeUnit =
    {
      normalizedRuntimeTargets,
      unitName,
      node,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      runtimeLogical = runtimeLogicalNodeForUnitFromNormalized {
        inherit normalizedRuntimeTargets unitName file;
      };

      nodeLogical = logicalNodeForRealizationNode node;

      runtimeSite = runtimeLogical.site or null;
      runtimeEnterprise = runtimeLogical.enterprise or null;
    in
    (runtimeSite == null || (nodeLogical.site or null) == runtimeSite)
    && (runtimeEnterprise == null || (nodeLogical.enterprise or null) == runtimeEnterprise);

  scopedNodeNamesForRuntimeUnit =
    {
      inventory,
      normalizedRuntimeTargets,
      unitName,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      realizationNodes = realizationNodesFor inventory;

      scopedNames = lib.filter (
        nodeName:
        nodeScopeMatchesRuntimeUnit {
          inherit
            normalizedRuntimeTargets
            unitName
            file
            ;
          node = realizationNodes.${nodeName};
        }
      ) (sortedAttrNames realizationNodes);
    in
    if scopedNames != [ ] then scopedNames else sortedAttrNames realizationNodes;

  linkPortMatchesOnNodeNames =
    {
      inventory,
      nodeNames,
      linkRefs,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
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
          inherit
            nodeName
            node
            portName
            ;
          port = ports.${portName};
        })
        (
          lib.filter (
            portName:
            let
              port = ports.${portName};
            in
            portMatchesLinkRefs {
              inherit port linkRefs;
            }
          ) (sortedAttrNames ports)
        )
    ) nodeNames;

  linkPortMatchesForRuntimeInterface =
    {
      inventory,
      normalizedRuntimeTargets,
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
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

      linkRefs = linkRefsForInterface {
        inherit backingRef;
      };

      candidateNodeNames = candidateRealizationNodeNamesForRuntimeUnit {
        inherit
          inventory
          normalizedRuntimeTargets
          unitName
          file
          ;
      };

      scopedNodeNames = scopedNodeNamesForRuntimeUnit {
        inherit
          inventory
          normalizedRuntimeTargets
          unitName
          file
          ;
      };

      globalNodeNames = sortedAttrNames (realizationNodesFor inventory);

      localMatches = linkPortMatchesOnNodeNames {
        inherit inventory file linkRefs;
        nodeNames = candidateNodeNames;
      };

      scopedMatches =
        if localMatches != [ ] then
          [ ]
        else
          linkPortMatchesOnNodeNames {
            inherit inventory file linkRefs;
            nodeNames = scopedNodeNames;
          };

      globalMatches =
        if localMatches != [ ] || scopedMatches != [ ] then
          [ ]
        else
          linkPortMatchesOnNodeNames {
            inherit inventory file linkRefs;
            nodeNames = globalNodeNames;
          };
    in
    if backingRefKind != "link" then
      [ ]
    else if localMatches != [ ] then
      localMatches
    else if scopedMatches != [ ] then
      scopedMatches
    else
      globalMatches;

  resolvePortForRuntimeInterface =
    {
      inventory,
      normalizedRuntimeTargets,
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      backingRef = iface.backingRef or { };

      backingRefKind =
        if backingRef ? kind && builtins.isString backingRef.kind then
          backingRef.kind
        else
          throw ''
            ${file}: interface '${ifName}' for unit '${unitName}' is missing backingRef.kind

            interface:
            ${builtins.toJSON iface}
          '';

      matches = linkPortMatchesForRuntimeInterface {
        inherit
          inventory
          normalizedRuntimeTargets
          unitName
          ifName
          iface
          file
          ;
      };

      candidateNodeNames =
        if backingRefKind == "link" then
          candidateRealizationNodeNamesForRuntimeUnit {
            inherit
              inventory
              normalizedRuntimeTargets
              unitName
              file
              ;
          }
        else
          [ ];

      scopedNodeNames =
        if backingRefKind == "link" then
          scopedNodeNamesForRuntimeUnit {
            inherit
              inventory
              normalizedRuntimeTargets
              unitName
              file
              ;
          }
        else
          [ ];
    in
    if backingRefKind != "link" then
      null
    else if builtins.length matches == 1 then
      builtins.head matches
    else if matches == [ ] then
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
        ${builtins.toJSON (
          map (match: {
            nodeName = match.nodeName;
            portName = match.portName;
            link = match.port.link or null;
          }) matches
        )}
      '';

  tryResolvePortForRuntimeInterface =
    args:
    let
      attempt = builtins.tryEval (resolvePortForRuntimeInterface args);
    in
    if attempt.success then attempt.value else null;

  attachTargetForRuntimeInterface =
    {
      inventory,
      normalizedRuntimeTargets,
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      resolvedPort = tryResolvePortForRuntimeInterface {
        inherit
          inventory
          normalizedRuntimeTargets
          unitName
          ifName
          iface
          file
          ;
      };

      attachTarget =
        if resolvedPort == null then
          null
        else
          attachForPort {
            inherit
              file
              unitName
              ;
            node = resolvedPort.node;
            portName = resolvedPort.portName;
            port = resolvedPort.port;
          };
    in
    if attachTarget == null then
      null
    else
      attachTarget
      // {
        inherit unitName ifName;
        renderedIfName = iface.renderedIfName or null;
        interface = iface;
        connectivity = iface.connectivity or { };
        backingRef = iface.backingRef or { };
        realizationNodeName = resolvedPort.nodeName;
      };

  fallbackAttachTargetForRuntimeInterface =
    {
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    let
      hostBridgeName =
        if iface ? hostBridge && builtins.isString iface.hostBridge then
          iface.hostBridge
        else
          throw ''
            ${file}: normalized interface '${ifName}' for unit '${unitName}' is missing hostBridge

            interface:
            ${builtins.toJSON iface}
          '';
    in
    {
      inherit unitName ifName hostBridgeName;
      renderedIfName = iface.renderedIfName or null;
      interface = iface;
      connectivity = iface.connectivity or { };
      backingRef = iface.backingRef or { };
      kind = "synthetic";
      name = hostBridgeName;
      originalName = hostBridgeName;
      identity = {
        unitName = unitName;
        portName = ifName;
        attachmentKind = "synthetic";
      };
    };

  attachTargetsForUnitsFromRuntime =
    {
      inventory ? { },
      selectedUnits,
      normalizedRuntimeTargets,
      file ? "s88/Unit/physical/realization-ports.nix",
    }:
    lib.concatMap (
      unitName:
      let
        runtimeTarget = runtimeTargetForUnitFromNormalized {
          inherit normalizedRuntimeTargets unitName file;
        };

        interfaces =
          if runtimeTarget ? interfaces && builtins.isAttrs runtimeTarget.interfaces then
            runtimeTarget.interfaces
          else
            { };
      in
      map (
        ifName:
        let
          iface = interfaces.${ifName};

          authoritativeTarget =
            if inventory == { } then
              null
            else
              attachTargetForRuntimeInterface {
                inherit
                  inventory
                  normalizedRuntimeTargets
                  unitName
                  ifName
                  iface
                  file
                  ;
              };
        in
        if authoritativeTarget != null then
          authoritativeTarget
        else
          fallbackAttachTargetForRuntimeInterface {
            inherit
              unitName
              ifName
              iface
              file
              ;
          }
      ) (sortedAttrNames interfaces)
    ) selectedUnits;
in
{
  inherit attachTargetsForUnitsFromRuntime;
}
