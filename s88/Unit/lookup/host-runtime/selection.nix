{
  lib,
  cpm,
  inventory ? { },
  context,
  file ? "s88/Unit/lookup/host-runtime.nix",
}:

let
  runtimeContext = import ../runtime-context.nix { inherit lib; };
  runtimeTargets = import ../../mapping/runtime-targets.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = runtimeTargets.normalizedRuntimeTargets {
    inherit cpm file;
  };

  allUnitNames = sortedAttrNames normalizedRuntimeTargets;

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    inherit cpm inventory file;
    deploymentHostName = context.deploymentHostName;
  };

  runtimeRole =
    if
      context.renderHostConfig ? runtimeRole && builtins.isString context.renderHostConfig.runtimeRole
    then
      context.renderHostConfig.runtimeRole
    else
      null;

  selectedUnits = runtimeContext.selectedUnitsForHostContext {
    inherit
      cpm
      inventory
      runtimeRole
      file
      ;
    hostContext = context.effectiveHostContext;
  };

  selectedRoleNames = runtimeContext.selectedRoleNamesForUnits {
    inherit
      cpm
      inventory
      selectedUnits
      file
      ;
  };
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
