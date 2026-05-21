{ lib
, cpm ? null
, inventory ? { }
, uplinks ? { }
, renderedModel
,
}:

let
  firewall = import ../../firewall/default.nix { inherit lib; };

  runtimeInterfaces =
    if
      renderedModel ? runtimeTarget
      && builtins.isAttrs renderedModel.runtimeTarget
      && builtins.isAttrs ((renderedModel.runtimeTarget.effectiveRuntimeRealization or { }).interfaces or null)
    then
      renderedModel.runtimeTarget.effectiveRuntimeRealization.interfaces
    else
      { };

  runtimeTarget =
    if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
      renderedModel.runtimeTarget
    else
      { };

  interfaces =
    if renderedModel ? interfaces && builtins.isAttrs renderedModel.interfaces && renderedModel.interfaces != { } then
      renderedModel.interfaces
    else
      runtimeInterfaces;

  wanIfs =
    if renderedModel ? wanInterfaceNames && builtins.isList renderedModel.wanInterfaceNames then
      renderedModel.wanInterfaceNames
    else
      [ ];

  lanIfs =
    if renderedModel ? lanInterfaceNames && builtins.isList renderedModel.lanInterfaceNames then
      renderedModel.lanInterfaceNames
    else
      [ ];

  unitKey = if renderedModel ? unitKey then renderedModel.unitKey else null;
  unitName = if renderedModel ? unitName then renderedModel.unitName else null;
  roleName = if renderedModel ? roleName then renderedModel.roleName else null;
  networkBehavior =
    if renderedModel ? networkBehavior && builtins.isAttrs renderedModel.networkBehavior then
      renderedModel.networkBehavior
    else
      { };
  policyModulePath = renderedModel.firewallPolicyPath or null;
  assumptionFamily = renderedModel.assumptionFamily or null;
  preferSiteNode = renderedModel.preferSiteNode or false;
  strictEndpointBindings = renderedModel.strictEndpointBindings or false;

  forwardingIntent = import ../../firewall/lookup/forwarding-intent.nix {
    inherit
      lib
      runtimeTarget
      interfaces
      wanIfs
      lanIfs
      uplinks
      ;
  };

  communication = import ../../firewall/lookup/communication-contract.nix {
    inherit
      lib
      cpm
      runtimeTarget
      ;
  };

  interfaceView = import ../../firewall/lookup/interface-view.nix {
    inherit
      lib
      interfaces
      wanIfs
      lanIfs
      ;
  };

  endpointMap = import ../../firewall/mapping/policy-endpoints.nix {
    inherit
      lib
      interfaceView
      runtimeTarget
      roleName
      unitName
      preferSiteNode
      strictEndpointBindings
      ;
    currentSite = communication.currentSite;
    communicationContract = communication.communicationContract;
    ownership = communication.ownership;
  };

  policyRelationForwardPairs = import ../../firewall/policy/relation-forward-pairs.nix {
    inherit lib endpointMap;
    communicationContract = communication.communicationContract;
  };

  routeForwardingIntent = forwardingIntent // {
    policyRelationForwardPairs =
      if
        (forwardingIntent.normalizedExplicitForwardPairs or [ ]) != [ ]
          && (forwardingIntent.nodeForwarding.mode or null) == "explicit-selector-forwarding"
          && (
          (networkBehavior.isSelector or false)
            || (networkBehavior.isUpstreamSelector or false)
            || (networkBehavior.isDownstreamSelector or false)
        )
      then
        [ ]
      else
        policyRelationForwardPairs;
  };

  mkFirewallArg =
    nftRuleset: forwardingIntent:
    (if builtins.isString nftRuleset && nftRuleset != "" then
      {
        enable = true;
        ruleset = nftRuleset;
      }
    else
      {
        enable = false;
        ruleset = null;
      })
    // {
      inherit forwardingIntent;
      lookup = {
        inherit
          interfaceView
          communication
          endpointMap
          ;
        forwardingIntent = routeForwardingIntent;
      };
    };
in
if cpm == null then
  if renderedModel ? firewall && builtins.isAttrs renderedModel.firewall then
    renderedModel.firewall
  else
    {
      enable = false;
      ruleset = null;
    }
else
  mkFirewallArg
    (firewall {
      inherit cpm inventory uplinks;
      inherit interfaceView endpointMap;
      communication = communication;
      forwardingIntent = routeForwardingIntent;
      inherit
        unitKey
        unitName
        roleName
        policyModulePath
        assumptionFamily
        preferSiteNode
        strictEndpointBindings
        ;
      inherit
        runtimeTarget
        interfaces
        wanIfs
        lanIfs
        ;
    })
    routeForwardingIntent
