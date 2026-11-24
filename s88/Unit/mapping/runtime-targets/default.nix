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
      normalizedInterfaces = interfaces.normalizedInterfacesForUnit {
        inherit cpm unitName file;
      };
    in
    runtimeTarget
    // {
      interfaces = normalizedInterfaces;

      canonicalForwarding =
        let
          model = if builtins.isAttrs cpm then (cpm.model or cpm) else { };
        in
        model.canonicalForwarding or { };
      policyRoutingSources = interfaces.policyRoutingSources normalizedInterfaces runtimeTarget;
      networkBehavior = interfaces.networkBehavior normalizedInterfaces runtimeTarget;
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
