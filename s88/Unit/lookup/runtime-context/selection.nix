{ lib }:

let
  base = import ./base.nix { inherit lib; };
  hostQuery = import ../../../ControlModule/lookup/host-query.nix { inherit lib; };

  sortedAttrNames = base.sortedAttrNames;

  deploymentHostForUnit =
    {
      cpm,
      inventory ? { },
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      target = base.runtimeTargetForUnit {
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

      runtimeTargetId = base.runtimeTargetIdForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      logicalNodeName = base.logicalNodeNameForUnit {
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
                base.realizationHostForUnit {
                  inherit
                    cpm
                    inventory
                    unitName
                    file
                    ;
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

  unitNamesForDeploymentHost =
    {
      cpm,
      inventory ? { },
      deploymentHostName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      targets = base.runtimeTargets cpm;
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
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      targets = base.runtimeTargets cpm;
    in
    lib.filter (
      unitName:
      base.roleForUnit {
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
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      logicalNodeName = base.logicalNodeNameForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };

      runtimeTargetId = base.runtimeTargetIdForUnit {
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
      file ? "s88/Unit/lookup/runtime-context.nix",
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

      requestedSiteNames =
        if hostContext ? matchedSites && builtins.isList hostContext.matchedSites then
          hostContext.matchedSites
        else if hostContext ? siteName && builtins.isString hostContext.siteName then
          [ hostContext.siteName ]
        else
          [ ];

      requestedEnterpriseNames =
        if hostContext ? matchedEnterprises && builtins.isList hostContext.matchedEnterprises then
          hostContext.matchedEnterprises
        else if hostContext ? enterpriseName && builtins.isString hostContext.enterpriseName then
          [ hostContext.enterpriseName ]
        else
          [ ];

      matchesRequestedIdentity =
        unitName:
        let
          logicalNode = base.logicalNodeForUnit {
            inherit
              cpm
              inventory
              unitName
              file
              ;
          };

          unitSite = logicalNode.site or null;
          unitEnterprise = logicalNode.enterprise or null;
        in
        (requestedSiteNames == [ ] || builtins.elem unitSite requestedSiteNames)
        && (requestedEnterpriseNames == [ ] || builtins.elem unitEnterprise requestedEnterpriseNames);

      deploymentCandidates = unitNamesForDeploymentHost {
        inherit
          cpm
          inventory
          deploymentHostName
          file
          ;
      };

      fallbackCandidates = sortedAttrNames (base.runtimeTargets cpm);
      identityFallbackCandidates = lib.filter matchesRequestedIdentity fallbackCandidates;

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
      ) (if deploymentCandidates == [ ] then identityFallbackCandidates else deploymentCandidates);

      baseCandidatesOrFallback =
        if requestedHostName != deploymentHostName && hostScopedCandidates != [ ] then
          hostScopedCandidates
        else if deploymentCandidates != [ ] then
          deploymentCandidates
        else
          identityFallbackCandidates;

      identityScopedCandidates = lib.filter matchesRequestedIdentity baseCandidatesOrFallback;
    in
    if runtimeRole == null then
      identityScopedCandidates
    else
      lib.filter (
        unitName:
        base.roleForUnit {
          inherit
            cpm
            inventory
            unitName
            file
            ;
        } == runtimeRole
      ) identityScopedCandidates;

  selectedRoleNamesForUnits =
    {
      cpm,
      inventory ? { },
      selectedUnits,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    lib.unique (
      lib.filter builtins.isString (
        map (
          unitName:
          base.roleForUnit {
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
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      entry = base.siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.rootName ];

  siteNamesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/lookup/runtime-context.nix",
    }:
    let
      entry = base.siteEntryForUnit {
        inherit cpm unitName file;
      };
    in
    [ entry.siteName ];
in
{
  inherit
    deploymentHostForUnit
    unitNamesForDeploymentHost
    unitNamesForRoleOnDeploymentHost
    requestedHostMatchesUnit
    selectedUnitsForHostContext
    selectedRoleNamesForUnits
    rootNamesForUnit
    siteNamesForUnit
    ;
}
