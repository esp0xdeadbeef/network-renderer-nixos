{ lib }:

let
  sourceModel = import ./realization-ports/source-model.nix { inherit lib; };
  runtimeResolution = import ./realization-ports/runtime-resolution.nix { inherit lib; };
in
sourceModel // runtimeResolution
