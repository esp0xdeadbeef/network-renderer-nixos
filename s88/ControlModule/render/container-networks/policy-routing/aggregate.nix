{
  lib,
  interfaceNames,
  renderedInterfaceNames,
  isPolicy,
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
      forwardingRuleScope = forwardingSourceScope.forTargetInterface interfaceName;
      forwardingMainScope = forwardingSourceScope.forSourceInterface interfaceName;
      scopedRuleSource = ruleSourceScope.forInterface interfaceName sourceScope;
      effectiveRuleSourceScope = scopedRuleSource // {
        staticPrefixes = lib.unique (
          scopedRuleSource.staticPrefixes
          ++ forwardingRuleScope.staticPrefixes
          ++ forwardingMainScope.staticPrefixes
        );
        sourceFiles = lib.unique (
          scopedRuleSource.sourceFiles ++ forwardingRuleScope.sourceFiles ++ forwardingMainScope.sourceFiles
        );
      };
      effectiveMainSourceScope = sourceScope // {
        staticPrefixes = lib.unique (sourceScope.staticPrefixes ++ forwardingMainScope.staticPrefixes);
        sourceFiles = lib.unique (sourceScope.sourceFiles ++ forwardingMainScope.sourceFiles);
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
        ${ifName} = (acc.rules.${ifName} or [ ]) ++ rulesForThisInterface;
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
  (lib.imap0 (index: ifName: { inherit index ifName; }) interfaceNames)
