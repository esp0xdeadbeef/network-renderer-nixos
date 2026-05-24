{
  lib,
  containerModel,
  common,
  forwardingIntent ? null,
  firewallRuleset ? null,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  laneAccessForRenderedName,
  upstreamLanesMatch,
  isSelector,
  isUpstreamSelector,
  isPolicy,
  isDownstreamSelectorAccessInterface,
  isDownstreamSelectorPolicyInterface,
  isUpstreamSelectorCoreInterface,
  isUpstreamSelectorPolicyInterface,
  isPolicyDownstreamInterface,
  isPolicyUpstreamInterface,
  isOverlayInterface,
  isCoreTransitInterface,
  mkRoute,
  isExternalValidationDelegatedPrefixRoute,
}:
let
  peers = import ./policy-routing/peers.nix {
    inherit lib common;
  };
  forwardingRuleSet = import ./policy-routing/forwarding-rules.nix {
    inherit lib containerModel forwardingIntent;
  };
  inherit (forwardingRuleSet)
    forwardingRulesResolved
    hasAcceptForwardingRule
    hasAcceptForwardingRuleForRoute
    ;
  routeSources = import ./policy-routing/source-interfaces.nix {
    inherit
      lib
      interfaces
      interfaceNames
      renderedInterfaceNames
      ;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
    policyRoutingSources = containerModel.policyRoutingSources or { };
    forwardingRules = forwardingRulesResolved;
  };
  sourceReachabilityRoutes = import ./policy-routing/source-reachability-routes.nix {
    inherit
      lib
      interfaces
      laneAccessForRenderedName
      peers
      ;
  };
  siteDestinations = import ./policy-routing/site-destinations.nix {
    inherit lib containerModel common;
  };
  returnRoutes = import ./policy-routing/return-routes.nix {
    inherit
      lib
      common
      interfaces
      renderedInterfaceNames
      isUpstreamSelector
      isUpstreamSelectorCoreInterface
      ;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
    inherit (siteDestinations) returnDestinationsForTenant;
  };
  routeHelpers = import ./policy-routing/route-helpers.nix {
    inherit
      lib
      interfaces
      interfaceNames
      peers
      ;
  };
  inherit (routeHelpers) routeOutputInterface;
  serviceDnsRoutes = import ./policy-routing/service-dns-routes.nix {
    inherit lib routeHelpers;
  };
  explicitReturnRoutes = import ./policy-routing/explicit-return-routes.nix {
    inherit
      lib
      common
      interfaces
      interfaceNames
      renderedInterfaceNames
      ;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
  };
  policyOnlyProjection = import ./policy-routing/policy-only-projection.nix {
    inherit renderedInterfaceNames;
    policyRoutingSources = containerModel.policyRoutingSources or { };
  };
  sourcePrefixes = import ./policy-routing/source-prefixes.nix {
    inherit lib containerModel laneAccessForRenderedName;
  };
  forwardingSourceScope = import ./policy-routing/forwarding-source-scope.nix {
    inherit lib forwardingRulesResolved;
  };
  ruleSourceScope = import ./policy-routing/rule-source-scope.nix {
    inherit
      isSelector
      isPolicy
      isDownstreamSelectorPolicyInterface
      isPolicyUpstreamInterface
      ;
  };
  rawRoutesForPolicyTable = import ./policy-routing/raw-routes.nix {
    inherit
      lib
      interfaces
      interfaceNames
      renderedInterfaceNames
      ;
    inherit
      isSelector
      isUpstreamSelector
      isPolicy
      isDownstreamSelectorPolicyInterface
      ;
    inherit
      isUpstreamSelectorCoreInterface
      isUpstreamSelectorPolicyInterface
      isPolicyDownstreamInterface
      ;
    inherit
      returnRoutes
      explicitReturnRoutes
      policyOnlyProjection
      routeHelpers
      routeOutputInterface
      hasAcceptForwardingRule
      hasAcceptForwardingRuleForRoute
      ;
    inherit isExternalValidationDelegatedPrefixRoute;
  };
  routesByOutputInterface = import ./policy-routing/routes-by-output-interface.nix {
    inherit mkRoute routeOutputInterface;
  };
  policyRulesFor = import ./policy-routing/rules.nix {
    inherit
      lib
      renderedInterfaceNames
      isSelector
      isUpstreamSelector
      isDownstreamSelectorPolicyInterface
      isUpstreamSelectorPolicyInterface
      ;
  };
  dynamicPolicyRulesFor = import ./policy-routing/dynamic-rules.nix {
    inherit
      lib
      renderedInterfaceNames
      isSelector
      isUpstreamSelector
      isDownstreamSelectorPolicyInterface
      isUpstreamSelectorPolicyInterface
      ;
  };
  aggregatePolicyRouting = import ./policy-routing/aggregate.nix {
    inherit
      lib
      interfaceNames
      renderedInterfaceNames
      isPolicy
      isPolicyUpstreamInterface
      isPolicyDownstreamInterface
      sourceReachabilityRoutes
      sourcePrefixes
      forwardingSourceScope
      ruleSourceScope
      routesByOutputInterface
      rawRoutesForPolicyTable
      serviceDnsRoutes
      policyRulesFor
      dynamicPolicyRulesFor
      ;
    inherit (routeSources) forTarget forTargetRules;
  };
in
{
  policyRoutingByInterface = aggregatePolicyRouting;
}
