{ lib
, repoPath
, cpm
, inventory ? { }
, context
, file ? "s88/Unit/lookup/host-runtime.nix"
,
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

  runtimeContext = import ../runtime-context.nix { inherit lib; };
  runtimeTargets = import ../../mapping/runtime-targets.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = trace.emit "host-runtime:${context.deploymentHostName}:normalized-runtime-targets" (runtimeTargets.normalizedRuntimeTargets {
    inherit cpm file;
  });

  allUnitNames = trace.emit "host-runtime:${context.deploymentHostName}:all-unit-names" (sortedAttrNames normalizedRuntimeTargets);

  unitsOnDeploymentHost = trace.emit "host-runtime:${context.deploymentHostName}:units-on-deployment-host" (runtimeContext.unitNamesForDeploymentHost {
    inherit cpm inventory file;
    deploymentHostName = context.deploymentHostName;
  });

  runtimeRole =
    if
      context.renderHostConfig ? runtimeRole && builtins.isString context.renderHostConfig.runtimeRole
    then
      context.renderHostConfig.runtimeRole
    else
      null;

  selectedUnits = trace.emit "host-runtime:${context.deploymentHostName}:selected-units" (runtimeContext.selectedUnitsForHostContext {
    inherit
      cpm
      inventory
      runtimeRole
      file
      ;
    hostContext = context.effectiveHostContext;
  });

  selectedRoleNames = trace.emit "host-runtime:${context.deploymentHostName}:selected-role-names" (runtimeContext.selectedRoleNamesForUnits {
    inherit
      cpm
      inventory
      selectedUnits
      file
      ;
  });
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
