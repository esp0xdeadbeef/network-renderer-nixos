{ lib }:

let
  inventoryModel = import ./realization-ports/inventory.nix { inherit lib; };
  runtimeResolution = import ./realization-ports/runtime-resolution.nix { inherit lib; };
in
inventoryModel // runtimeResolution
