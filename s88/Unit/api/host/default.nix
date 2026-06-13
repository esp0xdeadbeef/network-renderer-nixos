{ lib
, repoPath
, selectors
, buildHostFromControlPlane
, currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux"
,
}:

let
  boxInputs = import ../box-build-inputs.nix {
    inherit
      lib
      repoPath
      selectors
      buildHostFromControlPlane
      currentSystem
      ;
  };
in
{
  build =
    { file ? "s88/Unit/api/host/default.nix"
    , ...
    }@args:
    let
      resolved = boxInputs.resolve (args // { inherit file; });

      hostSystemd = import ../../../ControlModule/render/systemd-host-network.nix {
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
        hostName = resolved.hostPlan.hostName or resolved.selectorValue;
        deploymentHostName = resolved.hostPlan.deploymentHostName or null;
        runtimeRole = resolved.hostPlan.runtimeRole or null;
        selectedUnits = resolved.hostPlan.selectedUnits or [ ];
        uplinks = resolved.hostPlan.uplinks or { };
        transitBridges = resolved.hostPlan.transitBridges or { };
      };
    };
}
