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
    file = "s88/CM/network/render/host-plan.nix";
  };

  bridgeModel = import ../mapping/host-bridges.nix {
    inherit
      lib
      attachTargetsRuntime
      ;
  };

  wanAttachment = import ../mapping/wan-attachment.nix {
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

  transitBridgeModel = import ../physical/transit-bridges.nix {
    inherit lib;
    inherit (hostRuntime)
      deploymentHostName
      deploymentHost
      realizationNodes
      ;
  };
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

  bridgeNamesRaw = bridgeModel.bridgeNamesRaw;
  bridgeNameMap = bridgeModel.bridgeNameMap;
  bridges = bridgeModel.bridges;

  inherit attachTargetsRuntime;
  attachTargets = wanAttachment.attachTargets;
  localAttachTargets = wanAttachment.localAttachTargets;

  uplinks = wanAttachment.uplinks;
  hostHasUplinks = wanAttachment.hostHasUplinks;
  wanUplinkName = wanAttachment.wanUplinkName;
  fabricUplinkName = wanAttachment.fabricUplinkName;

  transitBridges = transitBridgeModel.transitBridges;
}
