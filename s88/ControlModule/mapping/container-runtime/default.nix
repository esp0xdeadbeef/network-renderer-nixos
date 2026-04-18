{
  lib,
  hostPlan,
}:

let
  lookup = import ./lookup.nix {
    inherit lib hostPlan;
  };

  naming = import ./naming.nix {
    inherit lib lookup;
  };

  interfaces = import ./interfaces.nix {
    inherit lib lookup;
  };
in
import ./model.nix {
  inherit
    lib
    lookup
    naming
    interfaces
    ;
}
