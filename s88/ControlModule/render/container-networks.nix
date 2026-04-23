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

  interfaceUnits = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      lib.imap0 (
        index: ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = interfaceNameFor iface;
          tableId = 2000 + index;
          baseRoutes = iface.routes or [ ];
          routes = lib.filter (route: route != null) (map mkRoute baseRoutes);
          policyTableRoutes = lib.filter (route: route != null) (
            map (
              route: if builtins.isAttrs route then mkRoute (route // { table = tableId; }) else null
            ) baseRoutes
          );
          routingPolicyRules =
            if policyTableRoutes == [ ] then
              [ ]
            else
              [
                {
                  IncomingInterface = interfaceName;
                  Priority = tableId;
                  Table = tableId;
                }
              ];
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
              routes = routes ++ policyTableRoutes;
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
