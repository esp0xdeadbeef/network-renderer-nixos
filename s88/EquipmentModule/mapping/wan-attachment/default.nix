{ lib
, hostName
, deploymentHostName
, deploymentHost
, renderHostConfig
, cpm
, source ? { }
, attachTargetsBase
,
}:

let
  lookup = import ./lookup.nix {
    inherit
      lib
      deploymentHostName
      deploymentHost
      cpm
      source
      attachTargetsBase
      ;
  };

  assignment = import ./assignment.nix {
    inherit
      lib
      hostName
      deploymentHostName
      deploymentHost
      renderHostConfig
      lookup
      ;
  };
in
import ./rendered.nix {
  inherit
    lib
    lookup
    assignment
    attachTargetsBase
    ;
}
