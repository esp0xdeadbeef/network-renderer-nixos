{ lib }:

args@{
  cpm,
  flakeInputs ? null,
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

  communication = import ./lookup/communication-contract.nix {
    inherit
      lib
      cpm
      flakeInputs
      runtimeTarget
      ;
  };

  endpointMap = import ./mapping/policy-endpoints.nix {
    inherit
      lib
      interfaceView
      ;
    currentSite = communication.currentSite;
    communicationContract = communication.communicationContract;
    ownership = communication.ownership;
  };

  ruleModelOrRuleset = import ./policy/default.nix (
    args
    // {
      inherit
        lib
        interfaceView
        endpointMap
        ;
      communicationContract = communication.communicationContract;
      ownership = communication.ownership;
    }
  );
in
if ruleModelOrRuleset == null then
  null
else if builtins.isString ruleModelOrRuleset then
  ruleModelOrRuleset
else
  import ./emission/default.nix { inherit lib; } ruleModelOrRuleset
