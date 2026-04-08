{ lib }:
bridgeModel:
let
  bridgeNames = builtins.attrNames bridgeModel.bridges;

  parentVlanMap = lib.foldl' (
    acc: bridgeName:
    let
      bridge = bridgeModel.bridges.${bridgeName};
      existing = acc.${bridge.parentBridgeName} or [ ];
    in
    acc
    // {
      ${bridge.parentBridgeName} = existing ++ [ bridge.vlanInterfaceName ];
    }
  ) { } bridgeNames;

  netdevs = builtins.listToAttrs (
    lib.concatMap (
      bridgeName:
      let
        bridge = bridgeModel.bridges.${bridgeName};
      in
      [
        {
          name = bridge.vlanInterfaceName;
          value = {
            netdevConfig = {
              Kind = "vlan";
              Name = bridge.vlanInterfaceName;
            };
            vlanConfig = {
              Id = bridge.vlanId;
            };
          };
        }
        {
          name = bridge.bridgeName;
          value = {
            netdevConfig = {
              Kind = "bridge";
              Name = bridge.bridgeName;
            };
          };
        }
      ]
    ) bridgeNames
  );

  parentNetworks = builtins.listToAttrs (
    map (parentBridgeName: {
      name = "60-${parentBridgeName}-vlans";
      value = {
        matchConfig.Name = parentBridgeName;
        networkConfig.VLAN = lib.unique parentVlanMap.${parentBridgeName};
      };
    }) (builtins.attrNames parentVlanMap)
  );

  childNetworks = builtins.listToAttrs (
    lib.concatMap (
      bridgeName:
      let
        bridge = bridgeModel.bridges.${bridgeName};
      in
      [
        {
          name = "70-${bridge.vlanInterfaceName}";
          value = {
            matchConfig.Name = bridge.vlanInterfaceName;
            networkConfig.Bridge = bridge.bridgeName;
          };
        }
        {
          name = "80-${bridge.bridgeName}";
          value = {
            matchConfig.Name = bridge.bridgeName;
            networkConfig.ConfigureWithoutCarrier = true;
          };
        }
      ]
    ) bridgeNames
  );

  renderedNetworks = parentNetworks // childNetworks;
in
{
  bridgeNameMap = bridgeModel.bridgeNameMap;
  bridges = bridgeModel.bridges;
  netdevs = netdevs;
  networks = renderedNetworks;
  debug = bridgeModel.debug // {
    renderedNetdevs = builtins.attrNames netdevs;
    renderedNetworks = builtins.attrNames renderedNetworks;
  };
}
