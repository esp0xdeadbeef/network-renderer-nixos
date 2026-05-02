{ lib }:

let
  inventoryModel = import ./inventory.nix { inherit lib; };
  common = import ./runtime-resolution/common.nix { inherit lib inventoryModel; };

  nodes = import ./runtime-resolution/nodes.nix {
    inherit lib inventoryModel common;
  };

  linkMatches = import ./runtime-resolution/link-matches.nix {
    inherit lib inventoryModel common nodes;
  };

  portResolution = import ./runtime-resolution/port-resolution.nix {
    inherit lib inventoryModel nodes linkMatches;
  };

  attachTargets = import ./runtime-resolution/attach-targets.nix {
    inherit lib inventoryModel common portResolution;
  };
in
{
  inherit (attachTargets) attachTargetsForUnitsFromRuntime;
}
