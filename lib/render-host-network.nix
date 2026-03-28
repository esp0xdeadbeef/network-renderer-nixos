{
  lib,
  hostName,
  cpm,
  inventory ? { },
}:

let
  hostNaming = import ./host-naming.nix { inherit lib; };
  runtimeContext = import ./runtime-context.nix { inherit lib; };
  cpmAdapter = import ./cpm-runtime-adapter.nix { inherit lib; };

  _inventory = inventory;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargets = cpmAdapter.normalizedRuntimeTargets {
    inherit cpm;
    file = "lib/render-host-network.nix";
  };

  unitsOnDeploymentHost = runtimeContext.unitNamesForDeploymentHost {
    inherit cpm;
    deploymentHostName = hostName;
    file = "lib/render-host-network.nix";
  };

  interfacesForUnit =
    unitName:
    if builtins.hasAttr unitName normalizedRuntimeTargets then
      normalizedRuntimeTargets.${unitName}.interfaces or { }
    else
      { };

  localAttachBridgeNames = lib.unique (
    lib.concatMap (
      unitName:
      let
        interfaces = interfacesForUnit unitName;
      in
      map (
        ifName:
        let
          iface = interfaces.${ifName};
        in
        if iface ? hostBridge && builtins.isString iface.hostBridge then
          iface.hostBridge
        else
          throw ''
            lib/render-host-network.nix: interface '${ifName}' for unit '${unitName}' is missing normalized hostBridge
          ''
      ) (sortedAttrNames interfaces)
    ) unitsOnDeploymentHost
  );

  bridgeNamesRaw = lib.sort builtins.lessThan (lib.unique localAttachBridgeNames);

  bridgeNameMap = hostNaming.ensureUnique bridgeNamesRaw;

  bridgeNames = map (bridgeName: bridgeNameMap.${bridgeName}) bridgeNamesRaw;

  bridges = builtins.listToAttrs (
    map (bridgeName: {
      name = bridgeName;
      value = {
        originalName = bridgeName;
        renderedName = bridgeNameMap.${bridgeName};
      };
    }) bridgeNamesRaw
  );

  netdevs = builtins.listToAttrs (
    map (renderedBridgeName: {
      name = "10-${renderedBridgeName}";
      value = {
        netdevConfig = {
          Name = renderedBridgeName;
          Kind = "bridge";
        };
      };
    }) bridgeNames
  );

  networks = builtins.listToAttrs (
    map (renderedBridgeName: {
      name = "30-${renderedBridgeName}";
      value = {
        matchConfig.Name = renderedBridgeName;
        networkConfig = {
          ConfigureWithoutCarrier = true;
        };
      };
    }) bridgeNames
  );

  attachTargets = lib.concatMap (
    unitName:
    let
      interfaces = interfacesForUnit unitName;
    in
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        hostBridgeName = iface.hostBridge;
      in
      {
        inherit unitName ifName hostBridgeName;
        renderedHostBridgeName = bridgeNameMap.${hostBridgeName};
        renderedIfName = iface.renderedIfName or null;
        addresses = iface.addresses or [ ];
        routes = iface.routes or [ ];
        connectivity = iface.connectivity or null;
        interface = iface;
      }
    ) (sortedAttrNames interfaces)
  ) unitsOnDeploymentHost;
in
{
  inherit
    bridgeNameMap
    bridges
    netdevs
    networks
    attachTargets
    ;
}
