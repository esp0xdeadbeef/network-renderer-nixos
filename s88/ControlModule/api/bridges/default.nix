{
  lib,
  selectors,
  buildHostFromPaths,
  currentSystem ? builtins.currentSystem,
}:

let
  boxInputs = import ../box-build-inputs.nix {
    inherit
      lib
      selectors
      buildHostFromPaths
      currentSystem
      ;
  };
in
{
  build =
    {
      file ? "s88/ControlModule/api/bridges/default.nix",
      ...
    }@args:
    let
      resolved = boxInputs.resolve (args // { inherit file; });

      hostSystemd = import ../../render/systemd-host-network.nix {
        inherit lib;
        hostPlan = resolved.hostPlan;
      };
    in
    {
      bridgeNameMap = resolved.hostPlan.bridgeNameMap or { };
      bridges = resolved.hostPlan.bridges or { };
      netdevs = hostSystemd.bridgeNetdevs or { };
      networks = hostSystemd.bridgeNetworks or { };

      debug = {
        identity = resolved.identity;
        fabric = resolved.fabric;
        hostName = resolved.hostPlan.hostName or resolved.selectorValue;
        deploymentHostName = resolved.hostPlan.deploymentHostName or null;
        selectedUnits = resolved.hostPlan.selectedUnits or [ ];
        bridgeNameMap = resolved.hostPlan.bridgeNameMap or { };
        bridges = resolved.hostPlan.bridges or { };
        attachTargets = resolved.hostPlan.attachTargets or [ ];
      };
    };
}
