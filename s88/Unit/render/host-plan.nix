{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
  realizationPorts = import ../physical/realization-ports.nix { inherit lib; };

  hostRuntime = import ../lookup/host-runtime.nix {
    inherit
      lib
      hostName
      cpm
      inventory
      hostContext
      ;
  };

  attachTargetsRuntime = realizationPorts.attachTargetsForUnitsFromRuntime {
    inherit inventory;
    selectedUnits = hostRuntime.selectedUnits;
    normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
    file = "s88/Unit/render/host-plan.nix";
  };

  bridgeModel = import ../../EquipmentModule/mapping/host-bridges.nix {
    inherit
      lib
      attachTargetsRuntime
      ;
  };

  wanAttachment = import ../../EquipmentModule/mapping/wan-attachment.nix {
    inherit
      lib
      hostName
      cpm
      inventory
      ;
    inherit (hostRuntime)
      deploymentHostName
      deploymentHost
      renderHostConfig
      ;
    inherit (bridgeModel) attachTargetsBase;
  };

  transitBridgeModel = import ../../EquipmentModule/physical/transit-bridges.nix {
    inherit lib;
    inherit (hostRuntime)
      deploymentHostName
      deploymentHost
      realizationNodes
      ;
  };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  claimedRenderedBridgeNames = lib.unique (
    lib.filter builtins.isString (
      (map (
        uplinkName:
        let
          uplink = wanAttachment.uplinks.${uplinkName};
        in
        uplink.bridge or null
      ) (sortedAttrNames wanAttachment.uplinks))
      ++ (map (
        transitName:
        let
          transit = transitBridgeModel.transitBridges.${transitName};
        in
        if transit ? name && builtins.isString transit.name then transit.name else null
      ) (sortedAttrNames transitBridgeModel.transitBridges))
    )
  );

  referencedRenderedBridgeNames = lib.unique (
    lib.filter builtins.isString (
      map (target: target.renderedHostBridgeName or null) wanAttachment.localAttachTargets
    )
  );

  effectiveRenderedBridgeNames = lib.filter (
    renderedName: !(builtins.elem renderedName claimedRenderedBridgeNames)
  ) referencedRenderedBridgeNames;

  effectiveBridges = builtins.listToAttrs (
    lib.concatMap (
      bridgeName:
      let
        bridge = bridgeModel.bridges.${bridgeName};
      in
      lib.optionals (builtins.elem bridge.renderedName effectiveRenderedBridgeNames) [
        {
          name = bridgeName;
          value = bridge;
        }
      ]
    ) (sortedAttrNames bridgeModel.bridges)
  );

  effectiveBridgeNameMap = builtins.mapAttrs (_: bridge: bridge.renderedName) effectiveBridges;
in
{
  inherit (hostRuntime)
    hostName
    deploymentHostName
    deploymentHost
    renderHostConfig
    resolvedHostContext
    normalizedRuntimeTargets
    unitsOnDeploymentHost
    deploymentHostUnitRoles
    deploymentHostRoleNames
    deploymentHostRoles
    deploymentHostContainerNamingUnits
    selectedUnits
    selectedRoleNames
    selectedRoles
    unitRoles
    runtimeRole
    ;

  bridgeNamesRaw = sortedAttrNames effectiveBridges;
  bridgeNameMap = effectiveBridgeNameMap;
  bridges = effectiveBridges;

  inherit attachTargetsRuntime;
  attachTargets = wanAttachment.attachTargets;
  localAttachTargets = wanAttachment.localAttachTargets;

  uplinks = wanAttachment.uplinks;
  hostHasUplinks = wanAttachment.hostHasUplinks;
  wanUplinkName = wanAttachment.wanUplinkName;
  fabricUplinkName = wanAttachment.fabricUplinkName;

  transitBridges = transitBridgeModel.transitBridges;
}
