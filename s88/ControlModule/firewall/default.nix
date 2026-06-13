{ lib }:

args@{ cpm
, source ? { }
, flakeInputs ? null
, runtimeTarget ? { }
, unitKey ? null
, unitName ? null
, roleName ? null
, policyModulePath ? null
, assumptionFamily ? null
, preferSiteNode ? false
, strictEndpointBindings ? false
, interfaces ? { }
, wanIfs ? [ ]
, lanIfs ? [ ]
, interfaceView ? null
, forwardingIntent ? null
, communication ? null
, endpointMap ? null
, ...
}:

let
  uplinks = if args ? uplinks && builtins.isAttrs args.uplinks then args.uplinks else { };

  interfaceViewResolved =
    if interfaceView != null then
      interfaceView
    else
      import ./lookup/interface-view.nix {
        inherit
          lib
          interfaces
          wanIfs
          lanIfs
          ;
      };

  forwardingIntentResolved =
    if forwardingIntent != null then
      forwardingIntent
    else
      import ./lookup/forwarding-intent.nix {
        inherit
          lib
          runtimeTarget
          interfaces
          wanIfs
          lanIfs
          uplinks
          ;
      };

  communicationResolved =
    if communication != null then
      communication
    else
      import ./lookup/communication-contract.nix {
        inherit
          lib
          cpm
          flakeInputs
          runtimeTarget
          ;
      };

  endpointMapResolved =
    if endpointMap != null then
      endpointMap
    else
      import ./mapping/policy-endpoints.nix {
        inherit
          lib
          runtimeTarget
          roleName
          unitName
          preferSiteNode
          strictEndpointBindings
          ;
        interfaceView = interfaceViewResolved;
        currentSite = communicationResolved.currentSite;
        communicationContract = communicationResolved.communicationContract;
        ownership = communicationResolved.ownership;
      };

  ruleModelOrRuleset =
    if policyModulePath == null then
      null
    else
      import policyModulePath (
        args
        // {
          inherit
            lib
            ;
          interfaceView = interfaceViewResolved;
          endpointMap = endpointMapResolved;
          forwardingIntent = forwardingIntentResolved;
          communicationContract = communicationResolved.communicationContract;
          ownership = communicationResolved.ownership;
          inherit source;
        }
      );
in
if ruleModelOrRuleset == null then
  null
else if builtins.isString ruleModelOrRuleset then
  ruleModelOrRuleset
else
  import ./emission/default.nix { inherit lib; } ruleModelOrRuleset
