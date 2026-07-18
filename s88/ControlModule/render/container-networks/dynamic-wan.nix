{ lib
, uplinks
, wanUplinkName
, common
,
}:

let
  inherit (common) hasIpv6Address;

  hasIpv4Address = address: builtins.isString address && lib.hasInfix "." address;
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  assignedUplinkFor =
    iface:
    let
      isWan = (iface.sourceKind or null) == "wan";
    in
    if
      isWan
      && iface ? assignedUplinkName
      && iface.assignedUplinkName != null
      && builtins.hasAttr iface.assignedUplinkName uplinks
    then
      uplinks.${iface.assignedUplinkName}
    else if isWan && iface ? assignedUplinkName then
      { }
    else if isWan && wanUplinkName != null && builtins.hasAttr wanUplinkName uplinks then
      uplinks.${wanUplinkName}
    else
      { };

  policyTableFor =
    iface:
    let
      allocation = iface.policyRoutingAllocation or { };
      tableId = allocation.tableId or null;
    in
    if builtins.isInt tableId && tableId > 0 then tableId else null;

  ipv6AcceptRAFor =
    iface:
    let
      assignedUplink = assignedUplinkFor iface;
      pppoeOwned = (iface._s88PppoeOwned or false) == true;
      dynamicAddressing = attrsOrEmpty (iface.dynamicAddressing or null);
      explicitIpv6 = attrsOrEmpty (dynamicAddressing.ipv6 or null);
      hasExplicitDynamic = dynamicAddressing ? ipv6;
      ipv6Contract = if hasExplicitDynamic then explicitIpv6 else attrsOrEmpty (assignedUplink.ipv6 or null);
    in
    !pppoeOwned
    && ((iface.sourceKind or null) == "wan" || hasExplicitDynamic)
    && !(lib.any hasIpv6Address (iface.addresses or [ ]))
    && (ipv6Contract.enable or false)
    && ((ipv6Contract.acceptRA or false) || (ipv6Contract.method or null) == "slaac");
in
{
  mkDynamicWanNetworkConfig =
    iface:
    let
      isWan = (iface.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];
      pppoeOwned = (iface._s88PppoeOwned or false) == true;
      hasStaticIpv4 = lib.any hasIpv4Address addresses;
      hasStaticIpv6 = lib.any hasIpv6Address addresses;
      assignedUplink = assignedUplinkFor iface;
      dynamicAddressing = attrsOrEmpty (iface.dynamicAddressing or null);
      explicitIpv4 = attrsOrEmpty (dynamicAddressing.ipv4 or null);
      explicitIpv6 = attrsOrEmpty (dynamicAddressing.ipv6 or null);
      hasExplicitDynamic = dynamicAddressing ? ipv4 || dynamicAddressing ? ipv6;
      ipv4Contract = if hasExplicitDynamic then explicitIpv4 else attrsOrEmpty (assignedUplink.ipv4 or null);
      ipv6Contract = if hasExplicitDynamic then explicitIpv6 else attrsOrEmpty (assignedUplink.ipv6 or null);
      ipv4Enabled = ipv4Contract ? enable && (ipv4Contract.enable or false);
      ipv4Dhcp =
        ipv4Enabled
        && !pppoeOwned
        && !hasStaticIpv4
        && ((ipv4Contract.dhcp or false) || (ipv4Contract.method or null) == "dhcp");
      ipv6Enabled = ipv6Contract ? enable && (ipv6Contract.enable or false);
      ipv6Dhcp =
        ipv6Enabled
        && !pppoeOwned
        && !hasStaticIpv6
        && ((ipv6Contract.dhcp or false) || (ipv6Contract.method or null) == "dhcp");
      ipv6AcceptRA =
        ipv6Enabled
        && !pppoeOwned
        && !hasStaticIpv6
        && ((ipv6Contract.acceptRA or false) || (ipv6Contract.method or null) == "slaac");
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
    if isWan || hasExplicitDynamic then
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

  mkDynamicWanDhcpV4Config =
    iface: fallbackTableId:
    let
      isWan = (iface.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];
      pppoeOwned = (iface._s88PppoeOwned or false) == true;
      hasStaticIpv4 = lib.any hasIpv4Address addresses;
      assignedUplink = assignedUplinkFor iface;
      dynamicAddressing = attrsOrEmpty (iface.dynamicAddressing or null);
      explicitIpv4 = attrsOrEmpty (dynamicAddressing.ipv4 or null);
      hasExplicitDynamic = dynamicAddressing ? ipv4;
      ipv4Contract = if hasExplicitDynamic then explicitIpv4 else attrsOrEmpty (assignedUplink.ipv4 or null);
      ipv4Enabled = ipv4Contract ? enable && (ipv4Contract.enable or false);
      ipv4Dhcp =
        ipv4Enabled
        && !pppoeOwned
        && !hasStaticIpv4
        && ((ipv4Contract.dhcp or false) || (ipv4Contract.method or null) == "dhcp");
      ifaceTableId = policyTableFor iface;
      tableId = if ifaceTableId != null then ifaceTableId else fallbackTableId;
    in
    if isWan && ipv4Dhcp && tableId != null then
      {
        RouteTable = tableId;
      }
    else
      { };

  mkDynamicWanIpv6AcceptRAConfig =
    iface: fallbackTableId:
    let
      ifaceTableId = policyTableFor iface;
      tableId = if ifaceTableId != null then ifaceTableId else fallbackTableId;
    in
    if ipv6AcceptRAFor iface && tableId != null then
      {
        RouteTable = tableId;
      }
    else
      { };

  needsIpv6AcceptRA = ipv6AcceptRAFor;
}
