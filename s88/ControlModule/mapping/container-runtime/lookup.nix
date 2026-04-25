{
  lib,
  hostPlan,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = hostPlan.normalizedRuntimeTargets or { };
  selectedUnits = hostPlan.selectedUnits or [ ];
  selectedRoles = hostPlan.selectedRoles or { };
  deploymentHostRoles = hostPlan.deploymentHostRoles or selectedRoles;
  unitRoles = hostPlan.deploymentHostUnitRoles or (hostPlan.unitRoles or { });

  deploymentHostContainerNamingUnits =
    hostPlan.deploymentHostContainerNamingUnits
      or (lib.filter (unitName: builtins.elem unitName selectedUnits) selectedUnits);

  localAttachTargets = hostPlan.localAttachTargets or [ ];
  bridgeNameMap = hostPlan.bridgeNameMap or { };
  deploymentHostName = hostPlan.deploymentHostName or null;
  hostContext = hostPlan.resolvedHostContext or { };
  siteData = hostPlan.sitesData or { };

  runtimeTargetForUnit =
    unitName:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}
    else
      throw ''
        s88/CM/network/mapping/container-runtime.nix: missing normalized runtime target for unit '${unitName}'
      '';

  runtimeTargetIdForUnit =
    unitName:
    let
      runtimeTarget = runtimeTargetForUnit unitName;
    in
    if runtimeTarget ? runtimeTargetId && builtins.isString runtimeTarget.runtimeTargetId then
      runtimeTarget.runtimeTargetId
    else if
      runtimeTarget ? logicalNode
      && builtins.isAttrs runtimeTarget.logicalNode
      && runtimeTarget.logicalNode ? name
      && builtins.isString runtimeTarget.logicalNode.name
    then
      runtimeTarget.logicalNode.name
    else
      unitName;

  roleForUnit = unitName: if builtins.hasAttr unitName unitRoles then unitRoles.${unitName} else null;

  roleConfigForUnit =
    unitName:
    let
      roleName = roleForUnit unitName;
    in
    if roleName != null && builtins.hasAttr roleName deploymentHostRoles then
      deploymentHostRoles.${roleName}
    else
      { };

  containerConfigForUnit =
    unitName:
    let
      roleConfig = roleConfigForUnit unitName;
    in
    if roleConfig ? container && builtins.isAttrs roleConfig.container then
      roleConfig.container
    else
      { };

  containerEnabledForUnit =
    unitName:
    let
      containerConfig = containerConfigForUnit unitName;
    in
    containerConfig ? enable && (containerConfig.enable or false);

  enabledUnits = lib.filter containerEnabledForUnit selectedUnits;
in
{
  inherit
    sortedAttrNames
    normalizedRuntimeTargets
    selectedUnits
    selectedRoles
    deploymentHostRoles
    unitRoles
    deploymentHostContainerNamingUnits
    localAttachTargets
    bridgeNameMap
    deploymentHostName
    hostContext
    siteData
    runtimeTargetForUnit
    runtimeTargetIdForUnit
    roleForUnit
    roleConfigForUnit
    containerConfigForUnit
    containerEnabledForUnit
    enabledUnits
    ;
}
