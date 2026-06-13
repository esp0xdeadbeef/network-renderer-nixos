{ lib
, repoPath
, hostName
, cpm
, inventory ? { }
, hostContext ? null
,
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

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

  # CMC-NIXOS-INTENT-CLEANUP: inventory.controlPlane.sites removed.
  # Renderers consume CPM output only. Sites come from CPM.data.
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

  # Extract source data from CPM for realization-ports lookups.
  # CPM carries realization/deployment data that replaces raw inventory.
  cpmSource =
    if cpm ? control_plane_model && builtins.isAttrs cpm.control_plane_model then
      cpm.control_plane_model
    else if builtins.isAttrs cpm then
      cpm
    else
      { };

  hostRuntime = trace.emit "host-plan:${hostName}:host-runtime" (import ../../lookup/host-runtime.nix {
    inherit repoPath;
    inherit
      lib
      hostName
      cpm
      hostContext
      ;
    # CMC-NIXOS-INTENT-CLEANUP: pass empty inventory; CPM provides all needed data.
    inventory = { };
  });

  attachTargetsRuntime = trace.emit "host-plan:${hostName}:attach-targets-all-host-units" (realizationPorts.attachTargetsForUnitsFromRuntime {
    source = cpmSource;
    selectedUnits = hostRuntime.unitsOnDeploymentHost;
    normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
    file = "s88/Unit/render/host-plan.nix";
  });

  attachTargetsRuntimeSelected = trace.emit "host-plan:${hostName}:attach-targets-selected-units" (realizationPorts.attachTargetsForUnitsFromRuntime {
    source = cpmSource;
    selectedUnits = hostRuntime.selectedUnits;
    normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
    file = "s88/Unit/render/host-plan.nix";
  });

  bridgeModel = trace.emit "host-plan:${hostName}:bridge-model" (import ../../../EquipmentModule/mapping/host-bridges.nix {
    inherit
      lib
      attachTargetsRuntime
      ;
    inherit (hostRuntime)
      deploymentHost
      ;
  });

  wanAttachment = trace.emit "host-plan:${hostName}:wan-attachment" (import ../../../EquipmentModule/mapping/wan-attachment.nix {
    inherit
      lib
      hostName
      cpm
      ;
    inherit (hostRuntime)
      deploymentHostName
      deploymentHost
      renderHostConfig
      ;
    inherit (bridgeModel) attachTargetsBase;
    # CMC-NIXOS-INTENT-CLEANUP: inventory no longer passed; CPM provides wan data.
    inventory = { };
  });

  transitBridgeModel = trace.emit "host-plan:${hostName}:transit-bridges" (import ../../../EquipmentModule/physical/transit-bridges.nix {
    inherit lib;
    inherit (hostRuntime)
      deploymentHostName
      deploymentHost
      realizationNodes
      ;
  });

  effectiveBridgeModel = trace.emit "host-plan:${hostName}:effective-bridge-model" (import ../../../EquipmentModule/mapping/effective-host-bridges.nix {
    inherit
      lib
      bridgeModel
      wanAttachment
      transitBridgeModel
      ;
  });
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
