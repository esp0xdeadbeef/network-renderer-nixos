{ lib
, interfaceNames
, renderedInterfaceNames
, isPolicy
, isDownstreamSelectorPolicyInterface
, isUpstreamSelectorCoreInterface
, isUpstreamSelectorPolicyInterface
, isPolicyUpstreamInterface
, isPolicyDownstreamInterface
, sourceReachabilityRoutes
, sourcePrefixes
, forwardingSourceScope
, ruleSourceScope
, routesByOutputInterface
, rawRoutesForPolicyTable
, serviceDnsRoutes
, localOriginDns ? {
    routesByInterface = _tableId: _sourceIfNames: { };
    rules = _tableId: _priority: _sourceIfNames: [ ];
  }
, policyRulesFor
, dynamicPolicyRulesFor
, hasAcceptForwardingRule
, policyRoutingAllocations
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
let
  positiveInt =
    ifName: field: value:
    if builtins.isInt value && value > 0 then
      value
    else
      throw "FS-310-HDS-010-SDS-010-SMS-130: interface '${ifName}' policyRoutingAllocation.${field} must be a positive integer";

  policyRoutingAllocationFor =
    ifName:
    let
      allocation = policyRoutingAllocations.${ifName} or null;
      source = if builtins.isAttrs allocation then allocation.source or null else null;
    in
    if !(builtins.isAttrs allocation) || allocation == { } then
      throw "FS-310-HDS-010-SDS-010-SMS-130: interface '${ifName}' has NixOS policy-routing materialization but lacks CPM policyRoutingAllocation; renderer must not invent route table IDs or rule priorities"
    else if source != "control-plane-model" && source != "provider-contract" then
      throw "FS-310-HDS-010-SDS-010-SMS-130: interface '${ifName}' policyRoutingAllocation.source must be 'control-plane-model' or 'provider-contract'"
    else
      {
        tableId = positiveInt ifName "tableId" (allocation.tableId or null);
        priority = positiveInt ifName "priority" (allocation.priority or null);
        tableRulePriority = positiveInt ifName "tableRulePriority" (allocation.tableRulePriority or null);
        dynamicRulePriority = positiveInt ifName "dynamicRulePriority" (allocation.dynamicRulePriority or null);
        mainSuppressPriority = positiveInt ifName "mainSuppressPriority" (allocation.mainSuppressPriority or null);
      };
in
builtins.foldl'
  (
    acc: entry:
    let
      index = entry.index;
      ifName = entry.ifName;
      interfaceName = renderedInterfaceNames.${ifName};
      policyRoutingAllocation = policyRoutingAllocationFor ifName;
      tableId = policyRoutingAllocation.tableId;
      routeSourceIfNames = forTarget interfaceName;
      baseSourceIfNames = forTargetRules interfaceName;
      policyIngressLocalSourceIfNames = lib.optionals
        (
          isPolicy && isPolicyUpstreamInterface interfaceName
        )
        (
          lib.filter
            (
              name:
              isPolicyDownstreamInterface renderedInterfaceNames.${name}
              && hasAcceptForwardingRule renderedInterfaceNames.${name} interfaceName
            )
            interfaceNames
        );
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
        sourceIfName != ifName
        && (
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
          )
        );
      isReturnSideSelfIngress =
        (isDownstreamSelectorPolicyInterface interfaceName && !(isPolicy || isUpstreamSelectorCoreInterface interfaceName))
        || (isPolicy && isPolicyDownstreamInterface interfaceName)
        || (isPolicy && isPolicyUpstreamInterface interfaceName)
        || (isUpstreamSelectorCoreInterface interfaceName && !(isPolicy || isDownstreamSelectorPolicyInterface interfaceName));
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
            if sourceIfName == ifName && isReturnSideSelfIngress then
              emptyScope
            else if isReturnSideRuleIngress sourceIfName then
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
            if isReturnSideRuleIngress sourceIfName then
              forwardingMainScope
            else if sourceIfName == ifName then
              {
                staticPrefixes =
                  if isUpstreamSelectorPolicyInterface interfaceName then [ ] else forwardingMainScope.staticPrefixes;
                sourceFiles = if isUpstreamSelectorPolicyInterface interfaceName then [ ] else forwardingMainScope.sourceFiles;
              }
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
        tableForOutputIfName =
          outputIfName:
          if isUpstreamSelectorCoreInterface interfaceName || isUpstreamSelectorPolicyInterface interfaceName then
            tableId
          else
            (policyRoutingAllocationFor outputIfName).tableId;
      };
      routesByInterfacePreferred = lib.mapAttrs (_: serviceDnsRoutes.prefer) routesByInterface;
      localOriginSourceIfNames = lib.unique (routeSourceIfNames ++ sourceIfNames);
      localOriginRoutesByInterface =
        localOriginDns.routesByInterface tableId localOriginSourceIfNames;
      localOriginRules =
        localOriginDns.rules tableId policyRoutingAllocation.tableRulePriority localOriginSourceIfNames;
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
              policyRulesFor interfaceName tableId policyRoutingAllocation.tableRulePriority policyRoutingAllocation.mainSuppressPriority [ sourceIfName ] [ ] destinationScope;
            sourceScopedRules =
              policyRulesFor interfaceName tableId policyRoutingAllocation.tableRulePriority policyRoutingAllocation.mainSuppressPriority [ sourceIfName ] sourceScopeForRule [ ];
          in
          if
            sourceIfName == ifName
            && isReturnSideSelfIngress
          then
            [ ]
          else if
            sourceIfName == ifName
            && isUpstreamSelectorPolicyInterface interfaceName
            && scopeHasEntries forwardingMainScope
          then
            [ ]
          else if destinationScope != [ ] && sourceScopeForRule != [ ] then
            destinationScopedRules ++ sourceScopedRules
          else
            policyRulesFor interfaceName tableId policyRoutingAllocation.tableRulePriority policyRoutingAllocation.mainSuppressPriority [ sourceIfName ] sourceScopeForRule destinationScope
        )
        sourceIfNames;
      forwardingIngressRules =
        let
          tableRuleFor = prefix: {
            Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
            From = prefix.prefix;
            IncomingInterface = interfaceName;
            Priority = policyRoutingAllocation.dynamicRulePriority;
            Table = tableId;
          };
          mainFallbackRuleFor = prefix: {
            Family = if (prefix.family or 4) == 6 then "ipv6" else "ipv4";
            From = prefix.prefix;
            IncomingInterface = interfaceName;
            Priority = policyRoutingAllocation.mainSuppressPriority;
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
      allRulesForThisInterface = lib.unique (rulesForThisInterface ++ forwardingIngressRules ++ localOriginRules);
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
      routes =
        let
          routesWithPolicyTables = builtins.foldl'
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
        in
        builtins.foldl'
          (
            routesAcc: outputIfName:
              routesAcc
              // {
                ${outputIfName} =
                  (routesAcc.${outputIfName} or [ ]) ++ (localOriginRoutesByInterface.${outputIfName} or [ ]);
              }
          )
          routesWithPolicyTables
          (builtins.attrNames localOriginRoutesByInterface);
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
            dynamicPolicyRulesFor interfaceName tableId policyRoutingAllocation.dynamicRulePriority policyRoutingAllocation.mainSuppressPriority [ sourceIfName ] (ruleSourceScopeForIngress sourceIfName).sourceFiles
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
