{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
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
