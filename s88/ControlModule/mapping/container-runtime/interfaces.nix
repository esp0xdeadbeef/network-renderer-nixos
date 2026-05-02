{
  lib,
  lookup,
}:

let
  naming = import ./interfaces/naming.nix { inherit lib; };
  attach = import ./interfaces/attach.nix { inherit lib lookup naming; };
  normalize = import ./interfaces/normalize.nix {
    inherit lib lookup naming attach;
  };
  veths = import ./interfaces/veths.nix { inherit lib lookup; };
in
{
  inherit (attach) sourceKindForInterface attachTargetForInterface;
  inherit (normalize) normalizedInterfacesForUnit;
  inherit (veths) vethsForInterfaces;
}
