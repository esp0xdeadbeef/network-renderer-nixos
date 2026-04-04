{ lib }:

let
  runtimeContext = import ../../lookup/runtime-context.nix { inherit lib; };
  interfaces = import ./interfaces.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizedRuntimeTargetForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };
    in
    runtimeTarget
    // {
      interfaces = interfaces.normalizedInterfacesForUnit {
        inherit cpm unitName file;
      };
      loopback = interfaces.emittedLoopbackForUnit {
        inherit cpm unitName file;
      };
    };

  normalizedRuntimeTargets =
    {
      cpm,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      targets = runtimeContext.runtimeTargets cpm;
    in
    builtins.listToAttrs (
      map (unitName: {
        name = unitName;
        value = normalizedRuntimeTargetForUnit {
          inherit cpm unitName file;
        };
      }) (sortedAttrNames targets)
    );
in
interfaces
// {
  inherit
    normalizedRuntimeTargetForUnit
    normalizedRuntimeTargets
    ;
}
