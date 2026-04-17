{
  lib,
  importValue,
  buildControlPlaneOutput,
  normalizeControlPlane,
  selectDeploymentHost,
  mapHostModel,
  mapBridgeModel,
  mapVmContainerSimulatedModel,
  mapVmSimulatedHostBridgeModel,
  renderHostNetwork,
  renderBridgeNetwork,
  renderSimulatedBridges,
  renderContainers,
  artifacts,
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  json = value: builtins.toJSON value;

  mergeAttrsDedupe =
    label: left: right:
    let
      names = lib.unique (sortedAttrNames left ++ sortedAttrNames right);
    in
    builtins.listToAttrs (
      map (
        name:
        if !(builtins.hasAttr name left) then
          {
            inherit name;
            value = right.${name};
          }
        else if !(builtins.hasAttr name right) then
          {
            inherit name;
            value = left.${name};
          }
        else if json left.${name} == json right.${name} then
          {
            inherit name;
            value = left.${name};
          }
        else
          throw "network-renderer-nixos: conflicting ${label} for '${name}'"
      ) names
    );

  inventoryDeploymentHosts =
    inventory:
    if
      builtins.isAttrs inventory
      && inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  resolveRequestedBoxName =
    {
      inventoryPath,
      requestedBoxName ? null,
    }:
    let
      inventoryRaw = if inventoryPath == null then { } else importValue inventoryPath;
      inventory = if builtins.isAttrs inventoryRaw then inventoryRaw else { };
      deploymentHosts = inventoryDeploymentHosts inventory;
      deploymentHostNames = sortedAttrNames deploymentHosts;
    in
    if requestedBoxName == null || requestedBoxName == "" || requestedBoxName == "*" then
      if builtins.length deploymentHostNames == 1 then
        builtins.head deploymentHostNames
      else
        throw "network-renderer-nixos: wildcard boxName requires exactly one deployment host in inventory"
    else
      requestedBoxName;

  resolveEffectiveInventoryPath =
    {
      inventoryPath,
      boxName,
    }:
    if inventoryPath == null then
      null
    else
      let
        inventoryRaw = importValue inventoryPath;
        inventory = if builtins.isAttrs inventoryRaw then inventoryRaw else { };
        deploymentHosts = inventoryDeploymentHosts inventory;
        inventoryDir = builtins.dirOf (toString inventoryPath);
        hostScopedPath = /. + "${inventoryDir}/${boxName}/inventory.nix";
      in
      if builtins.hasAttr boxName deploymentHosts then
        inventoryPath
      else if builtins.pathExists hostScopedPath then
        hostScopedPath
      else
        inventoryPath;
in
{
  build =
    {
      intentPath,
      inventoryPath,
      boxName ? null,
      simulatedContainerDefaults ? {
        autoStart = true;
        privateNetwork = true;
      },
    }:
    let
      resolvedBoxName = resolveRequestedBoxName {
        inherit inventoryPath;
        requestedBoxName = boxName;
      };

      effectiveInventoryPath = resolveEffectiveInventoryPath {
        inherit inventoryPath;
        boxName = resolvedBoxName;
      };

      hostControlPlaneOut = buildControlPlaneOutput {
        inherit intentPath;
        inventoryPath = effectiveInventoryPath;
      };

      hostModel = normalizeControlPlane hostControlPlaneOut;

      deploymentHost = selectDeploymentHost {
        model = hostModel;
        boxName = resolvedBoxName;
      };

      simulatedControlPlaneOut = buildControlPlaneOutput {
        inherit
          intentPath
          inventoryPath
          ;
      };

      simulatedModel = normalizeControlPlane simulatedControlPlaneOut;

      hostRendered = renderHostNetwork (mapHostModel {
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
      });

      bridgeRendered = renderBridgeNetwork (mapBridgeModel {
        boxName = deploymentHost.name;
        deploymentHostDef = deploymentHost.definition;
      });

      simulatedContainerModel = mapVmContainerSimulatedModel {
        normalizedModel = simulatedModel;
        deploymentHostName = deploymentHost.name;
        defaults = simulatedContainerDefaults;
      };

      simulatedBridgeRendered = renderSimulatedBridges (mapVmSimulatedHostBridgeModel {
        containerModel = simulatedContainerModel;
        deploymentHostName = deploymentHost.name;
      });
    in
    {
      boxName = deploymentHost.name;

      renderedNetdevs = mergeAttrsDedupe "systemd.network.netdevs" (mergeAttrsDedupe
        "systemd.network.netdevs"
        (hostRendered.netdevs or { })
        (bridgeRendered.netdevs or { })
      ) (simulatedBridgeRendered.netdevs or { });

      renderedNetworks = mergeAttrsDedupe "systemd.network.networks" (mergeAttrsDedupe
        "systemd.network.networks"
        (hostRendered.networks or { })
        (bridgeRendered.networks or { })
      ) (simulatedBridgeRendered.networks or { });

      renderedContainers = renderContainers simulatedContainerModel;

      artifactModule = artifacts.controlPlaneSplitFromControlPlane {
        controlPlaneOut = simulatedControlPlaneOut;
        fileName = "control-plane-model.json";
        directory = "network-artifacts";
      };
    };
}
