{
  lib,
  uplinks,
  wanUplinkName,
  common,
}:

let
  inherit (common) hasIpv6Address;

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
in
{
  mkDynamicWanNetworkConfig =
    iface:
    let
      isWan = (iface.sourceKind or null) == "wan";
      addresses = iface.addresses or [ ];
      hasStaticIpv6 = lib.any hasIpv6Address addresses;
      assignedUplink = assignedUplinkFor iface;
      ipv4Enabled = assignedUplink ? ipv4 && (assignedUplink.ipv4.enable or false);
      ipv4Dhcp = ipv4Enabled && (assignedUplink.ipv4.dhcp or false);
      ipv6Enabled = assignedUplink ? ipv6 && (assignedUplink.ipv6.enable or false);
      ipv6Dhcp = ipv6Enabled && (assignedUplink.ipv6.dhcp or false);
      ipv6AcceptRA = ipv6Enabled && (assignedUplink.ipv6.acceptRA or false);
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
      assignedUplink = assignedUplinkFor iface;
    in
    (iface.sourceKind or null) == "wan"
    && assignedUplink ? ipv6
    && builtins.isAttrs assignedUplink.ipv6
    && (assignedUplink.ipv6.enable or false)
    && (assignedUplink.ipv6.acceptRA or false);
}
