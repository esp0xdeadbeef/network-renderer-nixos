{
  lib,
  cpm,
  inventory ? { },
  unitsOnDeploymentHost,
  selectedUnits,
  selectedRoleNames,
  file ? "s88/Unit/lookup/host-runtime.nix",
}:

let
  runtimeContext = import ../runtime-context.nix { inherit lib; };
  roles = import ../../../ControlModule/profiles/registry.nix { inherit lib; };

  deploymentHostUnitRoles = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = runtimeContext.roleForUnit {
        inherit
          cpm
          inventory
          unitName
          file
          ;
      };
    }) unitsOnDeploymentHost
  );

  deploymentHostRoleNames = lib.unique (
    lib.filter builtins.isString (
      map (unitName: deploymentHostUnitRoles.${unitName}) unitsOnDeploymentHost
    )
  );

  deploymentHostRoles = builtins.listToAttrs (
    map (roleName: {
      name = roleName;
      value = roles.${roleName};
    }) (lib.filter (roleName: builtins.hasAttr roleName roles) deploymentHostRoleNames)
  );

  deploymentHostContainerNamingUnits = lib.filter (
    unitName:
    let
      roleName = deploymentHostUnitRoles.${unitName} or null;

      roleConfig =
        if roleName != null && builtins.hasAttr roleName deploymentHostRoles then
          deploymentHostRoles.${roleName}
        else
          { };

      containerConfig =
        if roleConfig ? container && builtins.isAttrs roleConfig.container then
          roleConfig.container
        else
          { };
    in
    containerConfig ? enable && (containerConfig.enable or false)
  ) unitsOnDeploymentHost;

  selectedRoles = builtins.listToAttrs (
    map (roleName: {
      name = roleName;
      value = roles.${roleName};
    }) (lib.filter (roleName: builtins.hasAttr roleName roles) selectedRoleNames)
  );

  unitRoles = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = deploymentHostUnitRoles.${unitName};
    }) selectedUnits
  );
in
{
  inherit
    deploymentHostUnitRoles
    deploymentHostRoleNames
    deploymentHostRoles
    deploymentHostContainerNamingUnits
    selectedRoles
    unitRoles
    ;
}
