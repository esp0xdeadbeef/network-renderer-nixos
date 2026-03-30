{
  lib,
  containerModel,
  uplinks,
  wanUplinkName,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

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
    iface:
    let
      isWan = (iface.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];

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
        LinkLocalAddressing = "no";
      };

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

  interfaceUnits = builtins.listToAttrs (
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        routes = lib.filter (route: route != null) (map mkRoute (iface.routes or [ ]));
        dynamicWanNetworkConfig = mkDynamicWanNetworkConfig iface;
      in
      {
        name = "10-${iface.interfaceName}";
        value = {
          matchConfig.Name = iface.interfaceName;
          networkConfig = {
            ConfigureWithoutCarrier = true;
          }
          // dynamicWanNetworkConfig;
          address = iface.addresses or [ ];
          routes = routes;
        };
      }
    ) (sortedAttrNames interfaces)
  );
in
loopbackUnit // interfaceUnits
