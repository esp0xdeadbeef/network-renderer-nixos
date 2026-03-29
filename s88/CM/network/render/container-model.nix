{
  lib,
  hostPlan,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = hostPlan.normalizedRuntimeTargets or { };
  selectedUnits = hostPlan.selectedUnits or [ ];
  selectedRoles = hostPlan.selectedRoles or { };
  unitRoles = hostPlan.unitRoles or { };
  localAttachTargets = hostPlan.localAttachTargets or [ ];
  bridgeNameMap = hostPlan.bridgeNameMap or { };
  uplinks = hostPlan.uplinks or { };
  wanUplinkName = hostPlan.wanUplinkName or null;
  deploymentHostName = hostPlan.deploymentHostName or null;
  hostContext = hostPlan.resolvedHostContext or { };

  roleForUnit = unitName: if builtins.hasAttr unitName unitRoles then unitRoles.${unitName} else null;

  roleConfigForUnit =
    unitName:
    let
      roleName = roleForUnit unitName;
    in
    if roleName != null && builtins.hasAttr roleName selectedRoles then
      selectedRoles.${roleName}
    else
      { };

  containerEnabledForUnit =
    unitName:
    let
      roleConfig = roleConfigForUnit unitName;
    in
    roleConfig ? container
    && builtins.isAttrs roleConfig.container
    && (roleConfig.container.enable or false);

  containerEnabledUnitNames = lib.filter containerEnabledForUnit selectedUnits;

  sourceKindForInterface =
    iface:
    if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? sourceKind
      && builtins.isString iface.connectivity.sourceKind
    then
      iface.connectivity.sourceKind
    else if iface ? sourceKind && builtins.isString iface.sourceKind then
      iface.sourceKind
    else
      null;

  attachTargetForInterface =
    {
      unitName,
      ifName,
      iface,
    }:
    let
      matches = lib.filter (
        target:
        (target.unitName or null) == unitName
        && (
          (target.ifName or null) == ifName
          || ((target.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.hostBridgeName or null) == (iface.hostBridge or null))
        )
      ) localAttachTargets;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else if builtins.hasAttr (iface.hostBridge or "") bridgeNameMap then
      {
        renderedHostBridgeName = bridgeNameMap.${iface.hostBridge};
        assignedUplinkName = null;
      }
    else
      throw ''
        s88/CM/network/render/container-model.nix: could not resolve rendered host bridge for unit '${unitName}', interface '${ifName}'

        iface.hostBridge:
        ${builtins.toJSON (iface.hostBridge or null)}

        available bridgeNameMap keys:
        ${builtins.toJSON (sortedAttrNames bridgeNameMap)}

        attachTargets:
        ${builtins.toJSON localAttachTargets}
      '';

  mkRoute =
    route:
    if !builtins.isAttrs route then
      null
    else
      let
        gateway =
          if route ? via4 && route.via4 != null then
            route.via4
          else if route ? via6 && route.via6 != null then
            route.via6
          else
            null;
      in
      if gateway == null then
        null
      else
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (route ? dst && route.dst != null) {
          Destination = route.dst;
        };

  mkDynamicWanNetworkConfig =
    {
      attachTarget,
      iface,
    }:
    let
      isWan = sourceKindForInterface iface == "wan";
      addresses = iface.addresses or [ ];

      assignedUplink =
        if
          isWan
          && attachTarget != null
          && attachTarget ? assignedUplinkName
          && attachTarget.assignedUplinkName != null
          && builtins.hasAttr attachTarget.assignedUplinkName uplinks
        then
          uplinks.${attachTarget.assignedUplinkName}
        else if isWan && wanUplinkName != null && builtins.hasAttr wanUplinkName uplinks then
          uplinks.${wanUplinkName}
        else
          { };

      ipv4Enabled =
        assignedUplink ? ipv4
        && builtins.isAttrs assignedUplink.ipv4
        && (assignedUplink.ipv4.enable or false);

      ipv4Dhcp =
        ipv4Enabled
        && assignedUplink ? ipv4
        && builtins.isAttrs assignedUplink.ipv4
        && (assignedUplink.ipv4.dhcp or false);

      ipv6Enabled =
        assignedUplink ? ipv6
        && builtins.isAttrs assignedUplink.ipv6
        && (assignedUplink.ipv6.enable or false);

      ipv6Dhcp =
        ipv6Enabled
        && assignedUplink ? ipv6
        && builtins.isAttrs assignedUplink.ipv6
        && (assignedUplink.ipv6.dhcp or false);

      ipv6AcceptRA =
        ipv6Enabled
        && assignedUplink ? ipv6
        && builtins.isAttrs assignedUplink.ipv6
        && (assignedUplink.ipv6.acceptRA or false);

      dhcpMode =
        if ipv4Dhcp && ipv6Dhcp then
          "yes"
        else if ipv4Dhcp then
          "ipv4"
        else if ipv6Dhcp then
          "ipv6"
        else
          "no";
    in
    if isWan && addresses == [ ] then
      {
        DHCP = dhcpMode;
        IPv6AcceptRA = ipv6AcceptRA;
        LinkLocalAddressing = if ipv6AcceptRA || ipv6Dhcp then "ipv6" else "no";
      }
    else
      {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };

  mkContainerNetworks =
    {
      unitName,
      interfaces,
      loopback,
    }:
    let
      interfaceNames = sortedAttrNames interfaces;

      loopbackAddresses = lib.filter builtins.isString [
        (loopback.addr4 or null)
        (loopback.addr6 or null)
      ];

      loopbackUnit = lib.optionalAttrs (loopbackAddresses != [ ]) {
        "00-lo" = {
          matchConfig.Name = "lo";
          address = loopbackAddresses;
          linkConfig.RequiredForOnline = "no";
          networkConfig.ConfigureWithoutCarrier = true;
        };
      };

      interfaceUnits = builtins.listToAttrs (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            renderedName = iface.renderedIfName or ifName;
            attachTarget = attachTargetForInterface {
              inherit unitName ifName iface;
            };
            routes = lib.filter (route: route != null) (map mkRoute (iface.routes or [ ]));
            dynamicWanNetworkConfig = mkDynamicWanNetworkConfig {
              inherit attachTarget iface;
            };
          in
          {
            name = "10-${renderedName}";
            value = {
              matchConfig.Name = renderedName;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              }
              // dynamicWanNetworkConfig;
              address = iface.addresses or [ ];
              routes = routes;
            };
          }
        ) interfaceNames
      );
    in
    loopbackUnit // interfaceUnits;

  mkExtraVeths =
    {
      unitName,
      interfaces,
    }:
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};
          attachTarget = attachTargetForInterface {
            inherit unitName ifName iface;
          };
          containerIfName = iface.renderedIfName or ifName;
          hostIfName = hostNaming.shorten "${unitName}-${containerIfName}";
        in
        {
          name = containerIfName;
          value = {
            hostBridge = attachTarget.renderedHostBridgeName;
            hostInterfaceName = hostIfName;
          };
        }
      ) (sortedAttrNames interfaces)
    );

  mkContainerModel =
    unitName:
    let
      runtimeTarget =
        if builtins.hasAttr unitName normalizedRuntimeTargets then
          normalizedRuntimeTargets.${unitName}
        else
          throw ''
            s88/CM/network/render/container-model.nix: missing normalized runtime target for unit '${unitName}'
          '';

      interfaces = runtimeTarget.interfaces or { };
      loopback = runtimeTarget.loopback or { };

      roleName = roleForUnit unitName;
      roleConfig = roleConfigForUnit unitName;
      containerConfig =
        if roleConfig ? container && builtins.isAttrs roleConfig.container then
          roleConfig.container
        else
          { };

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

      interfaceNames = sortedAttrNames interfaces;

      wanInterfaceNames = map (ifName: interfaces.${ifName}.renderedIfName or ifName) (
        lib.filter (ifName: sourceKindForInterface interfaces.${ifName} == "wan") interfaceNames
      );

      lanInterfaceNames = map (ifName: interfaces.${ifName}.renderedIfName or ifName) (
        lib.filter (ifName: sourceKindForInterface interfaces.${ifName} != "wan") interfaceNames
      );
    in
    {
      inherit
        unitName
        deploymentHostName
        hostContext
        runtimeTarget
        roleName
        roleConfig
        profilePath
        bindMounts
        allowedDevices
        additionalCapabilities
        wanInterfaceNames
        lanInterfaceNames
        ;

      extraVeths = mkExtraVeths {
        inherit unitName interfaces;
      };

      containerNetworks = mkContainerNetworks {
        inherit
          unitName
          interfaces
          loopback
          ;
      };
    };
in
builtins.listToAttrs (
  map (unitName: {
    name = unitName;
    value = mkContainerModel unitName;
  }) containerEnabledUnitNames
)
