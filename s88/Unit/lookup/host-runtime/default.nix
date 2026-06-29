{ lib
, repoPath
, hostName
, cpm
, source ? { }
, hostContext ? null
,
}:

let
  context = import ./context.nix {
    inherit
      lib
      hostName
      cpm
      source
      hostContext
      ;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  selection = import ./selection.nix {
    inherit lib repoPath cpm source;
    inherit context;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  roleView = import ./roles.nix {
    inherit
      lib
      cpm
      source
      ;
    inherit (selection)
      unitsOnDeploymentHost
      selectedUnits
      selectedRoleNames
      ;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

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
output
