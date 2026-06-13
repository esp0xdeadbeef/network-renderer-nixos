{ lib }:

let
  helpers = import ./inventory/helpers.nix { inherit lib; };

  resolveDeploymentHostName = import ./inventory/deployment-host.nix {
    inherit helpers;
  };

  hostContextForSelector = import ./inventory/selector.nix {
    inherit lib helpers;
  };

  hostContextForHost = import ./inventory/host.nix {
    inherit helpers resolveDeploymentHostName;
  };
in
{
  inherit
    resolveDeploymentHostName
    hostContextForSelector
    hostContextForHost
    ;
}
