{
  lib,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  networkManagerInterfaces,
  keepInterfaceRoutesInMain,
  isUpstreamSelectorCoreInterface,
  advertisedOnlinkRoutesByInterface,
  policyRoutingByInterface,
  mkRoute,
  isExternalValidationDelegatedPrefixRoute,
  delegatedPrefixSourceForRoute,
  mkDynamicWanNetworkConfig,
  needsIpv6AcceptRA,
  common,
}:

let
  inherit (common) interfaceNameFor;
  peers = import ./policy-routing/peers.nix {
    inherit lib common;
  };

  routeGateway =
    route:
    if builtins.isString (route.via4 or null) && route.via4 != "" then
      { family = 4; gateway = route.via4; }
    else if builtins.isString (route.via6 or null) && route.via6 != "" then
      { family = 6; gateway = route.via6; }
    else
      null;

  interfacePeerForFamily =
    family: iface:
    let
      address = peers.addressForFamily family iface;
    in
    if family == 6 then peers.ipv6PeerFor127 address else peers.ipv4PeerFor31 address;

  routeGatewayMatchesInterface =
    iface: route:
    let gateway = routeGateway route;
    in gateway == null || interfacePeerForFamily gateway.family iface == gateway.gateway;

  isPolicyOnlyRoute =
    route: builtins.isAttrs route && ((route.policyOnly or false) == true || (route._s88PolicyOnly or false) == true);

  isServiceIngressRoute =
    route:
    builtins.isAttrs route
    && (route.proto or null) == "service-ingress"
    && (route.policyOnly or false) != true
    && (route._s88PolicyOnly or false) != true;

  isMainTableRoute = route: !(route ? Table) || route.Table == 254;

  isDefaultRoute =
    route:
    (route.Destination or null) == "0.0.0.0/0"
    || (route.Destination or null) == "::/0"
    || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  isMainTableDefaultRoute = route: isMainTableRoute route && isDefaultRoute route;

  isOverlayProviderRoute =
    iface: route:
    (iface.sourceKind or null) == "overlay" || (builtins.isAttrs route && (route.proto or null) == "overlay");

  isWanInterface = iface:
    (iface.sourceKind or null) == "wan"
    || (iface.carrier or null) == "wan"
    || (iface.type or null) == "wan";

  stripRouteMetadata = route: builtins.removeAttrs route [ "_s88PolicyOnly" "sourceFile" "delegatedPrefix" "family" ];

  interfaceUnits = builtins.listToAttrs (
    lib.filter (entry: entry != null) (
      lib.imap0 (
        index: ifName:
        let
          iface = interfaces.${ifName};
          interfaceName = renderedInterfaceNames.${ifName};
          rawRoutes = (iface.routes or [ ]) ++ (advertisedOnlinkRoutesByInterface.${ifName} or [ ]);
          renderedInterfaceName = renderedInterfaceNames.${ifName};
          keepStaticRoutesInMain =
            keepInterfaceRoutesInMain || isUpstreamSelectorCoreInterface renderedInterfaceName;
          mainStaticRawRoutes =
            if keepInterfaceRoutesInMain then
              staticRawRoutes
            else
              lib.filter (route: routeGatewayMatchesInterface iface route) staticRawRoutes;
          serviceIngressMainRawRoutes =
            lib.filter (route: isServiceIngressRoute route && routeGatewayMatchesInterface iface route) staticRawRoutes;
          staticRawRoutes = lib.filter (
            route: !(isExternalValidationDelegatedPrefixRoute route) && !(isPolicyOnlyRoute route)
          ) rawRoutes;
          policyMainRoutes =
            lib.optionals keepInterfaceRoutesInMain (
              map (route: builtins.removeAttrs route [ "Table" ]) (
                lib.filter (route: !(isPolicyOnlyRoute route)) (policyRoutingByInterface.routes.${ifName} or [ ])
              )
            );
          renderedRoutes =
            (lib.optionals keepStaticRoutesInMain (
              lib.filter (route: route != null) (map mkRoute mainStaticRawRoutes)
            ))
            ++ (lib.optionals (!keepStaticRoutesInMain) (
              lib.filter (route: route != null) (map mkRoute serviceIngressMainRawRoutes)
            ))
            ++ policyMainRoutes
            ++ (policyRoutingByInterface.routes.${ifName} or [ ]);
        in
        if builtins.elem interfaceName networkManagerInterfaces then
          null
        else
          {
            name = "10-${interfaceName}";
            value = {
              matchConfig.Name = interfaceName;
              networkConfig = { ConfigureWithoutCarrier = true; } // mkDynamicWanNetworkConfig iface;
              address = iface.addresses or [ ];
              routes = map stripRouteMetadata (
                lib.filter (
                  route: keepStaticRoutesInMain || !(isMainTableDefaultRoute route)
                ) renderedRoutes
              );
              routingPolicyRules = policyRoutingByInterface.rules.${ifName} or [ ];
            };
          }
      ) interfaceNames
    )
  );

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
          gateway =
            if builtins.isString (route.via6 or null) && route.via6 != "" then
              route.via6
            else if builtins.isString (route.via4 or null) && route.via4 != "" then
              route.via4
            else
              null;
        in
        if sourceFile == null || isOverlayProviderRoute iface route then
          null
        else
          {
            name = "delegated-prefix-route-${interfaceName}-${builtins.toString index}";
            inherit interfaceName sourceFile gateway;
            family = route.family or null;
            metric = route.metric or null;
            table = route.Table or null;
            priority = if isWanInterface iface then 10 else 0;
          }
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
            priority = if isWanInterface iface then 10 else 0;
          }
      ) (policyRoutingByInterface.routes.${ifName} or [ ])
    ) interfaceNames
  );

  dynamicDelegatedRouteCandidatesBySource = builtins.groupBy (route: route.sourceFile) (
    lib.filter (route: route != null) (dynamicDelegatedRouteCandidates ++ dynamicPolicyDelegatedRouteCandidates)
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

  dynamicDelegatedRoutes =
    lib.mapAttrsToList
      (_: routes: builtins.removeAttrs (builtins.head (sortDynamicDelegatedRoutes routes)) [ "priority" ])
      dynamicDelegatedRouteCandidatesBySource;
in
{
  inherit interfaceUnits;

  ipv6AcceptRAInterfaces = map interfaceNameFor (
    lib.filter (
      iface:
      let
        interfaceName = interfaceNameFor iface;
      in
      needsIpv6AcceptRA iface && !(builtins.elem interfaceName networkManagerInterfaces)
    ) (builtins.attrValues interfaces)
  );

  inherit dynamicDelegatedRoutes;
}
