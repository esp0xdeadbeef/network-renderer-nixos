{
  lib,
  containerModel,
  uplinks,
  wanUplinkName,
}:

let
  hostBridge =
    if containerModel ? hostBridge && builtins.isString containerModel.hostBridge then
      containerModel.hostBridge
    else
      null;

  matchingUplinks =
    lib.filterAttrs (
      _: uplink:
      builtins.isAttrs uplink
      && builtins.isString (uplink.bridge or null)
      && uplink.bridge == hostBridge
    ) uplinks;

  selectedUplink =
    if
      wanUplinkName != null
      && builtins.hasAttr wanUplinkName matchingUplinks
    then
      matchingUplinks.${wanUplinkName}
    else if builtins.length (builtins.attrNames matchingUplinks) == 1 then
      matchingUplinks.${builtins.head (builtins.attrNames matchingUplinks)}
    else
      { };

  ipv4Enabled = selectedUplink ? ipv4 && (selectedUplink.ipv4.enable or false);
  ipv4Dhcp = ipv4Enabled && (selectedUplink.ipv4.dhcp or false);
  ipv6Enabled = selectedUplink ? ipv6 && (selectedUplink.ipv6.enable or false);
  ipv6Dhcp = ipv6Enabled && (selectedUplink.ipv6.dhcp or false);
  ipv6AcceptRA = ipv6Enabled && (selectedUplink.ipv6.acceptRA or false);

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
if hostBridge != null && selectedUplink != { } then
  {
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = dhcpMode;
        IPv6AcceptRA = ipv6AcceptRA;
        LinkLocalAddressing = if ipv6AcceptRA || ipv6Dhcp then "ipv6" else "no";
      };
    };
    ipv6AcceptRAInterfaces = lib.optionals ipv6AcceptRA [ "eth0" ];
  }
else
  {
    networks = { };
    ipv6AcceptRAInterfaces = [ ];
  }
