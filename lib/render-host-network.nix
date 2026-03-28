{ lib, inventory, hostName, cpm ? null }:

let
  realizationPorts = import ./realization-ports.nix { inherit lib; };

  sortedAttrNames = attrs:
    lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHosts =
    if inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      throw "lib/render-host-network.nix: inventory.deployment.hosts missing";

  deploymentHost =
    if builtins.hasAttr hostName deploymentHosts
      && builtins.isAttrs deploymentHosts.${hostName}
    then
      deploymentHosts.${hostName}
    else
      throw "lib/render-host-network.nix: deployment host '${hostName}' missing";

  uplinks =
    if deploymentHost ? uplinks && builtins.isAttrs deploymentHost.uplinks then
      deploymentHost.uplinks
    else
      { };

  uplinkBridgeNames =
    lib.unique (
      lib.filter
        builtins.isString
        (map
          (uplinkName:
            let
              uplink = uplinks.${uplinkName};
            in
            uplink.bridge or null)
          (sortedAttrNames uplinks))
    );

  localAttachTargets =
    realizationPorts.attachTargetsForDeploymentHost {
      inventory = inventory;
      deploymentHostName = hostName;
      file = "lib/render-host-network.nix";
    };

  localAttachBridgeNames =
    lib.unique (map (target: target.name) localAttachTargets);

  bridgeNames =
    lib.unique (uplinkBridgeNames ++ localAttachBridgeNames);

  netdevs =
    builtins.listToAttrs (
      map
        (bridgeName: {
          name = "10-${bridgeName}";
          value = {
            netdevConfig = {
              Name = bridgeName;
              Kind = "bridge";
            };
          };
        })
        bridgeNames
    );

  parentNetworks =
    builtins.listToAttrs (
      lib.filter
        (entry: entry != null)
        (map
          (uplinkName:
            let
              uplink = uplinks.${uplinkName};
              parent = uplink.parent or null;
              bridge = uplink.bridge or null;
            in
            if builtins.isString parent && builtins.isString bridge then
              {
                name = "20-${parent}";
                value = {
                  matchConfig.Name = parent;
                  networkConfig = {
                    Bridge = bridge;
                    ConfigureWithoutCarrier = true;
                  };
                };
              }
            else
              null)
          (sortedAttrNames uplinks))
    );

  bridgeNetworks =
    builtins.listToAttrs (
      map
        (bridgeName: {
          name = "30-${bridgeName}";
          value = {
            matchConfig.Name = bridgeName;
            networkConfig = {
              ConfigureWithoutCarrier = true;
            };
          };
        })
        bridgeNames
    );
in
{
  inherit netdevs;
  networks = parentNetworks // bridgeNetworks;
}
