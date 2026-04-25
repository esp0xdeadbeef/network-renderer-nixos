{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
  realizationPorts = import ../../physical/realization-ports.nix { inherit lib; };

  sitesData =
    if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? data
      && builtins.isAttrs cpm.control_plane_model.data
    then
      cpm.control_plane_model.data
    else if cpm ? data && builtins.isAttrs cpm.data then
      cpm.data
    else
      { };

  inventoryControlPlaneSites =
    if
      builtins.isAttrs inventory
      && inventory ? controlPlane
      && builtins.isAttrs inventory.controlPlane
      && inventory.controlPlane ? sites
      && builtins.isAttrs inventory.controlPlane.sites
    then
      inventory.controlPlane.sites
    else
      { };

  hostRuntime = import ../../lookup/host-runtime.nix {
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
    selectedUnits = hostRuntime.unitsOnDeploymentHost;
    normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
    file = "s88/Unit/render/host-plan.nix";
  };

  attachTargetsRuntimeSelected = realizationPorts.attachTargetsForUnitsFromRuntime {
    inherit inventory;
    selectedUnits = hostRuntime.selectedUnits;
    normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
    file = "s88/Unit/render/host-plan.nix";
  };

  bridgeModel = import ../../../EquipmentModule/mapping/host-bridges.nix {
    inherit
      lib
      attachTargetsRuntime
      ;
  };

  wanAttachment = import ../../../EquipmentModule/mapping/wan-attachment.nix {
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

  transitBridgeModel = import ../../../EquipmentModule/physical/transit-bridges.nix {
    inherit lib;
    inherit (hostRuntime)
      deploymentHostName
      deploymentHost
      realizationNodes
      ;
  };

  effectiveBridgeModel = import ../../../EquipmentModule/mapping/effective-host-bridges.nix {
    inherit
      lib
      bridgeModel
      wanAttachment
      transitBridgeModel
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

  inherit sitesData;
  inherit inventoryControlPlaneSites;

  inherit (effectiveBridgeModel)
    bridgeNamesRaw
    bridgeNameMap
    bridges
    ;

  inherit
    attachTargetsRuntime
    attachTargetsRuntimeSelected
    ;

  attachTargets = wanAttachment.attachTargets;
  localAttachTargets = wanAttachment.localAttachTargets;

  uplinks = wanAttachment.uplinks;
  hostHasUplinks = wanAttachment.hostHasUplinks;
  wanUplinkName = wanAttachment.wanUplinkName;
  fabricUplinkName = wanAttachment.fabricUplinkName;

  transitBridges = transitBridgeModel.transitBridges;
}
