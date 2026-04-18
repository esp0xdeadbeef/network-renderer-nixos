{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
  context = import ./context.nix {
    inherit
      lib
      hostName
      cpm
      inventory
      hostContext
      ;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  selection = import ./selection.nix {
    inherit lib cpm inventory;
    inherit context;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  roleView = import ./roles.nix {
    inherit
      lib
      cpm
      inventory
      ;
    inherit (selection)
      unitsOnDeploymentHost
      selectedUnits
      selectedRoleNames
      ;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  _selectedUnitsNonEmpty =
    if selection.selectedUnits != [ ] then
      true
    else
      throw ''
        s88/Unit/lookup/host-runtime.nix: no units matched deployment host '${context.deploymentHostName}'${
          if selection.runtimeRole != null then " for runtimeRole '${selection.runtimeRole}'" else ""
        }

        requested host:
        ${context.requestedHostName}

        units on deployment host:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ selection.unitsOnDeploymentHost)}

        available runtime targets:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ selection.allUnitNames)}
      '';

  output = {
    hostName = context.requestedHostName;

    inherit (context)
      deploymentHostName
      deploymentHost
      renderHostConfig
      resolvedHostContext
      realizationNodes
      ;

    inherit (selection)
      normalizedRuntimeTargets
      allUnitNames
      unitsOnDeploymentHost
      runtimeRole
      selectedUnits
      selectedRoleNames
      ;

    inherit (roleView)
      deploymentHostUnitRoles
      deploymentHostRoleNames
      deploymentHostRoles
      deploymentHostContainerNamingUnits
      selectedRoles
      unitRoles
      ;
  };
in
builtins.seq _selectedUnitsNonEmpty output
