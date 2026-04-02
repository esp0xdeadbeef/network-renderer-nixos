{ lib }:

args@{
  cpm,
  runtimeTarget ? { },
  unitKey ? null,
  unitName ? null,
  roleName ? null,
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  ...
}:

let
  interfaceView = import ./lookup/interface-view.nix {
    inherit
      lib
      interfaces
      wanIfs
      lanIfs
      ;
  };

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

  ruleModelOrRuleset = import ./policy/default.nix (
    args
    // {
      inherit
        lib
        interfaceView
        topology
        ;
    }
  );
in
if ruleModelOrRuleset == null then
  null
else if builtins.isString ruleModelOrRuleset then
  ruleModelOrRuleset
else
  import ./emission/default.nix { inherit lib; } ruleModelOrRuleset
