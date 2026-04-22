{
  lib,
  lookup,
  naming,
  interfaces,
}:

let
  stripPrefixLength =
    value:
    if !(builtins.isString value) then
      null
    else
      let
        parts = lib.splitString "/" value;
      in
      if builtins.length parts > 0 then builtins.elemAt parts 0 else null;

  firstAddressMatching =
    {
      addresses,
      predicate,
    }:
    let
      values =
        if builtins.isList addresses then
          lib.filter (
            value: builtins.isString value && predicate value && (stripPrefixLength value) != null
          ) addresses
        else
          [ ];
    in
    if values == [ ] then null else stripPrefixLength (builtins.head values);

  overlaySiteNameForInterface =
    iface:
    let
      backingId =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then
          iface.backingRef.id or null
        else
          null;
      parts = if builtins.isString backingId then lib.splitString "::" backingId else [ ];
    in
    if builtins.length parts >= 3 then builtins.elemAt parts 1 else null;

  overlayNameForInterface =
    iface:
    if
      iface ? backingRef
      && builtins.isAttrs iface.backingRef
      && builtins.isString (iface.backingRef.name or null)
    then
      iface.backingRef.name
    else
      null;

  overlayRouteLike =
    route:
    builtins.isAttrs route
    && (
      (builtins.isString (route.proto or null) && route.proto == "overlay")
      || (
        route ? intent
        && builtins.isAttrs route.intent
        && builtins.isString (route.intent.kind or null)
        && route.intent.kind == "overlay-reachability"
      )
    );

  enrichOverlayRoutesForInterface =
    {
      overlayEndpoints,
      iface,
    }:
    let
      ifaceOverlayName = overlayNameForInterface iface;
      routes = if iface ? routes && builtins.isList iface.routes then iface.routes else [ ];
    in
    map (
      route:
      if
        !overlayRouteLike route
        || (route ? via4 && route.via4 != null)
        || (route ? via6 && route.via6 != null)
      then
        route
      else
        let
          peerSite = if route ? peerSite && builtins.isString route.peerSite then route.peerSite else null;
          overlayName =
            if route ? overlay && builtins.isString route.overlay then route.overlay else ifaceOverlayName;
          endpointKey =
            if peerSite != null && overlayName != null then "${peerSite}::${overlayName}" else null;
          nextHop = if endpointKey != null then overlayEndpoints.${endpointKey} or { } else { };
        in
        route
        // lib.optionalAttrs (!(route ? via4) && nextHop ? via4 && nextHop.via4 != null) {
          via4 = nextHop.via4;
        }
        // lib.optionalAttrs (!(route ? via6) && nextHop ? via6 && nextHop.via6 != null) {
          via6 = nextHop.via6;
        }
    ) routes;

  enrichOverlayRoutesForContainer =
    {
      overlayEndpoints,
      containerRuntime,
    }:
    let
      interfacesRaw = containerRuntime.interfaces or { };
      interfaces = builtins.mapAttrs (
        _: iface:
        if (iface.sourceKind or null) == "overlay" then
          iface
          // {
            routes = enrichOverlayRoutesForInterface {
              inherit overlayEndpoints iface;
            };
          }
        else
          iface
      ) interfacesRaw;
    in
    containerRuntime
    // {
      interfaces = interfaces;
      renderedInterfaces = interfaces;
    };

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

      networkManagerWanInterfaces = map interfaceNameFor (
        lib.filter (
          ifName:
          let
            iface = renderedInterfaces.${ifName};
          in
          (iface.usePrimaryHostBridge or false) && iface.sourceKind == "wan"
        ) interfaceNames
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
        networkManagerWanInterfaces
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

  renderedContainersBase = builtins.listToAttrs (
    map (unitName: {
      name = naming.emittedUnitNameForUnit unitName;
      value = mkContainerRuntime unitName;
    }) lookup.enabledUnits
  );

  overlayEndpoints = builtins.foldl' (
    acc: containerRuntime:
    let
      interfaces = containerRuntime.interfaces or { };
    in
    builtins.foldl' (
      inner: ifName:
      let
        iface = interfaces.${ifName};
        siteName = overlaySiteNameForInterface iface;
        overlayName = overlayNameForInterface iface;
        key = if siteName != null && overlayName != null then "${siteName}::${overlayName}" else null;
        via4 = firstAddressMatching {
          addresses = iface.addresses or [ ];
          predicate = value: !(lib.hasInfix ":" value);
        };
        via6 = firstAddressMatching {
          addresses = iface.addresses or [ ];
          predicate = value: lib.hasInfix ":" value;
        };
      in
      if (iface.sourceKind or null) != "overlay" || key == null then
        inner
      else
        inner
        // {
          ${key} = {
            inherit via4 via6;
          };
        }
    ) acc (lookup.sortedAttrNames interfaces)
  ) { } (builtins.attrValues renderedContainersBase);

  renderedContainers = builtins.mapAttrs (
    _: containerRuntime:
    enrichOverlayRoutesForContainer {
      inherit overlayEndpoints containerRuntime;
    }
  ) renderedContainersBase;

in
builtins.seq naming.validateUniqueEmittedRuntimeUnitNames (renderedContainers)
