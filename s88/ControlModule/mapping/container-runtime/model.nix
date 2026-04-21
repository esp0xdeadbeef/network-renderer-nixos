{
  lib,
  lookup,
  naming,
  interfaces,
}:

let
  normalizedEmittedInterfacesForRuntimeTarget =
    {
      emittedUnitName,
      interfaces,
    }:
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};
        in
        {
          name = ifName;
          value = iface // {
            runtimeTarget = emittedUnitName;
          };
        }
      ) (lookup.sortedAttrNames interfaces)
    );

  emittedRuntimeTargetForUnit =
    unitName:
    let
      originalRuntimeTarget = lookup.runtimeTargetForUnit unitName;
      emittedUnitName = naming.emittedUnitNameForUnit unitName;

      originalLogicalNode =
        if originalRuntimeTarget ? logicalNode && builtins.isAttrs originalRuntimeTarget.logicalNode then
          originalRuntimeTarget.logicalNode
        else
          { };
    in
    originalRuntimeTarget
    // {
      runtimeTargetId = emittedUnitName;
      deploymentHostName = lookup.deploymentHostName;
      logicalNode = originalLogicalNode // {
        name = emittedUnitName;
      };
      interfaces = normalizedEmittedInterfacesForRuntimeTarget {
        inherit emittedUnitName;
        interfaces = originalRuntimeTarget.interfaces or { };
      };
    };

  mkContainerRuntime =
    unitName:
    let
      runtimeTarget = emittedRuntimeTargetForUnit unitName;
      emittedUnitName = naming.emittedUnitNameForUnit unitName;
      containerName = naming.containerNameForUnit unitName;

      renderedInterfaces = interfaces.normalizedInterfacesForUnit {
        inherit unitName containerName;
        interfaces = runtimeTarget.interfaces or { };
      };

      primaryHostBridgeInterfaceNames = lib.filter (
        ifName: renderedInterfaces.${ifName}.usePrimaryHostBridge or false
      ) (lookup.sortedAttrNames renderedInterfaces);

      primaryHostBridge =
        if builtins.length primaryHostBridgeInterfaceNames == 1 then
          renderedInterfaces.${builtins.head primaryHostBridgeInterfaceNames}.renderedHostBridgeName
        else
          null;

      roleName = lookup.roleForUnit unitName;
      roleConfig = lookup.roleConfigForUnit unitName;
      containerConfig = lookup.containerConfigForUnit unitName;

      profilePath = if containerConfig ? profilePath then containerConfig.profilePath else null;

      additionalCapabilities =
        if
          containerConfig ? additionalCapabilities && builtins.isList containerConfig.additionalCapabilities
        then
          containerConfig.additionalCapabilities
        else
          [ ];

      bindMounts =
        if containerConfig ? bindMounts && builtins.isAttrs containerConfig.bindMounts then
          containerConfig.bindMounts
        else
          { };

      allowedDevices =
        if containerConfig ? allowedDevices && builtins.isList containerConfig.allowedDevices then
          containerConfig.allowedDevices
        else
          [ ];

      interfaceNames = lookup.sortedAttrNames renderedInterfaces;

      interfaceNameFor =
        ifName:
        let
          iface = renderedInterfaces.${ifName};
        in
        if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
          iface.containerInterfaceName
        else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
          iface.hostInterfaceName
        else
          ifName;

      wanInterfaceNames = map interfaceNameFor (
        lib.filter (ifName: renderedInterfaces.${ifName}.sourceKind == "wan") interfaceNames
      );

      lanInterfaceNames = map interfaceNameFor (
        lib.filter (ifName: renderedInterfaces.${ifName}.sourceKind != "wan") interfaceNames
      );
    in
    {
      inherit
        bindMounts
        allowedDevices
        additionalCapabilities
        roleConfig
        roleName
        runtimeTarget
        renderedInterfaces
        wanInterfaceNames
        lanInterfaceNames
        ;

      deploymentHostName = lookup.deploymentHostName;
      hostContext = lookup.hostContext;
      unitKey = unitName;
      unitName = emittedUnitName;
      inherit containerName;
      profilePath = profilePath;
      hostBridge = primaryHostBridge;
      interfaces = renderedInterfaces;
      loopback = runtimeTarget.loopback or { };
      veths = interfaces.vethsForInterfaces renderedInterfaces;
    };

  renderedContainers = builtins.listToAttrs (
    map (unitName: {
      name = naming.emittedUnitNameForUnit unitName;
      value = mkContainerRuntime unitName;
    }) lookup.enabledUnits
  );
in
builtins.seq naming.validateUniqueEmittedRuntimeUnitNames renderedContainers
