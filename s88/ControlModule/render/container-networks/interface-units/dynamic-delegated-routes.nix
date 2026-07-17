{
  lib,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  policyRoutingByInterface,
  delegatedPrefixSourceForRoute,
  isExternalValidationDelegatedPrefixRoute,
}:

let
  isOverlayProviderRoute = iface: route: (iface.sourceKind or null) == "overlay";

  isWanInterface =
    iface:
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

  derivationForRoute =
    route:
    if !(isRuntimeRoutedPrefixReturnRoute route) then
      {
        deriveTenantPrefix = false;
        delegatedPrefixLength = null;
        perTenantPrefixLength = null;
        slot = null;
        tenant = null;
        prefixName = null;
        prefixPostfix = null;
      }
    else
      let
        delegatedPrefixLength = route.delegatedPrefixLength or null;
        perTenantPrefixLength = route.perTenantPrefixLength or null;
        slot = route.slot or null;
        valid =
          builtins.isInt delegatedPrefixLength
          && builtins.isInt perTenantPrefixLength
          && builtins.isInt slot
          && delegatedPrefixLength >= 0
          && delegatedPrefixLength <= 128
          && perTenantPrefixLength >= delegatedPrefixLength
          && perTenantPrefixLength <= 128
          && slot >= 0;
      in
      if !valid then
        throw "FS-350-HDS-010-SDS-010-SMS-060: runtime routed-prefix candidate '${
          toString (route.prefixName or route.tenant or "unnamed")
        }' lacks valid delegatedPrefixLength, perTenantPrefixLength, or slot metadata"
      else
        {
          deriveTenantPrefix = true;
          inherit delegatedPrefixLength perTenantPrefixLength slot;
          tenant = route.tenant or null;
          prefixName = route.prefixName or null;
          prefixPostfix = route.prefixPostfix or null;
        };

  dynamicDelegatedRouteCandidates = lib.concatLists (
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        interfaceName = renderedInterfaceNames.${ifName};
      in
      lib.imap0 (
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
          // derivationForRoute route
      ) (iface.routes or [ ])
    ) interfaceNames
  );

  dynamicPolicyDelegatedRouteCandidates = lib.concatLists (
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        interfaceName = renderedInterfaceNames.${ifName};
      in
      lib.imap0 (
        index: route:
        let
          sourceFile = delegatedPrefixSourceForRoute route;
          gateway =
            if builtins.isString (route.Gateway or null) && route.Gateway != "" then route.Gateway else null;
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
          // derivationForRoute route
      ) (policyRoutingByInterface.routes.${ifName} or [ ])
    ) interfaceNames
  );

  policyTableIdsByRenderedInterface = builtins.listToAttrs (
    lib.concatMap (
      ifName:
      let
        interfaceName = renderedInterfaceNames.${ifName};
        tableRules = lib.filter (rule: builtins.isInt (rule.Table or null) && (rule.Table or null) != 254) (
          policyRoutingByInterface.rules.${ifName} or [ ]
        );
      in
      map (rule: {
        name = interfaceName;
        value = rule.Table;
      }) tableRules
    ) interfaceNames
  );

  allPolicyTableIds = lib.unique (
    lib.concatMap (
      ifName:
      let
        interfaceName = renderedInterfaceNames.${ifName};
      in
      if builtins.hasAttr interfaceName policyTableIdsByRenderedInterface then
        [ policyTableIdsByRenderedInterface.${interfaceName} ]
      else
        [ ]
    ) interfaceNames
  );

  dynamicPolicyTableDelegatedRouteCandidates = lib.concatLists (
    map (
      ifName:
      let
        iface = interfaces.${ifName};
        interfaceName = renderedInterfaceNames.${ifName};
      in
      lib.imap0 (
        index: route:
        let
          sourceFile = delegatedPrefixSourceForRoute route;
          matchingTables = lib.unique (
            map (rule: rule.table) (
              lib.filter (
                rule:
                (rule.sourceFile or null) == sourceFile
                && builtins.isInt (rule.table or null)
                && (rule.table or null) != 254
              ) (policyRoutingByInterface.dynamicSourceRules or [ ])
            )
          );
          targetTables = if matchingTables != [ ] then matchingTables else allPolicyTableIds;
        in
        if
          sourceFile == null
          || isOverlayProviderRoute iface route
          || !(isRuntimeRoutedPrefixReturnRoute route)
        then
          [ ]
        else
          map (
            table:
            {
              name = "delegated-prefix-policy-route-${interfaceName}-${builtins.toString table}-${builtins.toString index}";
              inherit interfaceName sourceFile table;
              gateway = routeGateway route;
              family = route.family or null;
              metric = route.metric or null;
              priority = dynamicRoutePriority iface route;
            }
            // derivationForRoute route
          ) targetTables
      ) (iface.routes or [ ])
    ) interfaceNames
  );

  dynamicDelegatedRouteCandidatesBySource =
    builtins.groupBy
      (
        route:
        builtins.concatStringsSep "|" [
          route.sourceFile
          (toString (route.table or "main"))
          (toString (route.deriveTenantPrefix or false))
          (toString (route.delegatedPrefixLength or ""))
          (toString (route.perTenantPrefixLength or ""))
          (toString (route.slot or ""))
          (toString (route.tenant or ""))
          (toString (route.prefixName or ""))
          (toString (route.prefixPostfix or ""))
        ]
      )
      (
        lib.filter (route: route != null) (
          dynamicDelegatedRouteCandidates
          ++ dynamicPolicyDelegatedRouteCandidates
          ++ (builtins.concatLists dynamicPolicyTableDelegatedRouteCandidates)
        )
      );

  sortDynamicDelegatedRoutes =
    routes:
    builtins.sort (
      left: right:
      if (left.priority or 0) == (right.priority or 0) then
        left.name < right.name
      else
        (left.priority or 0) < (right.priority or 0)
    ) routes;
in
lib.mapAttrsToList (
  _: routes: builtins.removeAttrs (builtins.head (sortDynamicDelegatedRoutes routes)) [ "priority" ]
) dynamicDelegatedRouteCandidatesBySource
