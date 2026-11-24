{ lib }:

let
  runtimeContext = import ../../lookup/runtime-context.nix { inherit lib; };
  interfaces = import ./interfaces.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  # FS-310-HDS-020-SDS-010-SMS-060 (rendered policy route placement / lane
  # occurrence).
  #
  # `policyRoutingSources` (which interfaces feed which policy table) and
  # `networkBehavior` (the class flags that make a target a selector, a policy
  # target, an upstream selector or an access gateway) are FACTS ABOUT THE
  # NETWORK. `network-control-plane-model/src` has zero occurrences of either
  # name, so the model does not publish them: the two projections below --
  # `interfaces/policy-routing-sources.nix` and `interfaces/network-behavior.nix`
  # -- author them from interface topology instead. That is the derivation the
  # SMS forbids by name: "The renderer shall not choose, infer, or withhold a
  # route's table or lane occurrence".
  #
  # So the derivation is not allowed to stand in for a model fact. Where a target
  # needs one, the model must supply it; if it does not, the render fails here and
  # names the field, the target and the row that has to publish it. The two
  # derivation files stay for now -- replacing this throw with a real model field
  # is the fix, and it is a separate change with the row's own commit.
  requireModelFact =
    {
      field,
      unitName,
      target,
    }:
    if target ? ${field} && target.${field} != null then
      target.${field}
    else
      throw "FS-310-HDS-020-SDS-010-SMS-060: the model supplies no '${field}' for runtime target '${unitName}'. This renderer derives it from interface topology (s88/Unit/mapping/runtime-targets/interfaces/), which the row forbids: a renderer may not choose a route's table or lane occurrence, and it may not decide which interfaces feed a policy table. The control-plane model must publish '${field}' on the runtime target under FS-310-HDS-020-SDS-010-SMS-060; until it does, this renderer cannot render the target.";

  normalizedRuntimeTargetForUnit =
    { cpm
    , unitName
    , file ? "s88/Unit/mapping/runtime-targets.nix"
    ,
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };
      normalizedInterfaces = interfaces.normalizedInterfacesForUnit {
        inherit cpm unitName file;
      };
      # Forced before the merge below, so a target the model does not describe
      # fails even though the derivation would have produced a plausible value.
      _modelPublishesFacts = [
        (requireModelFact {
          field = "policyRoutingSources";
          inherit unitName;
          target = runtimeTarget;
        })
        (requireModelFact {
          field = "networkBehavior";
          inherit unitName;
          target = runtimeTarget;
        })
      ];
    in
    builtins.deepSeq _modelPublishesFacts (
      runtimeTarget
      // {
        interfaces = normalizedInterfaces;
        policyRoutingSources = interfaces.policyRoutingSources normalizedInterfaces;
        networkBehavior = interfaces.networkBehavior normalizedInterfaces;
        loopback = interfaces.emittedLoopbackForUnit {
          inherit cpm unitName file;
        };
      }
    );

  normalizedRuntimeTargets =
    { cpm
    , file ? "s88/Unit/mapping/runtime-targets.nix"
    ,
    }:
    let
      targets = runtimeContext.runtimeTargets cpm;
    in
    builtins.listToAttrs (
      map
        (unitName: {
          name = unitName;
          value = normalizedRuntimeTargetForUnit {
            inherit cpm unitName file;
          };
        })
        (sortedAttrNames targets)
    );
in
interfaces
  // {
  inherit
    normalizedRuntimeTargetForUnit
    normalizedRuntimeTargets
    ;
}
