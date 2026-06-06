{ lib
, lookup
, naming
, interfaces
,
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
      runtimeInterfaces =
        if originalRuntimeTarget ? interfaces && builtins.isAttrs originalRuntimeTarget.interfaces && originalRuntimeTarget.interfaces != { } then
          originalRuntimeTarget.interfaces
        else
          { };
      effectiveInterfaces =
        if
          originalRuntimeTarget ? effectiveRuntimeRealization
          && builtins.isAttrs originalRuntimeTarget.effectiveRuntimeRealization
          && builtins.isAttrs (originalRuntimeTarget.effectiveRuntimeRealization.interfaces or null)
        then
          originalRuntimeTarget.effectiveRuntimeRealization.interfaces
        else
          { };
      interfaceNamesForAssembly =
        if runtimeInterfaces != { } then
          builtins.attrNames runtimeInterfaces
        else
          builtins.attrNames effectiveInterfaces;
      originalInterfaces =
        builtins.listToAttrs (
          map
            (
              ifName:
              let
                effectiveIface = effectiveInterfaces.${ifName} or { };
                runtimeIface = runtimeInterfaces.${ifName} or { };
                effectiveMtu = effectiveIface.mtu or null;
                runtimeMtu = runtimeIface.mtu or null;
                baseIface =
                  if runtimeInterfaces != { } then
                    runtimeIface
                  else
                    effectiveIface;
              in
              {
                name = ifName;
                value = baseIface // lib.optionalAttrs (builtins.isInt runtimeMtu || builtins.isInt effectiveMtu) {
                  mtu = if builtins.isInt runtimeMtu then runtimeMtu else effectiveMtu;
                };
              }
            )
            (lib.sort builtins.lessThan interfaceNamesForAssembly)
        );
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

  hasPppoeService =
    runtimeTarget:
    let pppoe = (runtimeTarget.services or { }).pppoe or { };
    in builtins.isAttrs pppoe && (builtins.isAttrs (pppoe.client or null) || builtins.isAttrs (pppoe.server or null));

  pppoeCredentialPaths =
    runtimeTarget:
    let
      pppoe = (runtimeTarget.services or { }).pppoe or { };
      credentialPathsFor =
        config:
        let credentials = if builtins.isAttrs (config.credentials or null) then config.credentials else { };
        in lib.filter (path: builtins.isString path && path != "") [
          (credentials.usernameFile or null)
          (credentials.passwordFile or null)
        ];
    in
    lib.unique (
      (if builtins.isAttrs (pppoe.client or null) then credentialPathsFor pppoe.client else [ ])
      ++ (if builtins.isAttrs (pppoe.server or null) then credentialPathsFor pppoe.server else [ ])
    );
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
      policyRoutingSources = runtimeTarget.policyRoutingSources or { };
      networkBehavior = runtimeTarget.networkBehavior or { keepInterfaceRoutesInMain = true; };
      interfaceNames = lookup.sortedAttrNames renderedInterfaces;
      primaryHostBridgeInterfaceNames = lib.filter
        (
          ifName: renderedInterfaces.${ifName}.usePrimaryHostBridge or false
        )
        interfaceNames;
      primaryHostBridge =
        if builtins.length primaryHostBridgeInterfaceNames == 1 then
          renderedInterfaces.${builtins.head primaryHostBridgeInterfaceNames}.renderedHostBridgeName
        else
          null;
      roleName = lookup.roleForUnit unitName;
      roleConfig = lookup.roleConfigForUnit unitName;
      containerConfig = lookup.containerConfigForUnit unitName;
      site = siteFor lookup.siteData runtimeTarget;
      pppoeEnabled = hasPppoeService runtimeTarget;
      pppDeviceBindMounts = lib.optionalAttrs pppoeEnabled {
        "/dev/ppp" = {
          hostPath = "/dev/ppp";
          isReadOnly = false;
        };
      };
      pppoeCredentialBindMounts = lib.genAttrs (pppoeCredentialPaths runtimeTarget) (path: {
        hostPath = path;
        isReadOnly = true;
      });
      pppAllowedDevices = lib.optionals pppoeEnabled [
        {
          node = "/dev/ppp";
          modifier = "rw";
        }
      ];
      ifNameFor = ifName: let resolved = interfaceNameFor renderedInterfaces.${ifName}; in if resolved != null then resolved else ifName;
    in
    {
      inherit roleConfig roleName runtimeTarget renderedInterfaces;
      bindMounts =
        (if containerConfig ? bindMounts && builtins.isAttrs containerConfig.bindMounts then containerConfig.bindMounts else { })
        // pppDeviceBindMounts
        // pppoeCredentialBindMounts;
      allowedDevices =
        (if containerConfig ? allowedDevices && builtins.isList containerConfig.allowedDevices then containerConfig.allowedDevices else [ ])
        ++ pppAllowedDevices;
      additionalCapabilities = if containerConfig ? additionalCapabilities && builtins.isList containerConfig.additionalCapabilities then containerConfig.additionalCapabilities else [ ];
      enableEdgeServices = containerConfig.enableEdgeServices or false;
      firewallPolicyPath = roleConfig.firewallPolicyPath or null;
      assumptionFamily = roleConfig.assumptionFamily or null;
      preferSiteNode = roleConfig.preferSiteNode or false;
      strictEndpointBindings = roleConfig.strictEndpointBindings or false;
      wanInterfaceNames = map ifNameFor (lib.filter (ifName: renderedInterfaces.${ifName}.sourceKind == "wan") interfaceNames);
      lanInterfaceNames = map ifNameFor (lib.filter (ifName: renderedInterfaces.${ifName}.sourceKind != "wan") interfaceNames);
      networkManagerWanInterfaces = map ifNameFor (
        lib.filter
          (
            ifName:
            let iface = renderedInterfaces.${ifName};
            in
            (iface.usePrimaryHostBridge or false)
            && iface.sourceKind == "wan"
            && builtins.isString (iface.assignedUplinkName or null)
            && (iface.addresses or [ ]) == [ ]
            && (iface.routes or [ ]) == [ ]
          )
          interfaceNames
      );
      inherit site;
      inventorySite = siteFor lookup.inventorySiteData runtimeTarget;
      deploymentHostName = lookup.deploymentHostName;
      hostContext = lookup.hostContext;
      unitKey = unitName;
      unitName = emittedUnitName;
      inherit containerName;
      profilePath = if containerConfig ? profilePath then containerConfig.profilePath else null;
      hostBridge = primaryHostBridge;
      interfaces = renderedInterfaces;
      services = runtimeTarget.services or { };
      inherit policyRoutingSources;
      inherit networkBehavior;
      loopback = runtimeTarget.loopback or { };
      veths = interfaces.vethsForInterfaces renderedInterfaces;
    };
}
