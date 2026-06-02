{ lib
, interfaces
, interfaceNames
, renderedInterfaceNames
, policyRoutingByInterface
, delegatedPrefixSourceForRoute
, isExternalValidationDelegatedPrefixRoute
,
}:

let
  isOverlayProviderRoute =
    iface: route:
    (iface.sourceKind or null) == "overlay";

  isWanInterface = iface:
    (iface.sourceKind or null) == "wan"
    || (iface.carrier or null) == "wan"
    || (iface.type or null) == "wan";

  dynamicRoutePriority =
    iface: route:
    let
      intentKind = route.intent.kind or null;
    in
    if intentKind == "runtime-routed-prefix-return" then
      -20
    else if isWanInterface iface then
      10
    else
      0;

  routeGateway =
    route:
    if builtins.isString (route.via6 or null) && route.via6 != "" then
      route.via6
    else if builtins.isString (route.via4 or null) && route.via4 != "" then
      route.via4
    else
      null;

  isRuntimeRoutedPrefixReturnRoute =
    route: ((route.intent or { }).kind or null) == "runtime-routed-prefix-return";

  dynamicDelegatedRouteCandidates = lib.concatLists (
    map
      (
        ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
        in
        lib.imap0
          (
            index: route:
              let
                sourceFile = delegatedPrefixSourceForRoute route;
              in
              if sourceFile == null || isOverlayProviderRoute iface route then
                null
              else
                {
                  name = "delegated-prefix-route-${interfaceName}-${builtins.toString index}";
                  inherit interfaceName sourceFile;
                  gateway = routeGateway route;
                  family = route.family or null;
                  metric = route.metric or null;
                  table = route.Table or null;
                  priority = dynamicRoutePriority iface route;
                }
          )
          (iface.routes or [ ])
      )
      interfaceNames
  );

  dynamicPolicyDelegatedRouteCandidates = lib.concatLists (
    map
      (
        ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
        in
        lib.imap0
          (
            index: route:
              let
                sourceFile = delegatedPrefixSourceForRoute route;
                gateway =
                  if builtins.isString (route.Gateway or null) && route.Gateway != "" then
                    route.Gateway
                  else
                    null;
              in
              if sourceFile == null || isOverlayProviderRoute iface route then
                null
              else
                {
                  name = "delegated-prefix-policy-route-${interfaceName}-${builtins.toString index}";
                  inherit interfaceName sourceFile gateway;
                  family = route.Family or route.family or null;
                  metric = route.Metric or route.metric or null;
                  table = route.Table or null;
                  priority = dynamicRoutePriority iface route;
                }
          )
          (policyRoutingByInterface.routes.${ifName} or [ ])
      )
      interfaceNames
  );

  policyTableIdsByRenderedInterface =
    builtins.listToAttrs (
      lib.concatMap
        (ifName:
          let
            interfaceName = renderedInterfaceNames.${ifName};
            tableRules =
              lib.filter
                (rule: builtins.isInt (rule.Table or null) && (rule.Table or null) != 254)
                (policyRoutingByInterface.rules.${ifName} or [ ]);
          in
          map (rule: { name = interfaceName; value = rule.Table; }) tableRules)
        interfaceNames
    );

  allPolicyTableIds =
    lib.unique (
      lib.concatMap
        (ifName:
          let interfaceName = renderedInterfaceNames.${ifName};
          in
          if builtins.hasAttr interfaceName policyTableIdsByRenderedInterface then
            [ policyTableIdsByRenderedInterface.${interfaceName} ]
          else [ ])
        interfaceNames
    );

  dynamicPolicyTableDelegatedRouteCandidates = lib.concatLists (
    map
      (
        ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
        in
        lib.imap0
          (
            index: route:
              let
                sourceFile = delegatedPrefixSourceForRoute route;
                matchingTables =
                  lib.unique (
                    map (rule: rule.table) (
                      lib.filter
                        (
                          rule:
                          (rule.sourceFile or null) == sourceFile
                          && builtins.isInt (rule.table or null)
                          && (rule.table or null) != 254
                        )
                        (policyRoutingByInterface.dynamicSourceRules or [ ])
                    )
                  );
                targetTables =
                  if matchingTables != [ ] then matchingTables else allPolicyTableIds;
              in
              if
                sourceFile == null
                || isOverlayProviderRoute iface route
                || !(isRuntimeRoutedPrefixReturnRoute route)
              then
                [ ]
              else
                map
                  (table: {
                    name = "delegated-prefix-policy-route-${interfaceName}-${builtins.toString table}-${builtins.toString index}";
                    inherit interfaceName sourceFile table;
                    gateway = routeGateway route;
                    family = route.family or null;
                    metric = route.metric or null;
                    priority = dynamicRoutePriority iface route;
                  })
                  targetTables
          )
          (iface.routes or [ ])
      )
      interfaceNames
  );

  dynamicDelegatedRouteCandidatesBySource = builtins.groupBy (route: "${route.sourceFile}|${toString (route.table or "main")}") (
    lib.filter (route: route != null) (
      dynamicDelegatedRouteCandidates
      ++ dynamicPolicyDelegatedRouteCandidates
      ++ (builtins.concatLists dynamicPolicyTableDelegatedRouteCandidates)
    )
  );

  sortDynamicDelegatedRoutes =
    routes:
    builtins.sort
      (
        left: right:
        if (left.priority or 0) == (right.priority or 0) then
          left.name < right.name
        else
          (left.priority or 0) < (right.priority or 0)
      )
      routes;
in
lib.mapAttrsToList
  (_: routes: builtins.removeAttrs (builtins.head (sortDynamicDelegatedRoutes routes)) [ "priority" ])
  dynamicDelegatedRouteCandidatesBySource
