{ lib }:

args@{
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

  ruleModel = import ./policy/default.nix (
    args
    // {
      inherit
        lib
        interfaceView
        ;
    }
  );
in
if ruleModel == null then null else import ./emission/default.nix { inherit lib; } ruleModel
