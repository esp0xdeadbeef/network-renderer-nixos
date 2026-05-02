{
  lib,
  lookup,
  naming,
  interfaces,
}:

let
  assembly = import ./model/container-assembly.nix {
    inherit lib lookup naming interfaces;
  };

  overlay = import ./model/overlay-routes.nix {
    inherit lib lookup;
  };

  renderedContainersBase = builtins.listToAttrs (
    map (unitName: {
      name = naming.emittedUnitNameForUnit unitName;
      value = assembly.mkContainerRuntime unitName;
    }) lookup.enabledUnits
  );

  renderedContainers = overlay.enrichOverlayRoutesForContainers renderedContainersBase;
in
builtins.seq naming.validateUniqueEmittedRuntimeUnitNames renderedContainers
