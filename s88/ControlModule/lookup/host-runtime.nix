{
  lib,
  hostName,
  cpm,
  inventory ? { },
}:

let
  runtimeContext = import ./runtime-context.nix { inherit lib; };
  runtimeTargets = import ../mapping/runtime-targets.nix { inherit lib; };
  hostQuery = import ./host-query.nix { inherit lib; };
  roles = import ../roles/registry.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  resolvedHostContext =
    if inventory != { } then
      hostQuery.hostContextForHost {
        inherit inventory;
        hostname = hostName;
        file = "s88/CM/network/lookup/host-runtime.nix";
      }
    else
      {
        hostname = hostName;
        renderHosts = { };
        renderHostConfig = { };
        deploymentHosts = { };
        deploymentHostNames = [ hostName ];
        realizationNodes = { };
        deploymentHostName = hostName;
        deploymentHost = { };
        realizationNode = null;
      };

  deploymentHostName = resolvedHostContext.deploymentHostName or hostName;
  deploymentHost = resolvedHostContext.deploymentHost or { };
  renderHostConfig = resolvedHostContext.renderHostConfig or { };

  realizationNodes =
    if
      resolvedHostContext ? realizationNodes && builtins.isAttrs resolvedHostContext.realizationNodes
    then
      resolvedHostContext.realizationNodes
    else if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  normalizedRuntimeTargets = runtimeTargets.normalizedRuntimeTargets {
    inherit cpm;
    file = "s88/CM/network/lookup/host-runtime.nix";
  };

  allUnitNames = sortedAttrNames normalizedRuntimeTargets;

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    inherit cpm inventory deploymentHostName;
    file = "s88/CM/network/lookup/host-runtime.nix";
  };

  runtimeRole =
    if renderHostConfig ? runtimeRole && builtins.isString renderHostConfig.runtimeRole then
      renderHostConfig.runtimeRole
    else
      null;

  selectedUnits = runtimeContext.selectedUnitsForHostContext {
    inherit cpm inventory runtimeRole;
    hostContext = resolvedHostContext;
    file = "s88/CM/network/lookup/host-runtime.nix";
  };

  _selectedUnitsNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        s88/CM/network/lookup/host-runtime.nix: no units matched deployment host '${deploymentHostName}'${
          if runtimeRole != null then " for runtimeRole '${runtimeRole}'" else ""
        }

        requested host:
        ${hostName}

        units on deployment host:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ unitsOnDeploymentHost)}

        available runtime targets:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ allUnitNames)}
      '';

  selectedRoleNames = runtimeContext.selectedRoleNamesForUnits {
    inherit cpm inventory selectedUnits;
    file = "s88/CM/network/lookup/host-runtime.nix";
  };

  selectedRoles = builtins.listToAttrs (
    map (roleName: {
      name = roleName;
      value = roles.${roleName};
    }) (lib.filter (roleName: builtins.hasAttr roleName roles) selectedRoleNames)
  );

  unitRoles = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = runtimeContext.roleForUnit {
        inherit cpm inventory unitName;
        file = "s88/CM/network/lookup/host-runtime.nix";
      };
    }) selectedUnits
  );

  output = {
    inherit
      hostName
      deploymentHostName
      deploymentHost
      renderHostConfig
      resolvedHostContext
      realizationNodes
      normalizedRuntimeTargets
      allUnitNames
      unitsOnDeploymentHost
      runtimeRole
      selectedUnits
      selectedRoleNames
      selectedRoles
      unitRoles
      ;
  };
in
builtins.seq _selectedUnitsNonEmpty output
