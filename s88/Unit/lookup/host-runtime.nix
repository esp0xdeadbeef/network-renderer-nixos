{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
  runtimeContext = import ./runtime-context.nix { inherit lib; };
  runtimeTargets = import ../mapping/runtime-targets.nix { inherit lib; };
  hostQuery = import ../../ControlModule/lookup/host-query.nix { inherit lib; };
  roles = import ../../ControlModule/profiles/registry.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  requestedHostName =
    if
      hostContext != null
      && builtins.isAttrs hostContext
      && hostContext ? hostname
      && builtins.isString hostContext.hostname
    then
      hostContext.hostname
    else
      hostName;

  resolvedHostContext =
    if hostContext != null && builtins.isAttrs hostContext && hostContext != { } then
      hostContext // { hostname = requestedHostName; }
    else if inventory != { } then
      hostQuery.hostContextForHost {
        inherit inventory;
        hostname = requestedHostName;
        file = "s88/Unit/lookup/host-runtime.nix";
      }
    else
      {
        hostname = requestedHostName;
        renderHosts = { };
        renderHostConfig = { };
        deploymentHosts = { };
        deploymentHostNames = [ requestedHostName ];
        realizationNodes = { };
        deploymentHostName = requestedHostName;
        deploymentHost = { };
        realizationNode = null;
      };

  deploymentHostName =
    if
      resolvedHostContext ? deploymentHostName && builtins.isString resolvedHostContext.deploymentHostName
    then
      resolvedHostContext.deploymentHostName
    else
      requestedHostName;

  deploymentHost =
    if resolvedHostContext ? deploymentHost && builtins.isAttrs resolvedHostContext.deploymentHost then
      resolvedHostContext.deploymentHost
    else
      { };

  renderHostConfig =
    if
      resolvedHostContext ? renderHostConfig && builtins.isAttrs resolvedHostContext.renderHostConfig
    then
      resolvedHostContext.renderHostConfig
    else
      { };

  realizationNodes =
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else if
      resolvedHostContext ? realizationNodes && builtins.isAttrs resolvedHostContext.realizationNodes
    then
      resolvedHostContext.realizationNodes
    else
      { };

  normalizedRuntimeTargets = runtimeTargets.normalizedRuntimeTargets {
    inherit cpm;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  allUnitNames = sortedAttrNames normalizedRuntimeTargets;

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    inherit cpm inventory deploymentHostName;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  runtimeRole =
    if renderHostConfig ? runtimeRole && builtins.isString renderHostConfig.runtimeRole then
      renderHostConfig.runtimeRole
    else
      null;

  effectiveHostContext = resolvedHostContext // {
    hostname = requestedHostName;
    inherit deploymentHostName;
  };

  selectedUnits = runtimeContext.selectedUnitsForHostContext {
    inherit cpm inventory runtimeRole;
    hostContext = effectiveHostContext;
    file = "s88/Unit/lookup/host-runtime.nix";
  };

  _selectedUnitsNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        s88/Unit/lookup/host-runtime.nix: no units matched deployment host '${deploymentHostName}'${
          if runtimeRole != null then " for runtimeRole '${runtimeRole}'" else ""
        }

        requested host:
        ${requestedHostName}

        units on deployment host:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ unitsOnDeploymentHost)}

        available runtime targets:
        ${builtins.concatStringsSep "\n  " ([ "" ] ++ allUnitNames)}
      '';

  deploymentHostUnitRoles = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = runtimeContext.roleForUnit {
        inherit cpm inventory unitName;
        file = "s88/Unit/lookup/host-runtime.nix";
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

  selectedRoleNames = runtimeContext.selectedRoleNamesForUnits {
    inherit cpm inventory selectedUnits;
    file = "s88/Unit/lookup/host-runtime.nix";
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
      value = deploymentHostUnitRoles.${unitName};
    }) selectedUnits
  );

  output = {
    hostName = requestedHostName;

    inherit
      deploymentHostName
      deploymentHost
      renderHostConfig
      resolvedHostContext
      realizationNodes
      normalizedRuntimeTargets
      allUnitNames
      unitsOnDeploymentHost
      deploymentHostUnitRoles
      deploymentHostRoleNames
      deploymentHostRoles
      deploymentHostContainerNamingUnits
      runtimeRole
      selectedUnits
      selectedRoleNames
      selectedRoles
      unitRoles
      ;
  };
in
builtins.seq _selectedUnitsNonEmpty output
