{
  lib,
  lookup,
  naming,
  interfaces,
}:

let
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
      originalInterfaces =
        if originalRuntimeTarget ? interfaces && builtins.isAttrs originalRuntimeTarget.interfaces && originalRuntimeTarget.interfaces != { } then
          originalRuntimeTarget.interfaces
        else
          (originalRuntimeTarget.effectiveRuntimeRealization or { }).interfaces or { };
    in
    originalRuntimeTarget
    // {
      runtimeTargetId = emittedUnitName;
      deploymentHostName = lookup.deploymentHostName;
      logicalNode = originalLogicalNode // { name = emittedUnitName; };
      interfaces = builtins.mapAttrs (_: iface: iface // { runtimeTarget = emittedUnitName; }) originalInterfaces;
    };

  siteFor =
    siteData: runtimeTarget:
    let
      logicalNode = if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then runtimeTarget.logicalNode else { };
      enterpriseName = if builtins.isString (logicalNode.enterprise or null) then logicalNode.enterprise else null;
      siteName = if builtins.isString (logicalNode.site or null) then logicalNode.site else null;
      enterpriseSites = if enterpriseName != null && builtins.hasAttr enterpriseName siteData then siteData.${enterpriseName} else { };
    in
    if siteName != null && builtins.isAttrs enterpriseSites && builtins.hasAttr siteName enterpriseSites then
      enterpriseSites.${siteName}
    else
      { };

  interfaceNameFor =
    iface:
    if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
      iface.containerInterfaceName
    else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
      iface.hostInterfaceName
    else
      null;
in
{
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
      interfaceNames = lookup.sortedAttrNames renderedInterfaces;
      primaryHostBridgeInterfaceNames = lib.filter (
        ifName: renderedInterfaces.${ifName}.usePrimaryHostBridge or false
      ) interfaceNames;
      primaryHostBridge =
        if builtins.length primaryHostBridgeInterfaceNames == 1 then
          renderedInterfaces.${builtins.head primaryHostBridgeInterfaceNames}.renderedHostBridgeName
        else
          null;
      roleName = lookup.roleForUnit unitName;
      roleConfig = lookup.roleConfigForUnit unitName;
      containerConfig = lookup.containerConfigForUnit unitName;
      ifNameFor = ifName: let resolved = interfaceNameFor renderedInterfaces.${ifName}; in if resolved != null then resolved else ifName;
    in
    {
      inherit roleConfig roleName runtimeTarget renderedInterfaces;
      bindMounts = if containerConfig ? bindMounts && builtins.isAttrs containerConfig.bindMounts then containerConfig.bindMounts else { };
      allowedDevices = if containerConfig ? allowedDevices && builtins.isList containerConfig.allowedDevices then containerConfig.allowedDevices else [ ];
      additionalCapabilities = if containerConfig ? additionalCapabilities && builtins.isList containerConfig.additionalCapabilities then containerConfig.additionalCapabilities else [ ];
      wanInterfaceNames = map ifNameFor (lib.filter (ifName: renderedInterfaces.${ifName}.sourceKind == "wan") interfaceNames);
      lanInterfaceNames = map ifNameFor (lib.filter (ifName: renderedInterfaces.${ifName}.sourceKind != "wan") interfaceNames);
      networkManagerWanInterfaces = map ifNameFor (
        lib.filter (
          ifName:
          let iface = renderedInterfaces.${ifName};
          in (iface.usePrimaryHostBridge or false) && iface.sourceKind == "wan" && builtins.isString (iface.assignedUplinkName or null)
        ) interfaceNames
      );
      site = siteFor lookup.siteData runtimeTarget;
      inventorySite = siteFor lookup.inventorySiteData runtimeTarget;
      deploymentHostName = lookup.deploymentHostName;
      hostContext = lookup.hostContext;
      unitKey = unitName;
      unitName = emittedUnitName;
      inherit containerName;
      profilePath = if containerConfig ? profilePath then containerConfig.profilePath else null;
      hostBridge = primaryHostBridge;
      interfaces = renderedInterfaces;
      loopback = runtimeTarget.loopback or { };
      veths = interfaces.vethsForInterfaces renderedInterfaces;
    };
}
