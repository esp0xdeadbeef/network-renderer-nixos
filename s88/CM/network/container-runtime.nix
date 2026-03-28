{
  config,
  lib,
  controlPlaneOut,
  globalInventory,
  hostContext,
  activeRoleNames ? [ ],
  activeRoles ? { },
  s88Role ? null,
  s88RoleName ? null,
  ...
}:

let
  runtimeContext = import ../../../lib/runtime-context.nix { inherit lib; };
  cpmAdapter = import ../../../lib/cpm-runtime-adapter.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHostName =
    if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
      hostContext.deploymentHostName
    else
      config.networking.hostName;

  effectiveActiveRoles =
    if activeRoles != { } then
      activeRoles
    else if s88Role != null && s88RoleName != null then
      { "${s88RoleName}" = s88Role; }
    else
      { };

  effectiveActiveRoleNames =
    if activeRoleNames != [ ] then activeRoleNames else sortedAttrNames effectiveActiveRoles;

  renderedHostNetwork = import ../../../lib/render-host-network.nix {
    inherit lib;
    hostName = deploymentHostName;
    cpm = controlPlaneOut;
  };

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    cpm = controlPlaneOut;
    inventory = globalInventory;
    inherit deploymentHostName;
    file = "s88/CM/network/container-runtime.nix";
  };

  selectedUnits = lib.filter (
    unitName:
    let
      unitRoleName = runtimeContext.roleForUnit {
        cpm = controlPlaneOut;
        inventory = globalInventory;
        inherit unitName;
        file = "s88/CM/network/container-runtime.nix";
      };
    in
    builtins.hasAttr unitRoleName effectiveActiveRoles
    && effectiveActiveRoles.${unitRoleName} ? container
    && builtins.isAttrs effectiveActiveRoles.${unitRoleName}.container
    && (effectiveActiveRoles.${unitRoleName}.container.enable or false)
  ) unitsOnDeploymentHost;

  mkContainer =
    unitName:
    let
      unitRoleName = runtimeContext.roleForUnit {
        cpm = controlPlaneOut;
        inventory = globalInventory;
        inherit unitName;
        file = "s88/CM/network/container-runtime.nix";
      };

      unitRole =
        if builtins.hasAttr unitRoleName effectiveActiveRoles then
          effectiveActiveRoles.${unitRoleName}
        else
          throw "s88/CM/network/container-runtime.nix: no role registry entry for unit '${unitName}' with role '${unitRoleName}'";

      runtimeTarget = cpmAdapter.normalizedRuntimeTargetForUnit {
        cpm = controlPlaneOut;
        inherit unitName;
        file = "s88/CM/network/container-runtime.nix";
      };

      interfaces = runtimeTarget.interfaces;

      profilePath =
        if
          unitRole ? container && builtins.isAttrs unitRole.container && unitRole.container ? profilePath
        then
          unitRole.container.profilePath
        else
          null;

      additionalCapabilities =
        if
          unitRole ? container
          && builtins.isAttrs unitRole.container
          && unitRole.container ? additionalCapabilities
          && builtins.isList unitRole.container.additionalCapabilities
        then
          unitRole.container.additionalCapabilities
        else
          [ ];

      bindMounts =
        if
          unitRole ? container
          && builtins.isAttrs unitRole.container
          && unitRole.container ? bindMounts
          && builtins.isAttrs unitRole.container.bindMounts
        then
          unitRole.container.bindMounts
        else
          { };

      allowedDevices =
        if
          unitRole ? container
          && builtins.isAttrs unitRole.container
          && unitRole.container ? allowedDevices
          && builtins.isList unitRole.container.allowedDevices
        then
          unitRole.container.allowedDevices
        else
          [ ];

      extraVeths = builtins.listToAttrs (
        map (
          ifName:
          let
            iface = interfaces.${ifName};

            renderedIfName =
              if iface ? renderedIfName && builtins.isString iface.renderedIfName then
                iface.renderedIfName
              else
                throw ''
                  s88/CM/network/container-runtime.nix: interface '${ifName}' missing renderedIfName for unit '${unitName}'
                '';

            hostBridgeName =
              if iface ? hostBridge && builtins.isString iface.hostBridge then
                iface.hostBridge
              else
                throw ''
                  s88/CM/network/container-runtime.nix: interface '${ifName}' missing normalized hostBridge for unit '${unitName}'
                '';

            renderedHostBridgeName =
              if builtins.hasAttr hostBridgeName renderedHostNetwork.bridgeNameMap then
                renderedHostNetwork.bridgeNameMap.${hostBridgeName}
              else
                throw ''
                  s88/CM/network/container-runtime.nix: unknown host bridge '${hostBridgeName}' for unit '${unitName}', interface '${ifName}'
                '';
          in
          {
            name = renderedIfName;
            value = {
              hostBridge = renderedHostBridgeName;
            };
          }
        ) (sortedAttrNames interfaces)
      );
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;
        inherit bindMounts allowedDevices extraVeths;

        additionalCapabilities = lib.unique (
          [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ]
          ++ additionalCapabilities
        );

        specialArgs = {
          inherit
            unitName
            deploymentHostName
            runtimeTarget
            controlPlaneOut
            globalInventory
            hostContext
            ;
          s88Role = unitRole;
          s88RoleName = unitRoleName;
        };

        config =
          { ... }:
          {
            imports = lib.optionals (profilePath != null) [
              profilePath
            ];

            networking.hostName = unitName;
          };
      };
    };
in
{
  containers = builtins.listToAttrs (map mkContainer selectedUnits);
}
