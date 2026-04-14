{ lib }:
hostModel:
let
  uplinkNames = builtins.attrNames hostModel.uplinks;

  keepaliveNameFor = bridgeName: "ka-${bridgeName}";

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
            name = uplink.vlanInterfaceName;
            value = {
              netdevConfig = {
                Kind = "vlan";
                Name = uplink.vlanInterfaceName;
              };
              vlanConfig = {
                Id = uplink.vlanId;
              };
            };
          }
          {
            name = uplink.bridgeName;
            value = {
              netdevConfig = {
                Kind = "bridge";
                Name = uplink.bridgeName;
              };
            };
          }
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
        [
          {
            name = uplink.bridgeName;
            value = {
              netdevConfig = {
                Kind = "bridge";
                Name = uplink.bridgeName;
              };
            };
          }
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
    ) uplinkNames
  );

  parentNetworks = builtins.listToAttrs (
    map (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
      in
      {
        name = "10-${uplink.parent}-${uplinkName}";
        value =
          if uplink.kind == "vlan-bridge" then
            {
              matchConfig.Name = uplink.parent;
              networkConfig.VLAN = [ uplink.vlanInterfaceName ];
            }
          else
            {
              matchConfig.Name = uplink.parent;
              networkConfig.Bridge = uplink.bridgeName;
            };
      }
    ) uplinkNames
  );

  keepaliveNetworks = builtins.listToAttrs (
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
    ) uplinkNames
  );

  childNetworks = builtins.listToAttrs (
    lib.concatMap (
      uplinkName:
      let
        uplink = hostModel.uplinks.${uplinkName};
      in
      if uplink.kind == "vlan-bridge" then
        [
          {
            name = "20-${uplink.vlanInterfaceName}";
            value = {
              matchConfig.Name = uplink.vlanInterfaceName;
              networkConfig.Bridge = uplink.bridgeName;
            };
          }
          {
            name = "30-${uplink.bridgeName}";
            value = {
              matchConfig.Name = uplink.bridgeName;
              networkConfig = uplink.networkOptions // {
                ConfigureWithoutCarrier = true;
              };
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
            };
          }
        ]
      else
        [
          {
            name = "20-${uplink.bridgeName}";
            value = {
              matchConfig.Name = uplink.bridgeName;
              networkConfig = uplink.networkOptions // {
                ConfigureWithoutCarrier = true;
              };
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
            };
          }
        ]
    ) uplinkNames
  );

  renderedNetworks = parentNetworks // keepaliveNetworks // childNetworks;
in
{
  hostName = hostModel.hostName;
  deploymentHostName = hostModel.deploymentHostName;
  netdevs = netdevs;
  networks = renderedNetworks;
  debug = hostModel.debug // {
    renderedNetdevs = builtins.attrNames netdevs;
    renderedNetworks = builtins.attrNames renderedNetworks;
  };
}
