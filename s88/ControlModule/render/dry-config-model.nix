{ lib
, metadataSourcePaths
, debugEnabled ? false
, runtimeContext
, normalizedRuntimeTargets
, hostRenderings
, deploymentHostNames
, controlPlane
, resolvedInventory
,
}:

let
  isa = import ../alarm/isa18.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  unitNames = sortedAttrNames normalizedRuntimeTargets;

  pipelineAlarmModel = isa.normalizeModel controlPlane;
  containerDebug = import ./dry-config-model/containers-debug.nix { inherit lib; };
  inherit (containerDebug) sanitizedContainersForHost;

  hostRenderingsDebug = builtins.mapAttrs
    (_hostName: hostRendering: {
      hostName = hostRendering.hostName or null;
      deploymentHostName = hostRendering.deploymentHostName or null;
      runtimeRole = hostRendering.runtimeRole or null;
      selectedUnits = hostRendering.selectedUnits or [ ];
      selectedRoleNames = hostRendering.selectedRoleNames or [ ];
      bridgeNameMap = hostRendering.bridgeNameMap or { };
      bridges = hostRendering.bridges or { };
      netdevs = hostRendering.netdevs or { };
      networks = hostRendering.networks or { };
      attachTargets = hostRendering.attachTargets or [ ];
      localAttachTargets = hostRendering.localAttachTargets or [ ];
      uplinks = hostRendering.uplinks or { };
      transitBridges = hostRendering.transitBridges or { };
      containers = sanitizedContainersForHost hostRendering;
      debug = hostRendering.debug or { };
    })
    hostRenderings;

  renderedInterfacesForUnit = import ./dry-config-model/interfaces.nix {
    inherit lib runtimeContext normalizedRuntimeTargets hostRenderings deploymentHostNames controlPlane resolvedInventory;
  };

  renderHosts = builtins.listToAttrs (
    map
      (
        hostName:
        let
          hostRendering = hostRenderings.${hostName};
        in
        {
          name = hostName;
          value = {
            network = {
              bridges = hostRendering.bridges;
              netdevs = hostRendering.netdevs;
              networks = hostRendering.networks;
            };
          };
        }
      )
      deploymentHostNames
  );

  renderNodes = builtins.listToAttrs (
    map
      (unitName: {
        name = unitName;
        value = {
          logicalNode = runtimeContext.logicalNodeForUnit {
            cpm = controlPlane;
            inventory = resolvedInventory;
            inherit unitName;
            file = "s88/CM/network/render/dry-config-model.nix";
          };

          deploymentHostName = runtimeContext.deploymentHostForUnit {
            cpm = controlPlane;
            inventory = resolvedInventory;
            inherit unitName;
            file = "s88/CM/network/render/dry-config-model.nix";
          };

          role = runtimeContext.roleForUnit {
            cpm = controlPlane;
            inventory = resolvedInventory;
            inherit unitName;
            file = "s88/CM/network/render/dry-config-model.nix";
          };

          interfaces = renderedInterfacesForUnit unitName;
          loopback = normalizedRuntimeTargets.${unitName}.loopback or { };
        };
      })
      unitNames
  );

  renderContainers = builtins.listToAttrs (
    map
      (hostName: {
        name = hostName;
        value = sanitizedContainersForHost hostRenderings.${hostName};
      })
      deploymentHostNames
  );

  renderSites = import ./dry-config-model/sites.nix { inherit controlPlane; };

  output = {
    metadata = {
      sourcePaths = metadataSourcePaths;
      warnings = pipelineAlarmModel.warningMessages;
      alarms = pipelineAlarmModel.alarms;
    };

    render = {
      hosts = renderHosts;
      nodes = renderNodes;
      containers = renderContainers;
      sites = renderSites;
    };
  }
  // lib.optionalAttrs debugEnabled {
    debug = {
      controlPlane = controlPlane;
      inventory = resolvedInventory;
      normalizedRuntimeTargets = normalizedRuntimeTargets;
      hostRenderings = hostRenderingsDebug;
    };
  };
in
output
