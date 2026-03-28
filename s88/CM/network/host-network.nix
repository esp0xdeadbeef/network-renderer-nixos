{
  config,
  lib,
  boxContext,
  globalInventory,
  s88Role,
  ...
}:

let
  realizationPorts = import ../../../lib/realization-ports.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHostName =
    if boxContext ? deploymentHostName && builtins.isString boxContext.deploymentHostName then
      boxContext.deploymentHostName
    else
      config.networking.hostName;

  deploymentHost =
    if boxContext ? box && builtins.isAttrs boxContext.box && boxContext.box != { } then
      boxContext.box
    else if globalInventory ? deployment
      && builtins.isAttrs globalInventory.deployment
      && globalInventory.deployment ? hosts
      && builtins.isAttrs globalInventory.deployment.hosts
      && builtins.hasAttr deploymentHostName globalInventory.deployment.hosts
    then
      globalInventory.deployment.hosts.${deploymentHostName}
    else
      { };

  uplinks =
    if deploymentHost ? uplinks && builtins.isAttrs deploymentHost.uplinks then
      deploymentHost.uplinks
    else
      { };

  uplinkBridgeNames =
    lib.unique (
      lib.filter
        (value: builtins.isString value)
        (map
          (uplinkName:
            let
              uplink = uplinks.${uplinkName};
            in
            uplink.bridge or null)
          (sortedAttrNames uplinks))
    );

  localAttachTargets = realizationPorts.attachTargetsForDeploymentHost {
    inventory = globalInventory;
    inherit deploymentHostName;
    file = "s88/CM/network/host-network.nix";
  };

  localAttachBridgeNames =
    lib.unique (map (target: target.name) localAttachTargets);

  bridgeNames = lib.unique (uplinkBridgeNames ++ localAttachBridgeNames);

  renderedBaseNetdevs =
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

  renderedParentNetworks =
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

  renderedBridgeNetworks =
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

  roleExtra =
    if s88Role ? hostProfilePath && s88Role.hostProfilePath != null then
      import s88Role.hostProfilePath {
        inherit
          lib
          config
          globalInventory
          boxContext
          deploymentHostName
          deploymentHost
          ;
      }
    else
      {
        netdevs = { };
        networks = { };
      };
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs =
    renderedBaseNetdevs
    // (roleExtra.netdevs or { });

  systemd.network.networks =
    renderedParentNetworks
    // renderedBridgeNetworks
    // (roleExtra.networks or { });
}
