{ lib }:
hostModel:
let
  uplinkNames = builtins.attrNames hostModel.uplinks;

  keepaliveNameFor = bridgeName: "ka-${bridgeName}";

  bridgeUplinkNames = lib.filter (
    uplinkName:
    let
      uplink = hostModel.uplinks.${uplinkName};
    in
    uplink.kind == "bridge" || uplink.kind == "vlan-bridge"
  ) uplinkNames;

  netdevs = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
        keepaliveName = keepaliveNameFor uplink.bridgeName;
      in
      if uplink.kind == "vlan-bridge" then
        [
          {
            name = keepaliveName;
            value = {
              netdevConfig = {
                Kind = "dummy";
                Name = keepaliveName;
              };
            };
          }
        ]
      else if uplink.kind == "bridge" then
        [
          {
            name = keepaliveName;
            value = {
              netdevConfig = {
                Kind = "dummy";
                Name = keepaliveName;
              };
            };
          }
        ]
      else
        [ ]
    ) uplinkNames
  );

  networkingVlans = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
      in
      if uplink.kind == "vlan-bridge" then
        [
          {
            name = uplink.vlanInterfaceName;
            value = {
              id = uplink.vlanId;
              interface = uplink.parent;
            };
          }
        ]
      else
        [ ]
    ) uplinkNames
  );

  networkingBridges = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
      in
      if uplink.kind == "vlan-bridge" then
        [
          {
            name = uplink.bridgeName;
            value = {
              interfaces = [ uplink.vlanInterfaceName ];
            };
          }
        ]
      else if uplink.kind == "bridge" then
        [
          {
            name = uplink.bridgeName;
            value = {
              interfaces = [ uplink.parent ];
            };
          }
        ]
      else
        [ ]
    ) uplinkNames
  );

  renderedNetworks =
    builtins.listToAttrs (
      map (
        uplinkName:
        let
          uplink = hostModel.uplinks.${uplinkName};
          keepaliveName = keepaliveNameFor uplink.bridgeName;

          dhcpValue =
            if uplink.networkOptions ? DHCP then
              uplink.networkOptions.DHCP
            else if uplink.networkOptions ? dhcp then
              uplink.networkOptions.dhcp
            else
              null;

          ipv6AcceptRAValue =
            if uplink.networkOptions ? IPv6AcceptRA then
              uplink.networkOptions.IPv6AcceptRA
            else if uplink.networkOptions ? ipv6AcceptRA then
              uplink.networkOptions.ipv6AcceptRA
            else
              null;

          passthroughNetworkOptions = builtins.removeAttrs uplink.networkOptions [
            "DHCP"
            "dhcp"
            "IPv6AcceptRA"
            "ipv6AcceptRA"
          ];
        in
        {
          name = "30-${uplink.bridgeName}";
          value = {
            matchConfig.Name = uplink.bridgeName;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig =
              passthroughNetworkOptions
              // (lib.optionalAttrs (dhcpValue != null) {
                DHCP = dhcpValue;
              })
              // (lib.optionalAttrs (ipv6AcceptRAValue != null) {
                IPv6AcceptRA = ipv6AcceptRAValue;
              })
              // {
                ConfigureWithoutCarrier = true;
              };
          };
        }
      ) bridgeUplinkNames
    )
    // builtins.listToAttrs (
      map (
        uplinkName:
        let
          uplink = hostModel.uplinks.${uplinkName};
          keepaliveName = keepaliveNameFor uplink.bridgeName;
        in
        {
          name = "15-${keepaliveName}";
          value = {
            matchConfig.Name = keepaliveName;
            networkConfig = {
              Bridge = uplink.bridgeName;
              ConfigureWithoutCarrier = true;
            };
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
          };
        }
      ) bridgeUplinkNames
    );
in
{
  hostName = hostModel.hostName;
  deploymentHostName = hostModel.deploymentHostName;
  netdevs = netdevs;
  networks = renderedNetworks;
  networking = {
    vlans = networkingVlans;
    bridges = networkingBridges;
  };
  debug = hostModel.debug // {
    renderedNetdevs = builtins.attrNames netdevs;
    renderedNetworks = builtins.attrNames renderedNetworks;
    renderedVlans = builtins.attrNames networkingVlans;
    renderedBridges = builtins.attrNames networkingBridges;
  };
}
