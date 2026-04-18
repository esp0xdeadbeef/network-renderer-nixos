{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
  isa = import ../../ControlModule/alarm/isa18.nix { inherit lib; };

  hostPlan = import ./host-plan.nix {
    inherit
      lib
      hostName
      cpm
      inventory
      hostContext
      ;
  };

  hostSystemd = import ../../ControlModule/render/systemd-host-network.nix {
    inherit lib hostPlan;
  };

  containerRenderings = import ../../ControlModule/render/containers.nix {
    inherit
      lib
      hostPlan
      cpm
      inventory
      ;
  };

  pipelineAlarmModel = isa.normalizeModel cpm;
in
{
  inherit (hostPlan)
    hostName
    deploymentHostName
    deploymentHost
    renderHostConfig
    bridgeNameMap
    bridges
    attachTargets
    localAttachTargets
    selectedUnits
    selectedRoleNames
    selectedRoles
    resolvedHostContext
    runtimeRole
    uplinks
    transitBridges
    ;

  alarms = pipelineAlarmModel.alarms;
  warnings = pipelineAlarmModel.warningMessages;

  netdevs = hostSystemd.netdevs;
  networks = hostSystemd.networks;
  containers = containerRenderings;

  debug = {
    inherit (hostPlan)
      hostName
      deploymentHostName
      runtimeRole
      selectedUnits
      uplinks
      transitBridges
      ;
    localBridgeNameMap = hostPlan.bridgeNameMap;
    localAttachTargets = hostPlan.localAttachTargets;
  };
}
