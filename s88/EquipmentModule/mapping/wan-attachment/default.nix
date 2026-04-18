{
  lib,
  hostName,
  deploymentHostName,
  deploymentHost,
  renderHostConfig,
  cpm,
  inventory ? { },
  attachTargetsBase,
}:

let
  lookup = import ./lookup.nix {
    inherit
      lib
      deploymentHostName
      deploymentHost
      cpm
      inventory
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
