{
  lib,
  repoPath,
  hostName,
  cpm,
  source ? { },
  hostContext ? null,
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

  realizationPorts = import ../../physical/realization-ports.nix { inherit lib; };

  sitesData =
    let
      model = if builtins.isAttrs cpm then (cpm.model or cpm.control_plane_model or cpm) else { };
      byEnterprise = (model.canonicalSites or { }).byEnterprise or null;
    in
    if builtins.isAttrs byEnterprise then
      byEnterprise
    else if builtins.isAttrs (model.data or null) then
      model.data
    else
      { };

  cpmSourceBase =
    if builtins.isAttrs (cpm.model or null) then
      cpm.model
    else if builtins.isAttrs cpm then
      cpm
    else
      { };

  cpmTopLevelSource =
    if builtins.isAttrs cpm then
      (lib.optionalAttrs (cpm ? deploymentHosts && builtins.isAttrs cpm.deploymentHosts) {
        deploymentHosts = cpm.deploymentHosts;
      })
      // (lib.optionalAttrs (cpm ? deployment && builtins.isAttrs cpm.deployment) {
        deployment = cpm.deployment;
      })
      // (lib.optionalAttrs (cpm ? realization && builtins.isAttrs cpm.realization) {
        realization = cpm.realization;
      })
      // (lib.optionalAttrs (cpm ? render && builtins.isAttrs cpm.render) {
        render = cpm.render;
      })
    else
      { };

  cpmSource = cpmSourceBase // cpmTopLevelSource;

  hostRuntime = trace.emit "host-plan:${hostName}:host-runtime" (
    import ../../lookup/host-runtime.nix {
      inherit repoPath;
      inherit
        lib
        hostName
        cpm
        hostContext
        ;

      source = cpmSource;
    }
  );

  attachTargetsRuntime = trace.emit "host-plan:${hostName}:attach-targets-all-host-units" (
    realizationPorts.attachTargetsForUnitsFromRuntime {
      source = cpmSource;
      selectedUnits = hostRuntime.unitsOnDeploymentHost;
      normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
      file = "s88/Unit/render/host-plan.nix";
    }
  );

  attachTargetsRuntimeSelected = trace.emit "host-plan:${hostName}:attach-targets-selected-units" (
    realizationPorts.attachTargetsForUnitsFromRuntime {
      source = cpmSource;
      selectedUnits = hostRuntime.selectedUnits;
      normalizedRuntimeTargets = hostRuntime.normalizedRuntimeTargets;
      file = "s88/Unit/render/host-plan.nix";
    }
  );

  bridgeModel = trace.emit "host-plan:${hostName}:bridge-model" (
    import ../../../EquipmentModule/mapping/host-bridges.nix {
      inherit
        lib
        attachTargetsRuntime
        ;
      inherit (hostRuntime)
        deploymentHost
        ;
    }
  );

  wanAttachment = trace.emit "host-plan:${hostName}:wan-attachment" (
    import ../../../EquipmentModule/mapping/wan-attachment.nix {
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

      source = { };
    }
  );

  transitBridgeModel = trace.emit "host-plan:${hostName}:transit-bridges" (
    import ../../../EquipmentModule/physical/transit-bridges.nix {
      inherit lib;
      inherit (hostRuntime)
        deploymentHostName
        deploymentHost
        realizationNodes
        ;
    }
  );

  effectiveBridgeModel = trace.emit "host-plan:${hostName}:effective-bridge-model" (
    import ../../../EquipmentModule/mapping/effective-host-bridges.nix {
      inherit
        lib
        bridgeModel
        wanAttachment
        transitBridgeModel
        ;
    }
  );
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
