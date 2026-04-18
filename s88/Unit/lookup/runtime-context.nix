{ lib }:

let
  base = import ./runtime-context/base.nix { inherit lib; };
  validation = import ./runtime-context/validation.nix { inherit lib; };
  selection = import ./runtime-context/selection.nix { inherit lib; };
in
base // validation // selection
