{ lib, base, hostQuery }:

let
  sortedAttrNames = base.sortedAttrNames;
in
rec {
  deploymentHostForUnit =
    { cpm, inventory ? { }, unitName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      target = base.runtimeTargetForUnit { inherit cpm unitName file; };
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
      runtimeTargetId = base.runtimeTargetIdForUnit { inherit cpm inventory unitName file; };
      logicalNodeName = base.logicalNodeNameForUnit { inherit cpm inventory unitName file; };
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
                base.realizationHostForUnit { inherit cpm inventory unitName file; };
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

  unitNamesForDeploymentHost =
    { cpm, inventory ? { }, deploymentHostName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let targets = base.runtimeTargets cpm;
    in
    lib.filter (
      unitName: deploymentHostForUnit { inherit cpm inventory unitName file; } == deploymentHostName
    ) (sortedAttrNames targets);

  requestedHostMatchesUnit =
    { cpm, inventory ? { }, unitName, requestedHostName, file ? "s88/Unit/lookup/runtime-context.nix" }:
    let
      logicalNodeName = base.logicalNodeNameForUnit { inherit cpm inventory unitName file; };
      runtimeTargetId = base.runtimeTargetIdForUnit { inherit cpm inventory unitName file; };
    in
    unitName == requestedHostName
    || runtimeTargetId == requestedHostName
    || logicalNodeName == requestedHostName
    || lib.hasPrefix "${requestedHostName}::" unitName
    || lib.hasPrefix "${requestedHostName}-" runtimeTargetId
    || lib.hasPrefix "${requestedHostName}-" logicalNodeName;
}
