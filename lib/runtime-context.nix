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

  siteTreeForEnterprise =
    enterprise:
    if enterprise ? site && builtins.isAttrs enterprise.site then
      enterprise.site
    else if builtins.isAttrs enterprise then
      enterprise
    else
      { };

  siteEntries =
    cpm:
    let
      cpmData = controlPlaneData cpm;
    in
    lib.concatMap (
      enterpriseName:
      let
        siteTree = siteTreeForEnterprise cpmData.${enterpriseName};
      in
      map (siteName: {
        inherit enterpriseName siteName;
        site = siteTree.${siteName};
      }) (sortedAttrNames siteTree)
    ) (sortedAttrNames cpmData);

  runtimeTargets =
    cpm:
    lib.foldl' (
      acc: entry:
      acc
      // (
        if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
          entry.site.runtimeTargets
        else
          { }
      )
    ) { } (siteEntries cpm);

  siteEntryForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      matches = lib.filter (
        entry:
        entry.site ? runtimeTargets
        && builtins.isAttrs entry.site.runtimeTargets
        && builtins.hasAttr unitName entry.site.runtimeTargets
      ) (siteEntries cpm);
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if matches == [ ] then
      throw ''
        ${file}: no site entry matched unit '${unitName}'
      ''
    else
      throw ''
        ${file}: multiple site entries matched unit '${unitName}'
      '';

  runtimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      targets = runtimeTargets cpm;
    in
    if builtins.hasAttr unitName targets && builtins.isAttrs targets.${unitName} then
      targets.${unitName}
    else
      throw ''
        ${file}: missing runtime target for unit '${unitName}'

        known runtime targets:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ sortedAttrNames targets)}
      '';

  logicalNodeForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      target = runtimeTargetForUnit {
        inherit cpm unitName file;
      };
    in
    if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  roleForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "lib/runtime-context.nix",
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

  deploymentHostForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "lib/runtime-context.nix",
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

      fallbackHost =
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
            fromFallbackHost = if fromUnitName != null then null else resolveCandidate fallbackHost;
          in
          if fromUnitName != null then fromUnitName else fromFallbackHost;
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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
      file ? "lib/runtime-context.nix",
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

  enterpriseNamesForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
    }:
    let
      entry = siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.enterpriseName ];

  siteNamesForUnit =
    {
      cpm,
      unitName,
      file ? "lib/runtime-context.nix",
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
    runtimeTargets
    siteEntryForUnit
    runtimeTargetForUnit
    logicalNodeForUnit
    roleForUnit
    deploymentHostForUnit
    emittedInterfacesForUnit
    validateInterfaceForUnit
    validateRuntimeTargetForUnit
    validateAllRuntimeTargets
    unitNamesForDeploymentHost
    unitNamesForRoleOnDeploymentHost
    enterpriseNamesForUnit
    siteNamesForUnit
    ;
}
