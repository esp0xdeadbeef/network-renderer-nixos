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
      file ? "s88/ControlModule/api/host/default.nix",
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
      hostName = resolved.hostPlan.hostName or resolved.selectorValue;
      deploymentHostName = resolved.hostPlan.deploymentHostName or null;
      netdevs = hostSystemd.hostNetdevs or { };
      networks = hostSystemd.hostNetworks or { };

      debug = {
        identity = resolved.identity;
        fabric = resolved.fabric;
        hostName = resolved.hostPlan.hostName or resolved.selectorValue;
        deploymentHostName = resolved.hostPlan.deploymentHostName or null;
        runtimeRole = resolved.hostPlan.runtimeRole or null;
        selectedUnits = resolved.hostPlan.selectedUnits or [ ];
        uplinks = resolved.hostPlan.uplinks or { };
        transitBridges = resolved.hostPlan.transitBridges or { };
      };
    };
}
