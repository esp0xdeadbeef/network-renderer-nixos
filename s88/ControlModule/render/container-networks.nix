{
  lib,
  containerModel,
  uplinks,
  wanUplinkName,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);
  networkManagerInterfaces =
    if
      containerModel ? networkManagerWanInterfaces
      && builtins.isList containerModel.networkManagerWanInterfaces
    then
      lib.filter builtins.isString containerModel.networkManagerWanInterfaces
    else
      [ ];

  hasIpv6Address = address: builtins.isString address && lib.hasInfix ":" address;

  interfaceNameFor =
    iface:
    if iface ? containerInterfaceName && builtins.isString iface.containerInterfaceName then
      iface.containerInterfaceName
    else if iface ? interfaceName && builtins.isString iface.interfaceName then
      iface.interfaceName
    else if iface ? hostInterfaceName && builtins.isString iface.hostInterfaceName then
      iface.hostInterfaceName
    else if iface ? ifName && builtins.isString iface.ifName then
      iface.ifName
    else
      throw ''
        s88/CM/network/render/container-networks.nix: could not resolve container interface name

        iface:
        ${builtins.toJSON iface}
      '';

  stringHasPrefix = prefix: value: builtins.isString value && lib.hasPrefix prefix value;

  downstreamPairKeyFor =
    name:
    if stringHasPrefix "access-" name then
      builtins.substring 7 (builtins.stringLength name - 7) name
    else if stringHasPrefix "policy-" name then
      builtins.substring 7 (builtins.stringLength name - 7) name
    else
      null;

  policyTenantKeyFor =
    name:
    let
      normalizeTenantKey =
        raw:
        if raw == "adm" || raw == "admin" then
          "admin"
        else if raw == "cli" || raw == "client" then
          "client"
        else if raw == "cl2" || raw == "client2" then
          "client2"
        else if raw == "mgt" || raw == "mgmt" then
          "mgmt"
        else if raw == "med" || raw == "media" then
          "media"
        else if raw == "prn" || raw == "printer" then
          "printer"
        else if raw == "nas" then
          "nas"
        else if raw == "iot" then
          "iot"
        else if raw == "branch" then
          "branch"
        else if raw == "hostile" then
          "hostile"
        else
          raw;
      takeTenantSegment =
        prefix:
        let
          stripped = builtins.substring (builtins.stringLength prefix) (
            builtins.stringLength name - builtins.stringLength prefix
          ) name;
          parts = lib.splitString "-" stripped;
        in
        if parts == [ ] then null else normalizeTenantKey (builtins.elemAt parts 0);
    in
    if stringHasPrefix "downstr-" name then
      normalizeTenantKey (builtins.substring 8 (builtins.stringLength name - 8) name)
    else if stringHasPrefix "downstream-" name then
      normalizeTenantKey (builtins.substring 11 (builtins.stringLength name - 11) name)
    else if stringHasPrefix "down-" name then
      takeTenantSegment "down-"
    else if stringHasPrefix "up-" name then
      takeTenantSegment "up-"
    else if stringHasPrefix "upstream-" name then
      takeTenantSegment "upstream-"
    else
      null;

  isDownstreamSelectorAccessInterface = name: stringHasPrefix "access-" name;

  isDownstreamSelectorPolicyInterface = name: stringHasPrefix "policy-" name;

  isDownstreamSelectorInterface =
    name: isDownstreamSelectorAccessInterface name || isDownstreamSelectorPolicyInterface name;

  isUpstreamSelectorCoreInterface = name: name == "core" || stringHasPrefix "core-" name;

  isUpstreamSelectorPolicyInterface =
    name: stringHasPrefix "pol-" name || stringHasPrefix "policy-" name;

  isPolicyDownstreamInterface =
    name:
    stringHasPrefix "downstr-" name
    || stringHasPrefix "downstream-" name
    || stringHasPrefix "down-" name;

  isPolicyUpstreamInterface = name: stringHasPrefix "up-" name || stringHasPrefix "upstream-" name;

  isOverlayInterface = name: stringHasPrefix "overlay-" name;

  isCoreTransitInterface = name: name == "upstream" || stringHasPrefix "upstream-" name;

  mkRoute =
    route:
    if !builtins.isAttrs route then
      null
    else
      let
        destination = if route ? dst && route.dst != null then route.dst else null;
        destinationIsIpv6 = builtins.isString destination && lib.hasInfix ":" destination;
        gateway =
          if destinationIsIpv6 && route ? via6 && route.via6 != null then
            route.via6
          else if destinationIsIpv6 && route ? via4 && route.via4 != null then
            route.via4
          else if route ? via4 && route.via4 != null then
            route.via4
          else if route ? via6 && route.via6 != null then
            route.via6
          else
            null;
      in
      if gateway == null then
        if route ? scope && route.scope == "link" && builtins.isString destination && destination != "" then
          {
            Destination = destination;
            Scope = "link";
          }
        else
          null
      else
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (destination != null) {
          Destination = destination;
        }
        // lib.optionalAttrs (route ? table && builtins.isInt route.table) {
          Table = route.table;
        }
        // lib.optionalAttrs (route ? metric && builtins.isInt route.metric) {
          Metric = route.metric;
        };

  mkDynamicWanNetworkConfig =
    iface:
    let
      isWan = (iface.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];
      hasStaticIpv6 = lib.any hasIpv6Address addresses;

      assignedUplink =
        if
          isWan
          && iface ? assignedUplinkName
          && iface.assignedUplinkName != null
          && builtins.hasAttr iface.assignedUplinkName uplinks
        then
          uplinks.${iface.assignedUplinkName}
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
        LinkLocalAddressing = if hasStaticIpv6 then "ipv6" else "no";
      };

  needsIpv6AcceptRA =
    iface:
    let
      isWan = (iface.sourceKind or null) == "wan";

      assignedUplink =
        if
          isWan
          && iface ? assignedUplinkName
          && iface.assignedUplinkName != null
          && builtins.hasAttr iface.assignedUplinkName uplinks
        then
          uplinks.${iface.assignedUplinkName}
        else if isWan && wanUplinkName != null && builtins.hasAttr wanUplinkName uplinks then
          uplinks.${wanUplinkName}
        else
          { };
    in
    isWan
    && assignedUplink ? ipv6
    && builtins.isAttrs assignedUplink.ipv6
    && (assignedUplink.ipv6.enable or false)
    && (assignedUplink.ipv6.acceptRA or false);

  loopback = containerModel.loopback or { };

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

  interfaces = containerModel.interfaces or { };
  interfaceNames = sortedAttrNames interfaces;
  renderedInterfaceNames = builtins.listToAttrs (
    map (ifName: {
      name = ifName;
      value = interfaceNameFor interfaces.${ifName};
    }) interfaceNames
  );
  runtimeTarget =
    if containerModel ? runtimeTarget && builtins.isAttrs containerModel.runtimeTarget then
      containerModel.runtimeTarget
    else
      { };
  advertisements =
    if runtimeTarget ? advertisements && builtins.isAttrs runtimeTarget.advertisements then
      runtimeTarget.advertisements
    else
      { };
  ipv6RaAdvertisements =
    if advertisements ? ipv6Ra && builtins.isList advertisements.ipv6Ra then
      lib.filter (entry: builtins.isAttrs entry && (entry.enabled or true) != false) advertisements.ipv6Ra
    else
      [ ];
  interfaceKeyForAdvertisedInterface =
    name:
    if !(builtins.isString name) || name == "" then
      null
    else
      let
        matches = lib.filter (
          ifName: ifName == name || renderedInterfaceNames.${ifName} == name
        ) interfaceNames;
      in
      if matches == [ ] then null else builtins.head matches;
  advertisedOnlinkRoutesByInterface = builtins.foldl' (
    acc: adv:
    let
      rawInterface =
        if builtins.isString (adv.interface or null) && adv.interface != "" then
          adv.interface
        else if builtins.isString (adv.bindInterface or null) && adv.bindInterface != "" then
          adv.bindInterface
        else
          null;
      ifName = interfaceKeyForAdvertisedInterface rawInterface;
      prefixes =
        if adv ? prefixes && builtins.isList adv.prefixes then
          lib.filter builtins.isString adv.prefixes
        else
          [ ];
      routes = map (prefix: {
        dst = prefix;
        scope = "link";
      }) prefixes;
    in
    if ifName == null || routes == [ ] then
      acc
    else
      acc // { ${ifName} = (acc.${ifName} or [ ]) ++ routes; }
  ) { } ipv6RaAdvertisements;
  isSelector =
    lib.any (name: isDownstreamSelectorAccessInterface renderedInterfaceNames.${name}) interfaceNames
    && lib.any (
      name: isDownstreamSelectorPolicyInterface renderedInterfaceNames.${name}
    ) interfaceNames;
  isUpstreamSelector =
    lib.any (name: isUpstreamSelectorCoreInterface renderedInterfaceNames.${name}) interfaceNames
    && lib.any (name: isUpstreamSelectorPolicyInterface renderedInterfaceNames.${name}) interfaceNames;
  isPolicy =
    lib.any (name: isPolicyDownstreamInterface renderedInterfaceNames.${name}) interfaceNames
    && lib.any (name: isPolicyUpstreamInterface renderedInterfaceNames.${name}) interfaceNames;
  keepInterfaceRoutesInMain = !(isSelector || isUpstreamSelector || isPolicy);
  policyRoutingByInterface =
    builtins.foldl'
      (
        acc: entry:
        let
          index = entry.index;
          ifName = entry.ifName;
          interfaceName = renderedInterfaceNames.${ifName};
          tableId = 2000 + index;
          sourceIfNames = routeSourceInterfacesFor interfaceName;
          tableRoutesForSource =
            sourceIfName:
            let
              sourceIface = interfaces.${sourceIfName} or { };
            in
            lib.filter (route: route != null) (
              map (route: if builtins.isAttrs route then mkRoute (route // { table = tableId; }) else null) (
                sourceIface.routes or [ ]
              )
            );
          rulesForTarget =
            if sourceIfNames == [ ] then
              [ ]
            else
              [
                {
                  Family = "both";
                  IncomingInterface = interfaceName;
                  Priority = tableId;
                  Table = 254;
                  SuppressPrefixLength = 0;
                }
                {
                  Family = "both";
                  IncomingInterface = interfaceName;
                  Priority = 10000 + tableId;
                  Table = tableId;
                }
              ];
          routesByInterface = builtins.foldl' (
            routesAcc: sourceIfName:
            routesAcc
            // {
              ${sourceIfName} = (routesAcc.${sourceIfName} or [ ]) ++ tableRoutesForSource sourceIfName;
            }
          ) { } sourceIfNames;
        in
        {
          routes = builtins.foldl' (
            routesAcc: sourceIfName:
            routesAcc
            // {
              ${sourceIfName} = (routesAcc.${sourceIfName} or [ ]) ++ (routesByInterface.${sourceIfName} or [ ]);
            }
          ) acc.routes (builtins.attrNames routesByInterface);
          rules = acc.rules // {
            ${ifName} = (acc.rules.${ifName} or [ ]) ++ rulesForTarget;
          };
        }
      )
      {
        routes = { };
        rules = { };
      }
      (
        lib.imap0 (index: ifName: {
          inherit index ifName;
        }) interfaceNames
      );

  routeSourceInterfacesFor =
    targetName:
    let
      pairKey = downstreamPairKeyFor targetName;
      pairPrefix =
        if stringHasPrefix "access-" targetName then
          "policy-"
        else if stringHasPrefix "policy-" targetName then
          "access-"
        else
          null;
      tenantKey = policyTenantKeyFor targetName;
    in
    if isSelector && pairKey != null && pairPrefix != null then
      lib.filter (name: renderedInterfaceNames.${name} == "${pairPrefix}${pairKey}") interfaceNames
    else if isUpstreamSelector && isUpstreamSelectorCoreInterface targetName then
      lib.filter (
        name:
        let
          renderedName = renderedInterfaceNames.${name};
        in
        isUpstreamSelectorPolicyInterface renderedName
      ) interfaceNames
    else if isUpstreamSelector && isUpstreamSelectorPolicyInterface targetName then
      lib.filter (
        name:
        let
          renderedName = renderedInterfaceNames.${name};
        in
        isUpstreamSelectorCoreInterface renderedName
      ) interfaceNames
    else if isPolicy && tenantKey != null && isPolicyDownstreamInterface targetName then
      lib.filter (
        name:
        let
          renderedName = renderedInterfaceNames.${name};
        in
        isPolicyDownstreamInterface renderedName
        || (isPolicyUpstreamInterface renderedName && policyTenantKeyFor renderedName == tenantKey)
      ) interfaceNames
    else if isPolicy && tenantKey != null && isPolicyUpstreamInterface targetName then
      lib.filter (
        name:
        let
          renderedName = renderedInterfaceNames.${name};
        in
        ((isPolicyDownstreamInterface renderedName) && policyTenantKeyFor renderedName == tenantKey)
        || (isPolicyUpstreamInterface renderedName && policyTenantKeyFor renderedName == tenantKey)
      ) interfaceNames
    else if isOverlayInterface targetName then
      lib.unique (
        (lib.filter (name: renderedInterfaceNames.${name} == targetName) interfaceNames)
        ++ (lib.filter (name: isCoreTransitInterface renderedInterfaceNames.${name}) interfaceNames)
      )
    else if isCoreTransitInterface targetName then
      lib.unique (
        (lib.filter (name: renderedInterfaceNames.${name} == targetName) interfaceNames)
        ++ (lib.filter (name: isOverlayInterface renderedInterfaceNames.${name}) interfaceNames)
      )
    else
      lib.filter (name: renderedInterfaceNames.${name} == targetName) interfaceNames;

  interfaceUnits = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      lib.imap0 (
        index: ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
          rawRoutes = (iface.routes or [ ]) ++ (advertisedOnlinkRoutesByInterface.${ifName} or [ ]);
          routes =
            (lib.optionals keepInterfaceRoutesInMain (
              lib.filter (route: route != null) (map mkRoute rawRoutes)
            ))
            ++ (policyRoutingByInterface.routes.${ifName} or [ ]);
          routingPolicyRules = policyRoutingByInterface.rules.${ifName} or [ ];
          dynamicWanNetworkConfig = mkDynamicWanNetworkConfig iface;
        in
        if builtins.elem interfaceName networkManagerInterfaces then
          null
        else
          {
            name = "10-${interfaceName}";
            value = {
              matchConfig.Name = interfaceName;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              }
              // dynamicWanNetworkConfig;
              address = iface.addresses or [ ];
              routes = routes;
              routingPolicyRules = routingPolicyRules;
            };
          }
      ) interfaceNames
    )
  );
  ipv6AcceptRAInterfaces = map interfaceNameFor (
    lib.filter (
      iface:
      let
        interfaceName = interfaceNameFor iface;
      in
      needsIpv6AcceptRA iface && !(builtins.elem interfaceName networkManagerInterfaces)
    ) (builtins.attrValues interfaces)
  );
in
{
  networks = loopbackUnit // interfaceUnits;
  ipv6AcceptRAInterfaces = ipv6AcceptRAInterfaces;
}
