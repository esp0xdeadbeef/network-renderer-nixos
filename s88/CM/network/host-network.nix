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
  tenantBridgeRenderer = import ../../../lib/tenant-bridge-renderer.nix { inherit lib; };

  maxLen = 15;

  hash = name:
    builtins.substring 0 6 (builtins.hashString "sha256" name);

  shorten = name:
    if builtins.stringLength name <= maxLen then
      name
    else
      let
        prefixLen = maxLen - 7;
        prefix = builtins.substring 0 prefixLen name;
      in
      "${prefix}-${hash name}";

  ensureUnique =
    names:
    let
      shortened =
        map
          (n: {
            original = n;
            rendered = shorten n;
          })
          names;

      grouped =
        builtins.foldl'
          (acc: entry:
            let key = entry.rendered;
            in acc // {
              ${key} = (acc.${key} or [ ]) ++ [ entry.original ];
            })
          { }
          shortened;

      collisions =
        lib.filterAttrs (_: v: builtins.length v > 1) grouped;
    in
    if collisions != { } then
      throw ''
host-network: collision detected after shortening

${builtins.toJSON collisions}
''
    else
      builtins.listToAttrs (
        map (entry: {
          name = entry.original;
          value = entry.rendered;
        }) shortened
      );

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
            let uplink = uplinks.${uplinkName};
            in uplink.bridge or null)
          (sortedAttrNames uplinks))
    );

  localAttachTargets = realizationPorts.attachTargetsForDeploymentHost {
    inventory = globalInventory;
    inherit deploymentHostName;
    file = "s88/CM/network/host-network.nix";
  };

  localAttachBridgeNames =
    lib.unique (map (target: target.name) localAttachTargets);

  bridgeNamesRaw = lib.unique (uplinkBridgeNames ++ localAttachBridgeNames);

  bridgeNameMap = ensureUnique bridgeNamesRaw;

  bridgeNames = map (n: bridgeNameMap.${n}) bridgeNamesRaw;

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
              renderedBridge =
                if builtins.isString bridge && builtins.hasAttr bridge bridgeNameMap then
                  bridgeNameMap.${bridge}
                else
                  null;
            in
            if builtins.isString parent && renderedBridge != null then
              {
                name = "20-${parent}";
                value = {
                  matchConfig.Name = parent;
                  networkConfig = {
                    Bridge = renderedBridge;
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

  tenantRendered =
    tenantBridgeRenderer.renderTenantBridges {
      tenantBridges = { };
      shorten = shorten;
      ensureUnique = ensureUnique;
    };

  roleExtra =
    if s88Role ? hostProfilePath && s88Role.hostProfilePath != null then
      import s88Role.hostProfilePath {
        inherit
          lib
          config
          globalInventory
          boxContext
          deploymentHostName
          deploymentHost;
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
    // tenantRendered.netdevs
    // (roleExtra.netdevs or { });

  systemd.network.networks =
    renderedParentNetworks
    // renderedBridgeNetworks
    // tenantRendered.networks
    // (roleExtra.networks or { });
}
