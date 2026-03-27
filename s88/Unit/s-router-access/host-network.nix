{
  config,
  lib,
  outPath,
  boxContext,
  globalInventory,
  controlPlaneOut,
  ...
}:

let
  inventory = globalInventory;
  hostname = config.networking.hostName;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHostName =
    if boxContext ? deploymentHostName && builtins.isString boxContext.deploymentHostName then
      boxContext.deploymentHostName
    else
      hostname;

  hostConfig =
    if boxContext ? box && builtins.isAttrs boxContext.box then
      boxContext.box
    else
      throw ''
        host-network:

        boxContext.box missing.
      '';

  runtimeContext = import "${outPath}/lib/runtime-context.nix" { inherit lib; };

  baseRendered = import ../s-router-policy-only/lib/renderer/render-host-network.nix {
    inherit lib inventory;
    hostName = deploymentHostName;
    cpm = controlPlaneOut;
  };

  uplinks =
    if hostConfig ? uplinks && builtins.isAttrs hostConfig.uplinks then
      hostConfig.uplinks
    else
      throw ''
        host-network:

        inventory.deployment.hosts.${deploymentHostName}.uplinks missing.

        host config:
        ${builtins.toJSON hostConfig}
      '';

  uplinkNames = sortedAttrNames uplinks;

  localAccessUnits =
    runtimeContext.unitNamesForRoleOnDeploymentHost {
      cpm = controlPlaneOut;
      inventory = globalInventory;
      inherit deploymentHostName;
      role = "access";
      file = "s88/Unit/s-router-access/host-network.nix";
    };

  parentNames =
    lib.unique (
      map (uplinkName: uplinks.${uplinkName}.parent) uplinkNames
    );

  trunkParent =
    if builtins.length parentNames == 1 then
      builtins.head parentNames
    else
      throw ''
        host-network:

        Expected exactly 1 parent uplink for access host.

        Parents:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ parentNames)}
      '';

  vlanFromCIDR =
    cidr:
    let
      addr = builtins.elemAt (lib.splitString "/" cidr) 0;
      octets = lib.splitString "." addr;
    in
    if builtins.length octets == 4 then
      builtins.fromJSON (builtins.elemAt octets 2)
    else
      throw ''
        host-network:

        Cannot derive VLAN from IPv4 CIDR '${cidr}'.
      '';

  tenantBridgeSpecs =
    lib.unique (
      map
        (
          unitName:
          let
            domain = runtimeContext.tenantDomainForUnit {
              cpm = controlPlaneOut;
              inherit unitName;
              file = "s88/Unit/s-router-access/host-network.nix";
            };

            vlan = vlanFromCIDR domain.ipv4;
          in
          {
            bridge = "br-lan-${toString vlan}";
            vlanIf = "${trunkParent}.${toString vlan}";
            inherit vlan;
          }
        )
        localAccessUnits
    );

  tenantNetdevs =
    builtins.listToAttrs (
      lib.concatMap
        (
          spec:
          [
            {
              name = "13-${spec.bridge}";
              value = {
                netdevConfig = {
                  Name = spec.bridge;
                  Kind = "bridge";
                };
              };
            }
            {
              name = "14-${spec.vlanIf}";
              value = {
                netdevConfig = {
                  Name = spec.vlanIf;
                  Kind = "vlan";
                };
                vlanConfig.Id = spec.vlan;
              };
            }
          ]
        )
        tenantBridgeSpecs
    );

  parentNetworkKey = "20-${trunkParent}";

  existingParentNetwork =
    if builtins.hasAttr parentNetworkKey baseRendered.networks then
      baseRendered.networks.${parentNetworkKey}
    else
      {
        matchConfig.Name = trunkParent;
        networkConfig = {
          ConfigureWithoutCarrier = true;
        };
      };

  existingParentVlans =
    if existingParentNetwork ? networkConfig
      && builtins.isAttrs existingParentNetwork.networkConfig
      && existingParentNetwork.networkConfig ? VLAN
      && builtins.isList existingParentNetwork.networkConfig.VLAN
    then
      existingParentNetwork.networkConfig.VLAN
    else
      [ ];

  mergedParentVlans =
    lib.unique (existingParentVlans ++ (map (spec: spec.vlanIf) tenantBridgeSpecs));

  tenantVlanNetworks =
    builtins.listToAttrs (
      map
        (
          spec:
          {
            name = "22-${spec.vlanIf}";
            value = {
              matchConfig.Name = spec.vlanIf;
              networkConfig = {
                Bridge = spec.bridge;
                ConfigureWithoutCarrier = true;
              };
            };
          }
        )
        tenantBridgeSpecs
    );

  tenantBridgeNetworks =
    builtins.listToAttrs (
      map
        (
          spec:
          {
            name = "31-${spec.bridge}";
            value = {
              matchConfig.Name = spec.bridge;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              };
            };
          }
        )
        tenantBridgeSpecs
    );

  augmentedParentNetworks = {
    "${parentNetworkKey}" =
      existingParentNetwork
      // {
        networkConfig =
          (existingParentNetwork.networkConfig or { })
          // {
            ConfigureWithoutCarrier =
              (existingParentNetwork.networkConfig.ConfigureWithoutCarrier or true);
          }
          // lib.optionalAttrs (mergedParentVlans != [ ]) {
            VLAN = mergedParentVlans;
          };
      };
  };
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = baseRendered.netdevs // tenantNetdevs;
  systemd.network.networks =
    baseRendered.networks
    // augmentedParentNetworks
    // tenantVlanNetworks
    // tenantBridgeNetworks;
}
