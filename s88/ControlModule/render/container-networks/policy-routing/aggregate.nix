{ lib
, interfaceNames
, renderedInterfaceNames
, isPolicy
, isDownstreamSelectorPolicyInterface
, isUpstreamSelectorCoreInterface
, isPolicyUpstreamInterface
, isPolicyDownstreamInterface
, sourceReachabilityRoutes
, sourcePrefixes
, forwardingSourceScope
, ruleSourceScope
, routesByOutputInterface
, rawRoutesForPolicyTable
, serviceDnsRoutes
, policyRulesFor
, dynamicPolicyRulesFor
, forTarget
, forTargetRules
,
}:
# CODE trace:
# USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-006 /
# USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-007 ->
# USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-006 /
# USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-007 ->
# CMC-FUNC-POLICY-ROUTING-003 through CMC-FUNC-POLICY-ROUTING-010.
#
# This ControlModule assembles explicit CPM route/rule/source-scope contracts
# into NixOS policy-routing artifacts. Source-scoped egress and
# destination-scoped return selectors are independent selectors for the same
# modeled table; target-side scope must not leak to unrelated ingress.
builtins.foldl'
  (
    acc: entry:
    let
      index = entry.index;
      ifName = entry.ifName;
      interfaceName = renderedInterfaceNames.${ifName};
      tableId = 2000 + index;
      routeSourceIfNames = forTarget interfaceName;
      baseSourceIfNames = forTargetRules interfaceName;
      policyIngressLocalSourceIfNames = lib.optionals
        (
          isPolicy && isPolicyUpstreamInterface interfaceName
        )
        (lib.filter (name: isPolicyDownstreamInterface renderedInterfaceNames.${name}) interfaceNames);
      sourceIfNames = lib.unique (baseSourceIfNames ++ policyIngressLocalSourceIfNames);
      sourceScope = sourcePrefixes.forInterface interfaceName;
      forwardingMainScope = forwardingSourceScope.forSourceInterface interfaceName;
      scopedRuleSource = ruleSourceScope.forInterface interfaceName sourceScope;
      emptyScope = {
        staticPrefixes = [ ];
        sourceFiles = [ ];
      };
      scopeHasEntries =
        scope: (scope.staticPrefixes or [ ]) != [ ] || (scope.sourceFiles or [ ]) != [ ];
      isReturnSideRuleIngress =
        sourceIfName:
        let
          sourceInterfaceName = renderedInterfaceNames.${sourceIfName};
        in
        (
          isDownstreamSelectorPolicyInterface interfaceName
          && isDownstreamSelectorPolicyInterface sourceInterfaceName
        )
        || (
          isPolicyUpstreamInterface interfaceName
          && isPolicyUpstreamInterface sourceInterfaceName
        )
        || (
          isUpstreamSelectorCoreInterface interfaceName
          && isUpstreamSelectorCoreInterface sourceInterfaceName
        );
      effectiveMainSourceScope = sourceScope // {
        staticPrefixes = lib.unique (sourceScope.staticPrefixes ++ forwardingMainScope.staticPrefixes);
        sourceFiles = lib.unique (sourceScope.sourceFiles ++ forwardingMainScope.sourceFiles);
      };
      ruleSourceScopeForIngress =
        sourceIfName:
        let
          sourceInterfaceName = renderedInterfaceNames.${sourceIfName};
          ingressSourceScope = sourcePrefixes.forInterface sourceInterfaceName;
          baseScope =
            if isReturnSideRuleIngress sourceIfName then
              scopedRuleSource
            else if scopeHasEntries ingressSourceScope then
              ingressSourceScope
            else
              sourceScope;
          pairScope =
            if isDownstreamSelectorPolicyInterface interfaceName then
              {
                staticPrefixes = [ ];
                sourceFiles = [ ];
              }
            else
              forwardingSourceScope.forPair sourceInterfaceName interfaceName;
          forwardingScopeForIngress =
            if sourceIfName == ifName || isReturnSideRuleIngress sourceIfName then
              forwardingMainScope
            else
              emptyScope;
        in
        baseScope
        // {
          staticPrefixes = lib.unique (
            (baseScope.staticPrefixes or [ ])
            ++ forwardingScopeForIngress.staticPrefixes
            ++ pairScope.staticPrefixes
          );
          sourceFiles = lib.unique (
            (baseScope.sourceFiles or [ ]) ++ forwardingScopeForIngress.sourceFiles ++ pairScope.sourceFiles
          );
        };
      routesByInterface = routesByOutputInterface {
        inherit
          interfaceName
          rawRoutesForPolicyTable
          tableId
          ;
        sourceIfNames = routeSourceIfNames;
      };
      routesByInterfacePreferred = lib.mapAttrs (_: serviceDnsRoutes.prefer) routesByInterface;
      destinationScopeForIngress =
        sourceIfName:
        let
          routesForTargetOutput = routesByInterface.${ifName} or [ ];
          routeDestinations = map (route: route.Destination or null) routesForTargetOutput;
        in
        lib.filter (prefix: builtins.elem prefix.prefix routeDestinations) (
          (ruleSourceScopeForIngress sourceIfName).staticPrefixes
        );
      rulesForThisInterface = lib.concatMap
        (
          sourceIfName:
          let
            destinationScope = if sourceIfName == ifName then [ ] else destinationScopeForIngress sourceIfName;
            sourceScopeForRule = (ruleSourceScopeForIngress sourceIfName).staticPrefixes;
            destinationScopedRules =
              policyRulesFor interfaceName tableId [ sourceIfName ] [ ] destinationScope;
            sourceScopedRules =
              policyRulesFor interfaceName tableId [ sourceIfName ] sourceScopeForRule [ ];
          in
          if destinationScope != [ ] && sourceScopeForRule != [ ] then
            destinationScopedRules ++ sourceScopedRules
          else
            policyRulesFor interfaceName tableId [ sourceIfName ] sourceScopeForRule destinationScope
        )
        sourceIfNames;
      forwardingIngressRules =
        let
          tableRuleFor = prefix: {
            Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
            From = prefix.prefix;
            IncomingInterface = interfaceName;
            Priority = tableId;
            Table = tableId;
          };
          mainFallbackRuleFor = prefix: {
            Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
            From = prefix.prefix;
            IncomingInterface = interfaceName;
            Priority = 10000 + tableId;
            SuppressPrefixLength = 0;
            Table = 254;
          };
        in
        builtins.concatMap
          (prefix: [
            (tableRuleFor prefix)
            (mainFallbackRuleFor prefix)
          ])
          forwardingMainScope.staticPrefixes;
      allRulesForThisInterface = lib.unique (rulesForThisInterface ++ forwardingIngressRules);
      hasMainLookupRuleForSource =
        source:
        builtins.any
          (
            rule:
            (rule.From or null) == (source.prefix or null)
            && (rule.Table or null) == 254
            && (rule.SuppressPrefixLength or null) == 0
          )
          allRulesForThisInterface;
      mainSourceRoutes = lib.filter (route: route != null) (
        map (sourceReachabilityRoutes.routeFor ifName) (
          lib.filter
            (
              source:
              hasMainLookupRuleForSource source
              && sourceReachabilityRoutes.matchesInterfaceOrigin interfaceName source
            )
            effectiveMainSourceScope.staticPrefixes
        )
      );
    in
    {
      routes = builtins.foldl'
        (
          routesAcc: outputIfName:
            routesAcc
            // {
              ${outputIfName} =
                (routesAcc.${outputIfName} or [ ]) ++ (routesByInterfacePreferred.${outputIfName} or [ ]);
            }
        )
        acc.routes
        (builtins.attrNames routesByInterfacePreferred);
      mainRoutes = acc.mainRoutes // {
        ${ifName} = (acc.mainRoutes.${ifName} or [ ]) ++ mainSourceRoutes;
      };
      rules = acc.rules // {
        ${ifName} = (acc.rules.${ifName} or [ ]) ++ allRulesForThisInterface;
      };
      dynamicSourceRules =
        acc.dynamicSourceRules
        ++ lib.concatMap
          (
            sourceIfName:
            dynamicPolicyRulesFor interfaceName tableId [ sourceIfName ] (ruleSourceScopeForIngress sourceIfName).sourceFiles
          )
          sourceIfNames;
    }
  )
{
  routes = { };
  mainRoutes = { };
  rules = { };
  dynamicSourceRules = [ ];
}
  (lib.imap0 (index: ifName: { inherit index ifName; }) interfaceNames)
