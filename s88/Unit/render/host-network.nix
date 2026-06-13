{ lib
, repoPath
, hostName
, cpm
, source ? { }
, hostContext ? null
, ...
}:

let
  trace = import "${repoPath}/lib/trace.nix" { };

  isa = import ../../ControlModule/alarm/isa18.nix { inherit lib; };

  renderSites =
    let
      data =
        if cpm ? control_plane_model && builtins.isAttrs cpm.control_plane_model then
          cpm.control_plane_model.data or { }
        else
          { };
    in
    if !builtins.isAttrs data then
      { }
    else
      builtins.mapAttrs
        (
          _enterprise: sites:
            if !builtins.isAttrs sites then
              { }
            else
              builtins.mapAttrs
                (
                  _siteName: siteObj:
                    if !builtins.isAttrs siteObj then
                      { }
                    else
                      {
                        ipv6 = siteObj.ipv6 or { };
                        routing = siteObj.routing or { };
                        transit = siteObj.transit or { };
                      }
                )
                sites
        )
        data;

  hostPlan = trace.emit "host-network:${hostName}:host-plan" (import ./host-plan.nix {
    inherit repoPath;
    inherit
      lib
      hostName
      cpm
      source
      hostContext
      ;
  });

  hostSystemd = trace.emit "host-network:${hostName}:systemd-host-network" (import ../../ControlModule/render/systemd-host-network.nix {
    inherit lib hostPlan;
  });

  containerRenderings = trace.emit "host-network:${hostName}:containers" (import ../../ControlModule/render/containers.nix {
    inherit repoPath;
    inherit
      lib
      hostPlan
      cpm
      source
      ;
  });

  pppoeServerContainers = trace.emit "host-network:${hostName}:pppoe-server-containers" (import ../../ControlModule/render/pppoe-server-containers.nix {
    inherit lib cpm hostName hostPlan;
  });

  pipelineAlarmModel = trace.emit "host-network:${hostName}:alarms" (isa.normalizeModel cpm);
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
  containers = containerRenderings // pppoeServerContainers;
  sites = renderSites;

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
