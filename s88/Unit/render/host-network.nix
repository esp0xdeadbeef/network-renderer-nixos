{
  lib,
  hostName,
  cpm,
  inventory ? { },
  hostContext ? null,
}:

let
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
      builtins.mapAttrs (
        _enterprise: sites:
        if !builtins.isAttrs sites then
          { }
        else
          builtins.mapAttrs (
            _siteName: siteObj:
            if !builtins.isAttrs siteObj then
              { }
            else
              {
                overlays = siteObj.overlays or { };
                ipv6 = siteObj.ipv6 or { };
                routing = siteObj.routing or { };
                transit = siteObj.transit or { };
              }
          ) sites
      ) data;

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
