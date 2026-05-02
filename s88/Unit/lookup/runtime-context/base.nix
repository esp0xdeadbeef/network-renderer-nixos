{ lib }:

let
  common = import ./base/common.nix { inherit lib; };
  targets = import ./base/targets.nix { inherit lib common; };
  realization = import ./base/realization.nix {
    inherit lib common targets;
  };
in
{
  inherit (common) sortedAttrNames;
  inherit (targets)
    siteEntries
    runtimeTargetInstanceId
    runtimeTargetEntries
    runtimeTargets
    siteEntryForUnit
    runtimeTargetForUnit
    runtimeTargetIdForUnit
    logicalNodeForUnit
    logicalNodeNameForUnit
    logicalNodeIdentityForUnit
    roleForUnit
    ;
  inherit (realization)
    realizationNodesFor
    logicalNodeForRealizationNode
    candidateRealizationNodeNamesForUnit
    realizationNodeForUnit
    realizationHostForUnit
    ;
}
