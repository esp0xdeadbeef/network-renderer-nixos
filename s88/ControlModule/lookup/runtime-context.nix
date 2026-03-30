{ lib }:

let
  hostQuery = import ./host-query.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  controlPlaneData =
    cpm:
    if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? data
      && builtins.isAttrs cpm.control_plane_model.data
    then
      cpm.control_plane_model.data
    else if cpm ? data && builtins.isAttrs cpm.data then
      cpm.data
    else
      { };

  siteTreeFromRoot =
    rootValue:
    if rootValue ? site && builtins.isAttrs rootValue.site then
      rootValue.site
    else if builtins.isAttrs rootValue then
      rootValue
    else
      { };

  siteEntries =
    cpm:
    let
      cpmData = controlPlaneData cpm;
    in
    lib.concatMap (
      rootName:
      let
        siteTree = siteTreeFromRoot cpmData.${rootName};
      in
      map (siteName: {
        inherit rootName siteName;
        site = siteTree.${siteName};
      }) (sortedAttrNames siteTree)
    ) (sortedAttrNames cpmData);

  runtimeTargetAttrNamesForEntry =
    entry:
    if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
      sortedAttrNames entry.site.runtimeTargets
    else
      [ ];

  runtimeTargetInstanceId =
    {
      rootName,
      siteName,
      unitName,
    }:
    builtins.concatStringsSep "::" (
      lib.filter builtins.isString [
        rootName
        siteName
        unitName
      ]
    );

  runtimeTargetEntries =
    cpm:
    lib.concatMap (
      entry:
      map (
        unitName:
        entry
        // {
          inherit unitName;
          runtimeTarget = entry.site.runtimeTargets.${unitName};
          instanceId = runtimeTargetInstanceId {
            inherit (entry) rootName siteName;
            inherit unitName;
          };
        }
      ) (runtimeTargetAttrNamesForEntry entry)
    ) (siteEntries cpm);

  runtimeTargetEntriesById =
    cpm:
    builtins.listToAttrs (
      map (entry: {
        name = entry.instanceId;
        value = entry;
      }) (runtimeTargetEntries cpm)
    );

  runtimeTargetEntriesForRawUnitName =
    {
      cpm,
      unitName,
    }:
    lib.filter (entry: entry.unitName == unitName) (runtimeTargetEntries cpm);

  runtimeTargetEntryForUnit =
    {
      cpm,
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      byId = runtimeTargetEntriesById cpm;
      rawMatches = runtimeTargetEntriesForRawUnitName {
        inherit cpm unitName;
      };
    in
    if builtins.hasAttr unitName byId then
      byId.${unitName}
    else if builtins.length rawMatches == 1 then
      builtins.head rawMatches
    else if rawMatches == [ ] then
      throw ''
        ${file}: missing runtime target for unit '${unitName}'

        known runtime target instances:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ (sortedAttrNames byId))}
      ''
    else
      throw ''
        ${file}: multiple runtime target instances matched legacy unit name '${unitName}'

        matching runtime target instances:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ (map (entry: entry.instanceId) rawMatches))}
      '';

  runtimeTargetIdForEntry =
    entry:
    let
      target = entry.runtimeTarget;
    in
    if target ? runtimeTargetId && builtins.isString target.runtimeTargetId then
      target.runtimeTargetId
    else if
      target ? logicalNode
      && builtins.isAttrs target.logicalNode
      && target.logicalNode ? name
      && builtins.isString target.logicalNode.name
    then
      target.logicalNode.name
    else
      entry.unitName;

  runtimeTargets =
    cpm: builtins.mapAttrs (_: entry: entry.runtimeTarget) (runtimeTargetEntriesById cpm);

  siteEntryForUnit =
    {
      cpm,
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      entry = runtimeTargetEntryForUnit {
        inherit cpm unitName file;
      };
    in
    {
      inherit (entry)
        rootName
        siteName
        site
        unitName
        instanceId
        runtimeTarget
        ;
    };

  runtimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    (runtimeTargetEntryForUnit {
      inherit cpm unitName file;
    }).runtimeTarget;

  logicalNodeForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };
    in
    if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  runtimeTargetIdForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      entry = runtimeTargetEntryForUnit {
        inherit cpm unitName file;
      };
    in
    runtimeTargetIdForEntry entry;

  logicalNodeNameForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      logicalNode = logicalNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      runtimeTargetId = runtimeTargetIdForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    if logicalNode ? name && builtins.isString logicalNode.name then
      logicalNode.name
    else
      runtimeTargetId;

  logicalNodeIdentityForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      entry = runtimeTargetEntryForUnit {
        inherit cpm unitName file;
      };

      logicalNode = logicalNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      siteName =
        if logicalNode ? site && builtins.isString logicalNode.site then
          logicalNode.site
        else
          entry.siteName or null;

      identityName =
        if logicalNode ? name && builtins.isString logicalNode.name then
          logicalNode.name
        else
          runtimeTargetIdForEntry entry;

      segments = lib.filter builtins.isString [
        entry.rootName
        siteName
        identityName
      ];
    in
    if segments != [ ] then builtins.concatStringsSep "::" segments else unitName;

  roleForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode = logicalNodeForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    if target ? role && builtins.isString target.role then target.role else logicalNode.role or null;

  realizationNodeForUnit =
    {
      inventory ? { },
      unitName,
    }:
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
      && builtins.hasAttr unitName inventory.realization.nodes
      && builtins.isAttrs inventory.realization.nodes.${unitName}
    then
      inventory.realization.nodes.${unitName}
    else
      null;

  realizationHostForUnit =
    {
      inventory ? { },
      unitName,
    }:
    let
      node = realizationNodeForUnit {
        inherit inventory unitName;
      };
    in
    if node != null && node ? host && builtins.isString node.host then node.host else null;

  deploymentHostForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      placement =
        if target ? placement then
          if builtins.isAttrs target.placement then
            target.placement
          else
            throw ''
              ${file}: runtime target for unit '${unitName}' has non-attr placement

              runtime target:
              ${builtins.toJSON target}
            ''
        else
          throw ''
            ${file}: runtime target for unit '${unitName}' is missing placement

            runtime target:
            ${builtins.toJSON target}
          '';

      runtimeTargetId = runtimeTargetIdForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      logicalNodeName = logicalNodeNameForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      fallbackHost =
        if target ? runtimeTargetId && builtins.isString target.runtimeTargetId then
          target.runtimeTargetId
        else if logicalNodeName != null then
          logicalNodeName
        else
          unitName;

      placementHost =
        if !(placement ? host) || placement.host == null then
          null
        else if builtins.isString placement.host then
          placement.host
        else
          throw ''
            ${file}: runtime target for unit '${unitName}' has non-string placement.host

            runtime target:
            ${builtins.toJSON target}
          '';

      resolveCandidate =
        candidate:
        if candidate == null || !builtins.isString candidate || inventory == { } then
          null
        else
          let
            attempt = builtins.tryEval (
              hostQuery.resolveDeploymentHostName {
                inherit inventory file;
                hostname = candidate;
              }
            );
          in
          if attempt.success && builtins.isString attempt.value then attempt.value else null;

      resolvedViaInventory =
        if placementHost != null then
          null
        else
          let
            fromUnitName = resolveCandidate unitName;
            fromRuntimeTargetId = if fromUnitName != null then null else resolveCandidate runtimeTargetId;
            fromLogicalNodeName =
              if fromUnitName != null || fromRuntimeTargetId != null then
                null
              else
                resolveCandidate logicalNodeName;
            fromFallbackHost =
              if fromUnitName != null || fromRuntimeTargetId != null || fromLogicalNodeName != null then
                null
              else
                resolveCandidate fallbackHost;
            fromRealizationHost =
              if
                fromUnitName != null
                || fromRuntimeTargetId != null
                || fromLogicalNodeName != null
                || fromFallbackHost != null
              then
                null
              else
                realizationHostForUnit {
                  inherit inventory unitName;
                };
          in
          if fromUnitName != null then
            fromUnitName
          else if fromRuntimeTargetId != null then
            fromRuntimeTargetId
          else if fromLogicalNodeName != null then
            fromLogicalNodeName
          else if fromFallbackHost != null then
            fromFallbackHost
          else
            fromRealizationHost;
    in
    if placementHost != null then
      placementHost
    else if resolvedViaInventory != null then
      resolvedViaInventory
    else
      fallbackHost;

  emittedInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      effectiveRuntimeRealization =
        if target ? effectiveRuntimeRealization && builtins.isAttrs target.effectiveRuntimeRealization then
          target.effectiveRuntimeRealization
        else
          throw ''
            ${file}: runtime target for unit '${unitName}' is missing effectiveRuntimeRealization

            runtime target:
            ${builtins.toJSON target}
          '';
    in
    if
      effectiveRuntimeRealization ? interfaces && builtins.isAttrs effectiveRuntimeRealization.interfaces
    then
      effectiveRuntimeRealization.interfaces
    else
      throw ''
        ${file}: runtime target for unit '${unitName}' is missing effectiveRuntimeRealization.interfaces

        runtime target:
        ${builtins.toJSON target}
      '';

  validateStringField =
    {
      value,
      fieldName,
      unitName,
      ifName ? null,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
      context ? { },
    }:
    if builtins.isString value then
      true
    else
      throw ''
        ${file}: expected string field '${fieldName}'${
          if ifName != null then " on interface '${ifName}'" else ""
        } for unit '${unitName}'

        context:
        ${builtins.toJSON context}
      '';

  validateOptionalStringOrListField =
    {
      value,
      fieldName,
      unitName,
      ifName ? null,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
      context ? { },
    }:
    if value == null || builtins.isString value || builtins.isList value then
      true
    else
      throw ''
        ${file}: expected string-or-list field '${fieldName}'${
          if ifName != null then " on interface '${ifName}'" else ""
        } for unit '${unitName}'

        context:
        ${builtins.toJSON context}
      '';

  validateOptionalAttrField =
    {
      value,
      fieldName,
      unitName,
      ifName ? null,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
      context ? { },
    }:
    if value == null || builtins.isAttrs value then
      true
    else
      throw ''
        ${file}: expected attr field '${fieldName}'${
          if ifName != null then " on interface '${ifName}'" else ""
        } for unit '${unitName}'

        context:
        ${builtins.toJSON context}
      '';

  validateInterfaceForUnit =
    {
      unitName,
      ifName,
      iface,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
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

      _validateRenderedIfName = validateStringField {
        value = iface.renderedIfName or null;
        fieldName = "renderedIfName";
        inherit unitName ifName file;
        context = iface;
      };

      _validateBackingRefId = validateStringField {
        value = backingRef.id or null;
        fieldName = "backingRef.id";
        inherit unitName ifName file;
        context = iface;
      };

      _validateBackingRefKind = validateStringField {
        value = backingRef.kind or null;
        fieldName = "backingRef.kind";
        inherit unitName ifName file;
        context = iface;
      };

      _validateSourceKind = validateStringField {
        value = iface.sourceKind or null;
        fieldName = "sourceKind";
        inherit unitName ifName file;
        context = iface;
      };

      _validateAddr4 = validateOptionalStringOrListField {
        value = iface.addr4 or null;
        fieldName = "addr4";
        inherit unitName ifName file;
        context = iface;
      };

      _validateAddr6 = validateOptionalStringOrListField {
        value = iface.addr6 or null;
        fieldName = "addr6";
        inherit unitName ifName file;
        context = iface;
      };

      _validateRoutes = validateOptionalAttrField {
        value = iface.routes or { };
        fieldName = "routes";
        inherit unitName ifName file;
        context = iface;
      };

      _validateRoutesIpv4 = validateOptionalStringOrListField {
        value = if iface ? routes && builtins.isAttrs iface.routes then iface.routes.ipv4 or [ ] else [ ];
        fieldName = "routes.ipv4";
        inherit unitName ifName file;
        context = iface;
      };

      _validateRoutesIpv6 = validateOptionalStringOrListField {
        value = if iface ? routes && builtins.isAttrs iface.routes then iface.routes.ipv6 or [ ] else [ ];
        fieldName = "routes.ipv6";
        inherit unitName ifName file;
        context = iface;
      };
    in
    true;

  validateRuntimeTargetForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      _validateDeploymentHost = deploymentHostForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      _interfaces = emittedInterfacesForUnit {
        inherit cpm unitName file;
      };

      _validateInterfaces = map (
        ifName:
        validateInterfaceForUnit {
          inherit unitName ifName file;
          iface = _interfaces.${ifName};
        }
      ) (sortedAttrNames _interfaces);
    in
    true;

  validateAllRuntimeTargets =
    {
      cpm,
      inventory ? { },
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;

      _validations = map (
        unitName:
        validateRuntimeTargetForUnit {
          inherit
            cpm
            inventory
            unitName
            file
            ;
        }
      ) (sortedAttrNames targets);
    in
    true;

  unitNamesForDeploymentHost =
    {
      cpm,
      inventory ? { },
      deploymentHostName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
    in
    lib.filter (
      unitName:
      deploymentHostForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      } == deploymentHostName
    ) (sortedAttrNames targets);

  unitNamesForRoleOnDeploymentHost =
    {
      cpm,
      inventory ? { },
      deploymentHostName,
      role,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
    in
    lib.filter (
      unitName:
      roleForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      } == role
      &&
        deploymentHostForUnit {
          inherit
            cpm
            inventory
            unitName
            file
            ;
        } == deploymentHostName
    ) (sortedAttrNames targets);

  requestedHostMatchesUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      requestedHostName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      logicalNodeName = logicalNodeNameForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      runtimeTargetId = runtimeTargetIdForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    in
    unitName == requestedHostName
    || runtimeTargetId == requestedHostName
    || logicalNodeName == requestedHostName
    || lib.hasPrefix "${requestedHostName}::" unitName
    || lib.hasPrefix "${requestedHostName}-" runtimeTargetId
    || lib.hasPrefix "${requestedHostName}-" logicalNodeName;

  selectedUnitsForHostContext =
    {
      cpm,
      inventory ? { },
      hostContext,
      runtimeRole ? null,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      requestedHostName =
        if hostContext ? hostname && builtins.isString hostContext.hostname then
          hostContext.hostname
        else if hostContext ? selector && builtins.isString hostContext.selector then
          hostContext.selector
        else if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
          hostContext.deploymentHostName
        else
          throw ''
            ${file}: hostContext is missing hostname
          '';

      deploymentHostName =
        if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
          hostContext.deploymentHostName
        else
          requestedHostName;

      deploymentCandidates = unitNamesForDeploymentHost {
        inherit
          cpm
          inventory
          deploymentHostName
          file
          ;
      };

      hostScopedCandidates = lib.filter (
        unitName:
        requestedHostMatchesUnit {
          inherit
            cpm
            inventory
            unitName
            file
            ;
          requestedHostName = requestedHostName;
        }
      ) deploymentCandidates;

      baseCandidates =
        if requestedHostName != deploymentHostName && hostScopedCandidates != [ ] then
          hostScopedCandidates
        else
          deploymentCandidates;
    in
    if runtimeRole == null then
      baseCandidates
    else
      lib.filter (
        unitName:
        roleForUnit {
          inherit
            cpm
            inventory
            unitName
            file
            ;
        } == runtimeRole
      ) baseCandidates;

  selectedRoleNamesForUnits =
    {
      cpm,
      inventory ? { },
      selectedUnits,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    lib.unique (
      lib.filter builtins.isString (
        map (
          unitName:
          roleForUnit {
            inherit
              cpm
              inventory
              unitName
              file
              ;
          }
        ) selectedUnits
      )
    );

  rootNamesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.rootName ];

  siteNamesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/ControlModule/lookup/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.siteName ];
in
{
  inherit
    siteEntries
    runtimeTargetInstanceId
    runtimeTargetEntries
    runtimeTargets
    siteEntryForUnit
    runtimeTargetForUnit
    runtimeTargetIdForUnit
    logicalNodeForUnit
    logicalNodeNameForUnit
    logicalNodeIdentityForUnit
    roleForUnit
    deploymentHostForUnit
    realizationNodeForUnit
    realizationHostForUnit
    emittedInterfacesForUnit
    validateInterfaceForUnit
    validateRuntimeTargetForUnit
    validateAllRuntimeTargets
    unitNamesForDeploymentHost
    unitNamesForRoleOnDeploymentHost
    requestedHostMatchesUnit
    selectedUnitsForHostContext
    selectedRoleNamesForUnits
    rootNamesForUnit
    siteNamesForUnit
    ;
}
