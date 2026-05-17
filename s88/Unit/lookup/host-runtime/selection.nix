{
  lib,
  repoPath,
  cpm,
  inventory ? { },
  context,
  file ? "s88/Unit/lookup/host-runtime.nix",
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

  runtimeTargets = import ../../mapping/runtime-targets.nix { inherit lib; };
  hostQuery = import ../../../ControlModule/lookup/host-query.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = trace.emit "host-runtime:${context.deploymentHostName}:normalized-runtime-targets" (runtimeTargets.normalizedRuntimeTargets {
    inherit cpm file;
  });

  allUnitNames = trace.emit "host-runtime:${context.deploymentHostName}:all-unit-names" (sortedAttrNames normalizedRuntimeTargets);

  runtimeTargetForUnit =
    unitName:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}
    else
      throw ''
        ${file}: missing normalized runtime target for unit '${unitName}'
      '';

  logicalNodeForUnit =
    unitName:
    let target = runtimeTargetForUnit unitName;
    in if target ? logicalNode && builtins.isAttrs target.logicalNode then target.logicalNode else { };

  runtimeTargetIdForUnit =
    unitName:
    let
      target = runtimeTargetForUnit unitName;
      logicalNode = logicalNodeForUnit unitName;
    in
    if target ? runtimeTargetId && builtins.isString target.runtimeTargetId then
      target.runtimeTargetId
    else if logicalNode ? name && builtins.isString logicalNode.name then
      logicalNode.name
    else
      unitName;

  logicalNodeNameForUnit =
    unitName:
    let
      logicalNode = logicalNodeForUnit unitName;
      runtimeTargetId = runtimeTargetIdForUnit unitName;
    in
    if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else runtimeTargetId;

  roleForUnit =
    unitName:
    let
      target = runtimeTargetForUnit unitName;
      logicalNode = logicalNodeForUnit unitName;
    in
    if target ? role && builtins.isString target.role then target.role else logicalNode.role or null;

  realizationNodes =
    if inventory ? realization && builtins.isAttrs inventory.realization && builtins.isAttrs (inventory.realization.nodes or null) then
      inventory.realization.nodes
    else if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? realization
      && builtins.isAttrs cpm.control_plane_model.realization
      && builtins.isAttrs (cpm.control_plane_model.realization.nodes or null)
    then
      cpm.control_plane_model.realization.nodes
    else if cpm ? realization && builtins.isAttrs cpm.realization && builtins.isAttrs (cpm.realization.nodes or null) then
      cpm.realization.nodes
    else
      { };

  logicalNodeForRealizationNode =
    node: if node ? logicalNode && builtins.isAttrs node.logicalNode then node.logicalNode else { };

  realizationHostForUnit =
    unitName:
    let
      runtimeTargetId = runtimeTargetIdForUnit unitName;
      logicalNode = logicalNodeForUnit unitName;
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
      logicalMatches = lib.filter (
        nodeName:
        let nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
        in
        logicalName != null
        && (nodeLogical.name or null) == logicalName
        && (logicalSite == null || (nodeLogical.site or null) == logicalSite)
        && (logicalEnterprise == null || (nodeLogical.enterprise or null) == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);
      prefixMatches = lib.filter (
        nodeName:
        let nodeLogical = logicalNodeForRealizationNode realizationNodes.${nodeName};
        in
        runtimeTargetId != null
        && lib.hasSuffix runtimeTargetId nodeName
        && (logicalSite == null || (nodeLogical.site or null) == logicalSite)
        && (logicalEnterprise == null || (nodeLogical.enterprise or null) == logicalEnterprise)
      ) (sortedAttrNames realizationNodes);
      candidates = lib.unique (exactNames ++ logicalMatches ++ prefixMatches);
      node =
        if builtins.hasAttr unitName realizationNodes && builtins.isAttrs realizationNodes.${unitName} then
          realizationNodes.${unitName}
        else if builtins.length candidates == 1 then
          realizationNodes.${builtins.head candidates}
        else
          null;
    in
    if node != null && node ? host && builtins.isString node.host then node.host else null;

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

  deploymentHostForUnit =
    unitName:
    let
      target = runtimeTargetForUnit unitName;
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
      runtimeTargetId = runtimeTargetIdForUnit unitName;
      logicalNodeName = logicalNodeNameForUnit unitName;
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
      resolvedViaInventory =
        if placementHost != null then
          null
        else
          let
            fromUnitName = resolveCandidate unitName;
            fromRuntimeTargetId = if fromUnitName != null then null else resolveCandidate runtimeTargetId;
            fromLogicalNodeName =
              if fromUnitName != null || fromRuntimeTargetId != null then null else resolveCandidate logicalNodeName;
            fromFallbackHost =
              if fromUnitName != null || fromRuntimeTargetId != null || fromLogicalNodeName != null then
                null
              else
                resolveCandidate fallbackHost;
            fromRealizationHost =
              if fromUnitName != null || fromRuntimeTargetId != null || fromLogicalNodeName != null || fromFallbackHost != null then
                null
              else
                realizationHostForUnit unitName;
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
    if placementHost != null then placementHost else if resolvedViaInventory != null then resolvedViaInventory else fallbackHost;

  unitsOnDeploymentHost = trace.emit "host-runtime:${context.deploymentHostName}:units-on-deployment-host" (
    lib.filter (unitName: deploymentHostForUnit unitName == context.deploymentHostName) allUnitNames
  );

  runtimeRole =
    if context.renderHostConfig ? runtimeRole && builtins.isString context.renderHostConfig.runtimeRole then
      context.renderHostConfig.runtimeRole
    else
      null;

  requestedNames =
    hostContext: plural: singular:
    if builtins.hasAttr plural hostContext && builtins.isList hostContext.${plural} then
      hostContext.${plural}
    else if builtins.hasAttr singular hostContext && builtins.isString hostContext.${singular} then
      [ hostContext.${singular} ]
    else
      [ ];

  requestedHostName = context.requestedHostName;
  deploymentHostName = context.deploymentHostName;
  requestedSiteNames = requestedNames context.effectiveHostContext "matchedSites" "siteName";
  requestedEnterpriseNames = requestedNames context.effectiveHostContext "matchedEnterprises" "enterpriseName";

  matchesRequestedIdentity =
    unitName:
    let
      logicalNode = logicalNodeForUnit unitName;
      unitSite = logicalNode.site or null;
      unitEnterprise = logicalNode.enterprise or null;
    in
    (requestedSiteNames == [ ] || builtins.elem unitSite requestedSiteNames)
    && (requestedEnterpriseNames == [ ] || builtins.elem unitEnterprise requestedEnterpriseNames);

  requestedHostMatchesUnit =
    unitName:
    let
      logicalNodeName = logicalNodeNameForUnit unitName;
      runtimeTargetId = runtimeTargetIdForUnit unitName;
    in
    unitName == requestedHostName
    || runtimeTargetId == requestedHostName
    || logicalNodeName == requestedHostName
    || lib.hasPrefix "${requestedHostName}::" unitName
    || lib.hasPrefix "${requestedHostName}-" runtimeTargetId
    || lib.hasPrefix "${requestedHostName}-" logicalNodeName;

  identityFallbackCandidates = lib.filter matchesRequestedIdentity allUnitNames;
  hostScopedCandidates = lib.filter requestedHostMatchesUnit (
    if unitsOnDeploymentHost == [ ] then identityFallbackCandidates else unitsOnDeploymentHost
  );
  baseCandidatesOrFallback =
    if requestedHostName != deploymentHostName && hostScopedCandidates != [ ] then
      hostScopedCandidates
    else if unitsOnDeploymentHost != [ ] then
      unitsOnDeploymentHost
    else
      identityFallbackCandidates;
  identityScopedCandidates = lib.filter matchesRequestedIdentity baseCandidatesOrFallback;

  selectedUnits = trace.emit "host-runtime:${context.deploymentHostName}:selected-units" (
    if runtimeRole == null then
      identityScopedCandidates
    else
      lib.filter (unitName: roleForUnit unitName == runtimeRole) identityScopedCandidates
  );

  selectedRoleNames = trace.emit "host-runtime:${context.deploymentHostName}:selected-role-names" (
    lib.unique (lib.filter builtins.isString (map roleForUnit selectedUnits))
  );
in
{
  inherit
    normalizedRuntimeTargets
    allUnitNames
    unitsOnDeploymentHost
    runtimeRole
    selectedUnits
    selectedRoleNames
    ;
}
