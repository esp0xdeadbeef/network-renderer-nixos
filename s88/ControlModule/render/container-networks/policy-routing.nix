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

  isHostPrefix =
    source:
    let
      prefix = source.prefix or "";
    in
    builtins.isString prefix
    && (
      ((source.family or 4) == 4 && lib.hasSuffix "/32" prefix)
      || ((source.family or 4) == 6 && lib.hasSuffix "/128" prefix)
    );

  sourceReachabilityRouteFor =
    ifName: source:
    let
      iface = interfaces.${ifName};
      family = source.family or 4;
      gateway = if family == 6 then peers.ipv6PeerFor127 (peers.addressForFamily 6 iface) else peers.ipv4PeerFor31 (peers.addressForFamily 4 iface);
    in
    if gateway == null || !(isHostPrefix source) then
      null
    else
      {
        dst = source.prefix;
        intent.kind = "runtime-origin-source-reachability";
      }
      // (
        if family == 6 then
          { via6 = gateway; }
        else
          { via4 = gateway; }
      );

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
  inherit (routeHelpers) routeOutputInterface isServiceDnsReachabilityRoute;

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
      hasAcceptForwardingRule
      hasAcceptForwardingRuleForRoute
      ;
    inherit isExternalValidationDelegatedPrefixRoute;
  };

  routeDestinationKey = route: "${toString (route.table or "main")}|${route.dst or ""}";

  preferServiceDnsRoutes =
    routes:
    lib.concatMap (
      group:
      let
        serviceRoutes = lib.filter isServiceDnsReachabilityRoute group;
      in
      if serviceRoutes == [ ] then group else serviceRoutes
    ) (builtins.attrValues (builtins.groupBy routeDestinationKey routes));

  policyRulesFor = import ./policy-routing/rules.nix {
    inherit
      lib
      isSelector
      isUpstreamSelector
      isDownstreamSelectorPolicyInterface
      isUpstreamSelectorPolicyInterface
      ;
  };

  dynamicPolicyRulesFor = import ./policy-routing/dynamic-rules.nix {
    inherit
      lib
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
          rawPolicyRoutes = preferServiceDnsRoutes (
            lib.concatMap (
              sourceIfName:
              map (route: route // { _s88PolicySourceIfName = sourceIfName; }) (
                rawRoutesForPolicyTable tableId interfaceName sourceIfName
              )
            ) sourceIfNames
          );
          routesByInterface = builtins.foldl' (
            routesAcc: rawRoute:
            let
              sourceIfName = rawRoute._s88PolicySourceIfName;
              outputIfName = routeOutputInterface sourceIfName rawRoute;
              renderedRoute = mkRoute (builtins.removeAttrs rawRoute [ "_s88PolicySourceIfName" ]);
            in
            if renderedRoute == null then
              routesAcc
            else
              routesAcc
              // {
                ${outputIfName} = (routesAcc.${outputIfName} or [ ]) ++ [ renderedRoute ];
              }
          ) { } rawPolicyRoutes;
          mainSourceRoutes = lib.filter (route: route != null) (
            map (sourceReachabilityRouteFor ifName) effectiveRuleSourceScope.staticPrefixes
          );
        in
        {
          routes = builtins.foldl' (
            routesAcc: outputIfName:
            routesAcc
            // {
              ${outputIfName} = (routesAcc.${outputIfName} or [ ]) ++ (routesByInterface.${outputIfName} or [ ]);
            }
          ) acc.routes (builtins.attrNames routesByInterface);
          mainRoutes = acc.mainRoutes // {
            ${ifName} = (acc.mainRoutes.${ifName} or [ ]) ++ mainSourceRoutes;
          };
          rules = acc.rules // {
            ${ifName} =
              (acc.rules.${ifName} or [ ])
              ++ policyRulesFor interfaceName tableId sourceIfNames effectiveRuleSourceScope.staticPrefixes;
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
