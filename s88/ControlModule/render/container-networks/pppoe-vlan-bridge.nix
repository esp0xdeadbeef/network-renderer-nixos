{ lib
, interfaces
, interfaceNames
, renderedInterfaceNames
, uplinks
, wanUplinkName
,
}:

let
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  assignedUplinkFor =
    iface:
    if
      builtins.isString (iface.assignedUplinkName or null)
      && builtins.hasAttr iface.assignedUplinkName uplinks
    then
      uplinks.${iface.assignedUplinkName}
    else if
      (iface.sourceKind or null) == "wan"
      && builtins.isString wanUplinkName
      && builtins.hasAttr wanUplinkName uplinks
    then
      uplinks.${wanUplinkName}
    else
      { };

  pppoeVlanBridgeFor =
    ifName:
    let
      iface = attrsOrEmpty (interfaces.${ifName} or null);
      uplink = assignedUplinkFor iface;
      interfaceName = renderedInterfaceNames.${ifName};
    in
    if
      (iface._s88PppoeOwned or false) == true
      && (uplink.mode or null) == "pppoe"
      && builtins.isInt (uplink.vlan or null)
      && builtins.isString (uplink.bridge or null)
      && uplink.bridge != ""
    then
      {
        logicalInterfaceName = ifName;
        inherit interfaceName;
        vlanId = uplink.vlan;
        vlanInterfaceName = "${interfaceName}.${toString uplink.vlan}";
        bridgeName = uplink.bridge;
      }
    else
      null;

  bridges = lib.filter (entry: entry != null) (map pppoeVlanBridgeFor interfaceNames);
in
{
  bridgeInterfaces = builtins.listToAttrs (
    map
      (entry: {
        name = entry.logicalInterfaceName;
        value = entry;
      })
      bridges
  );

  netdevs = builtins.listToAttrs (
    lib.concatMap
      (entry: [
        {
          name = "10-${entry.vlanInterfaceName}";
          value = {
            netdevConfig = {
              Name = entry.vlanInterfaceName;
              Kind = "vlan";
            };
            vlanConfig.Id = entry.vlanId;
          };
        }
        {
          name = "20-${entry.bridgeName}";
          value.netdevConfig = {
            Name = entry.bridgeName;
            Kind = "bridge";
          };
        }
      ])
      bridges
  );

  networks = builtins.listToAttrs (
    lib.concatMap
      (entry: [
        {
          name = "05-${entry.interfaceName}";
          value = {
            matchConfig.Name = entry.interfaceName;
            networkConfig = {
              ConfigureWithoutCarrier = true;
              DHCP = "no";
              IPv6AcceptRA = false;
              LinkLocalAddressing = "no";
              VLAN = [ entry.vlanInterfaceName ];
            };
          };
        }
        {
          name = "50-${entry.vlanInterfaceName}";
          value = {
            matchConfig.Name = entry.vlanInterfaceName;
            networkConfig = {
              Bridge = entry.bridgeName;
              ConfigureWithoutCarrier = true;
              DHCP = "no";
              IPv6AcceptRA = false;
              LinkLocalAddressing = "no";
            };
          };
        }
        {
          name = "60-${entry.bridgeName}";
          value = {
            matchConfig.Name = entry.bridgeName;
            networkConfig = {
              ConfigureWithoutCarrier = true;
              DHCP = "no";
              IPv6AcceptRA = false;
              LinkLocalAddressing = "no";
            };
          };
        }
      ])
      bridges
  );
}
