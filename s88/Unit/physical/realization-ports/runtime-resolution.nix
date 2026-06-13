{ lib }:

let
  sourceModel = import ./source-model.nix { inherit lib; };
  common = import ./runtime-resolution/common.nix { inherit lib sourceModel; };

  nodes = import ./runtime-resolution/nodes.nix {
    inherit lib sourceModel common;
  };

  linkMatches = import ./runtime-resolution/link-matches.nix {
    inherit lib sourceModel common nodes;
  };

  portResolution = import ./runtime-resolution/port-resolution.nix {
    inherit lib sourceModel nodes linkMatches;
  };

  attachTargets = import ./runtime-resolution/attach-targets.nix {
    inherit lib sourceModel common portResolution;
  };
in
{
  inherit (attachTargets) attachTargetsForUnitsFromRuntime;
}
