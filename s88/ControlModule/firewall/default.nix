{ lib }:

{
  cpm,
  inventory,
  unitKey,
  unitName,
  roleName,
  runtimeTarget,
  interfaces,
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
}:

let
  topology = import ./lookup/topology.nix {
    inherit
      lib
      cpm
      runtimeTarget
      unitKey
      unitName
      roleName
      ;
  };

  interfaceClasses = import ./mapping/interface-classes.nix {
    inherit
      lib
      interfaces
      topology
      uplinks
      wanIfs
      lanIfs
      ;
  };

  featurePlan = import ./policy/features.nix {
    inherit
      lib
      roleName
      runtimeTarget
      interfaceClasses
      ;
  };

  fragments = lib.filter (fragment: fragment != null) [
    (import ./cm/base-hygiene.nix {
      inherit lib featurePlan;
    })
    (import ./cm/control-traffic.nix {
      inherit
        lib
        featurePlan
        interfaceClasses
        ;
    })
    (import ./cm/wan-client-control.nix {
      inherit
        lib
        featurePlan
        interfaceClasses
        ;
    })
    (import ./cm/forward-pairs.nix {
      inherit lib featurePlan;
    })
    (import ./cm/nat.nix {
      inherit lib featurePlan;
    })
    (import ./cm/port-forward.nix {
      inherit
        lib
        featurePlan
        interfaceClasses
        ;
    })
    (import ./cm/tcp-mss-clamp.nix {
      inherit lib featurePlan;
    })
  ];

  ruleModel = import ./mapping/rule-model.nix {
    inherit lib fragments;
  };
in
import ./emission/nftables.nix {
  inherit
    lib
    ruleModel
    ;
}
