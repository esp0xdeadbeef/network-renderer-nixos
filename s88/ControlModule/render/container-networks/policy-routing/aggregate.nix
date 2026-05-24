{
  lib,
  interfaceNames,
  renderedInterfaceNames,
  isPolicy,
  isDownstreamSelectorPolicyInterface,
  isPolicyUpstreamInterface,
  isPolicyDownstreamInterface,
  sourceReachabilityRoutes,
  sourcePrefixes,
  forwardingSourceScope,
  ruleSourceScope,
  routesByOutputInterface,
  rawRoutesForPolicyTable,
  serviceDnsRoutes,
  policyRulesFor,
  dynamicPolicyRulesFor,
  forTarget,
  forTargetRules,
}:
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
      policyIngressLocalSourceIfNames = lib.optionals (
        isPolicy && isPolicyUpstreamInterface interfaceName
      ) (lib.filter (name: isPolicyDownstreamInterface renderedInterfaceNames.${name}) interfaceNames);
      sourceIfNames = lib.unique (baseSourceIfNames ++ policyIngressLocalSourceIfNames);
      sourceScope = sourcePrefixes.forInterface interfaceName;
      forwardingMainScope = forwardingSourceScope.forSourceInterface interfaceName;
      scopedRuleSource = ruleSourceScope.forInterface interfaceName sourceScope;
      effectiveMainSourceScope = sourceScope // {
        staticPrefixes = lib.unique (sourceScope.staticPrefixes ++ forwardingMainScope.staticPrefixes);
        sourceFiles = lib.unique (sourceScope.sourceFiles ++ forwardingMainScope.sourceFiles);
      };
      ruleSourceScopeForIngress =
        sourceIfName:
        let
          pairScope =
            if isDownstreamSelectorPolicyInterface interfaceName then
              {
                staticPrefixes = [ ];
                sourceFiles = [ ];
              }
            else
              forwardingSourceScope.forPair renderedInterfaceNames.${sourceIfName} interfaceName;
        in
        scopedRuleSource
        // {
          staticPrefixes = lib.unique (
            scopedRuleSource.staticPrefixes
            ++ forwardingMainScope.staticPrefixes
            ++ pairScope.staticPrefixes
          );
          sourceFiles = lib.unique (
            scopedRuleSource.sourceFiles ++ forwardingMainScope.sourceFiles ++ pairScope.sourceFiles
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
      rulesForThisInterface = lib.concatMap (
        sourceIfName:
        policyRulesFor interfaceName tableId [ sourceIfName ] (ruleSourceScopeForIngress sourceIfName).staticPrefixes
      ) sourceIfNames;
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
        builtins.concatMap (prefix: [
          (tableRuleFor prefix)
          (mainFallbackRuleFor prefix)
        ]) forwardingMainScope.staticPrefixes;
      allRulesForThisInterface = lib.unique (rulesForThisInterface ++ forwardingIngressRules);
      hasMainLookupRuleForSource =
        source:
        builtins.any (
          rule:
          (rule.From or null) == (source.prefix or null)
          && (rule.Table or null) == 254
          && (rule.SuppressPrefixLength or null) == 0
        ) allRulesForThisInterface;
      mainSourceRoutes = lib.filter (route: route != null) (
        map (sourceReachabilityRoutes.routeFor ifName) (
          lib.filter (
            source:
            hasMainLookupRuleForSource source
            && sourceReachabilityRoutes.matchesInterfaceOrigin interfaceName source
          ) effectiveMainSourceScope.staticPrefixes
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
        ${ifName} = (acc.rules.${ifName} or [ ]) ++ allRulesForThisInterface;
      };
      dynamicSourceRules =
        acc.dynamicSourceRules
        ++ lib.concatMap (
          sourceIfName:
          dynamicPolicyRulesFor interfaceName tableId [ sourceIfName ] (ruleSourceScopeForIngress sourceIfName).sourceFiles
        ) sourceIfNames;
    }
  )
  {
    routes = { };
    mainRoutes = { };
    rules = { };
    dynamicSourceRules = [ ];
  }
  (lib.imap0 (index: ifName: { inherit index ifName; }) interfaceNames)
