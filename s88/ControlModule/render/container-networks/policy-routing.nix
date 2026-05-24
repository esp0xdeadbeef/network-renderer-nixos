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
in
{
  policyRoutingByInterface =
    builtins.foldl'
      (
        acc: entry:
        let
          index = entry.index;
          ifName = entry.ifName;
          interfaceName = renderedInterfaceNames.${ifName};
          tableId = 2000 + index;
          baseSourceIfNames = routeSources.forTarget interfaceName;
          policyIngressLocalSourceIfNames = lib.optionals (
            isPolicy && isPolicyUpstreamInterface interfaceName
          ) (lib.filter (name: isPolicyDownstreamInterface renderedInterfaceNames.${name}) interfaceNames);
          sourceIfNames = lib.unique (baseSourceIfNames ++ policyIngressLocalSourceIfNames);
          sourceScope = sourcePrefixes.forInterface interfaceName;
          forwardingScope = forwardingSourceScope.forInterface interfaceName;
          effectiveRuleSourceScope =
            let
              scoped = ruleSourceScope.forInterface interfaceName sourceScope;
            in
            scoped
            // {
              staticPrefixes = lib.unique (scoped.staticPrefixes ++ forwardingScope.staticPrefixes);
              sourceFiles = lib.unique (scoped.sourceFiles ++ forwardingScope.sourceFiles);
            };
          routesByInterface = routesByOutputInterface {
            inherit
              interfaceName
              rawRoutesForPolicyTable
              sourceIfNames
              tableId
              ;
          };
          routesByInterfacePreferred = lib.mapAttrs (_: serviceDnsRoutes.prefer) routesByInterface;
          rulesForThisInterface =
            policyRulesFor interfaceName tableId sourceIfNames effectiveRuleSourceScope.staticPrefixes;
          hasMainLookupRuleForSource =
            source:
            builtins.any (
              rule:
              (rule.From or null) == (source.prefix or null)
              && (rule.Table or null) == 254
              && (rule.SuppressPrefixLength or null) == 0
            ) rulesForThisInterface;
          mainSourceRoutes = lib.filter (route: route != null) (
            map (sourceReachabilityRoutes.routeFor ifName) (
              lib.filter (
                source:
                hasMainLookupRuleForSource source
                && sourceReachabilityRoutes.matchesInterfaceOrigin interfaceName source
              ) effectiveRuleSourceScope.staticPrefixes
            )
          );
        in
        {
          routes = builtins.foldl' (
            routesAcc: outputIfName:
            routesAcc
            // {
              ${outputIfName} =
                (routesAcc.${outputIfName} or [ ]) ++ (routesByInterfacePreferred.${outputIfName} or [ ]);
            }
          ) acc.routes (builtins.attrNames routesByInterfacePreferred);
          mainRoutes = acc.mainRoutes // {
            ${ifName} = (acc.mainRoutes.${ifName} or [ ]) ++ mainSourceRoutes;
          };
          rules = acc.rules // {
            ${ifName} =
              (acc.rules.${ifName} or [ ])
              ++ rulesForThisInterface;
          };
          dynamicSourceRules =
            acc.dynamicSourceRules
            ++ dynamicPolicyRulesFor interfaceName tableId sourceIfNames effectiveRuleSourceScope.sourceFiles;
        }
      )
      {
        routes = { };
        mainRoutes = { };
        rules = { };
        dynamicSourceRules = [ ];
      }
      (lib.imap0 (index: ifName: { inherit index ifName; }) interfaceNames);
}
