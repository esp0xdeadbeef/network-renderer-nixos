{ lib }:

let
  base = import ./base.nix { inherit lib; };
  hostQuery = import ../../../ControlModule/lookup/host-query.nix { inherit lib; };

  deployment = import ./selection/deployment-host.nix {
    inherit lib base hostQuery;
  };

  hostContext = import ./selection/host-context.nix {
    inherit lib base deployment;
  };

  roles = import ./selection/roles.nix { inherit lib base deployment; };
in
deployment // hostContext // roles
