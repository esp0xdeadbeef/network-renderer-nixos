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
  isAccessHostInterface,
  mkRoute,
  isExternalValidationDelegatedPrefixRoute,
  sourceKindForRenderedName,
  runtimeInterfaceToContainerName ? { },
}:
let
  peers = import ./policy-routing/peers.nix {
    inherit lib common;
  };
  forwardingRuleSet = import ./policy-routing/forwarding-rules.nix {
    inherit
      lib
      containerModel
      forwardingIntent
      runtimeInterfaceToContainerName
      ;
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
    inherit (siteDestinations) returnDestinationsForAccessUnit returnDestinationsForTenant;
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
  localOriginDns = import ./policy-routing/local-origin-dns.nix {
    inherit lib interfaces routeHelpers;
    services = containerModel.services or { };
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
    inherit
      lib
      containerModel
      laneAccessForRenderedName
      sourceKindForRenderedName
      ;
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
      isDownstreamSelectorAccessInterface
      isDownstreamSelectorPolicyInterface
      ;
    inherit
      isUpstreamSelectorCoreInterface
      isUpstreamSelectorPolicyInterface
      isPolicyDownstreamInterface
      isPolicyUpstreamInterface
      isAccessHostInterface
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

    selectedScopes = selectedScopesOf resolvedReachability;
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
      isDownstreamSelectorPolicyInterface
      isUpstreamSelectorCoreInterface
      isUpstreamSelectorPolicyInterface
      isPolicyUpstreamInterface
      isPolicyDownstreamInterface
      isAccessHostInterface
      isDownstreamSelectorAccessInterface
      laneAccessForRenderedName
      returnRoutes
      forwardingRulesResolved
      interfaces
      sourceReachabilityRoutes
      sourcePrefixes
      forwardingSourceScope
      ruleSourceScope
      routesByOutputInterface
      rawRoutesForPolicyTable
      serviceDnsRoutes
      localOriginDns
      policyRulesFor
      dynamicPolicyRulesFor
      hasAcceptForwardingRule
      ;
    policyRoutingAllocations = lib.mapAttrs (
      _: iface: if iface ? policyRoutingAllocation then iface.policyRoutingAllocation else null
    ) interfaces;
    inherit (routeSources) forTarget forTargetRules;
  };

  modeledLaneRoutes = builtins.concatLists (
    map (
      name:
      map (route: { inherit (route) dst via4 via6; }) (
        builtins.filter
          (
            route:
            ((route.lane or { }).access or null) != null
            && ((route.intent or { }).kind or null) == "internal-reachability"
          )
          (
            ((interfaces.${name}.routes or { }).ipv4 or [ ]) ++ ((interfaces.${name}.routes or { }).ipv6 or [ ])
          )
      )
    ) interfaceNames
  );
  reflectedPeerRoute =
    renderedName: route:
    let
      ifName = lib.findFirst (n: renderedInterfaceNames.${n} == renderedName) null interfaceNames;
      addr4 = if ifName == null then null else peers.addressForFamily 4 interfaces.${ifName};
      addr6 = if ifName == null then null else peers.addressForFamily 6 interfaces.${ifName};
      peer4 = if addr4 == null then null else peers.ipv4PeerFor31 addr4;
      peer6 = if addr6 == null then null else peers.ipv6PeerFor127 addr6;
      gateway = route.via4 or route.via6 or route.Gateway or null;
      dst = route.dst or route.Destination or null;
      modeled = builtins.filter (m: (m.dst or null) == dst) modeledLaneRoutes;
    in
    builtins.any (
      m:
      ((m.via4 or null) != null && gateway == peer4 && gateway != m.via4)
      || ((m.via6 or null) != null && gateway == peer6 && gateway != m.via6)
    ) modeled;
  modeledScopedDestinationsByLane = builtins.listToAttrs (
    map (name: {
      name = renderedInterfaceNames.${name};
      value = map (route: { inherit (route) dst via4 via6; }) (
        builtins.filter
          (
            route:
            ((route.lane or { }).access or null) != null
            && ((route.intent or { }).kind or null) == "internal-reachability"
          )
          (
            ((interfaces.${name}.routes or { }).ipv4 or [ ]) ++ ((interfaces.${name}.routes or { }).ipv6 or [ ])
          )
      );
    }) interfaceNames
  );
  aggregatePolicyRoutingFiltered = aggregatePolicyRouting // {
    routes = lib.mapAttrs (
      renderedName: routes: lib.filter (route: !(reflectedPeerRoute renderedName route)) routes
    ) (aggregatePolicyRouting.routes or { });
  };

  effectiveRuntimeRealization =
    if
      containerModel ? runtimeTarget
      && builtins.isAttrs containerModel.runtimeTarget
      && builtins.isAttrs (containerModel.runtimeTarget.effectiveRuntimeRealization or null)
    then
      containerModel.runtimeTarget.effectiveRuntimeRealization
    else
      { };
  resolvedReachability =
    let
      value = effectiveRuntimeRealization.resolvedReachability or { };
    in
    if builtins.isAttrs value then value else { };

  selectedScopesOf =
    reachability:
    lib.unique (
      builtins.filter builtins.isString (
        map (entry: entry.scope or null) (
          if builtins.isList (reachability.selects or null) then reachability.selects else [ ]
        )
      )
    );
  relationSelectionRulesRaw = effectiveRuntimeRealization.routeSelectionRules or [ ];
  relationSelectionRules =
    if builtins.isList relationSelectionRulesRaw then
      import ./policy-routing/relation-selection-rules.nix {
        inherit
          lib
          interfaces
          renderedInterfaceNames
          ;
        routeSelectionRules = relationSelectionRulesRaw;
      }
    else
      throw "FS-270-HDS-010-SDS-010-SMS-020: effectiveRuntimeRealization.routeSelectionRules must be a list";
  relationRuleKeys = builtins.attrNames relationSelectionRules.rulesByInterface;
  targetOriginatedSelection = import ./policy-routing/target-originated-selection.nix {
    inherit
      lib
      interfaces
      renderedInterfaceNames
      ;
    targetOriginatedSelection = effectiveRuntimeRealization.targetOriginatedSelection or null;
  };
  targetOriginatedRuleKeys = builtins.attrNames targetOriginatedSelection.rulesByInterface;
  allRuleKeys = lib.unique (
    (builtins.attrNames aggregatePolicyRouting.rules) ++ relationRuleKeys ++ targetOriginatedRuleKeys
  );
  policyRoutingWithRelationSelection = aggregatePolicyRoutingFiltered // {
    rules = builtins.listToAttrs (
      map (ifName: {
        name = ifName;
        value =
          (aggregatePolicyRouting.rules.${ifName} or [ ])
          ++ (relationSelectionRules.rulesByInterface.${ifName} or [ ])
          ++ (targetOriginatedSelection.rulesByInterface.${ifName} or [ ]);
      }) allRuleKeys
    );
  };
in
{
  policyRoutingByInterface =
    let
      merged = import ./policy-routing/multipath-merge.nix {
        inherit lib renderedInterfaceNames;
        routesByInterface = policyRoutingWithRelationSelection.routes or { };
      };
    in
    policyRoutingWithRelationSelection // { routes = merged; };

  rawRoutesByInterface = policyRoutingWithRelationSelection.routes or { };
  inherit modeledScopedDestinationsByLane;
}
