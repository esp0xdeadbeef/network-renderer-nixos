{
  lib,
  containerModel,
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
      {
        family = 4;
        gateway = route.via4;
      }
    else if builtins.isString (route.via6 or null) && route.via6 != "" then
      {
        family = 6;
        gateway = route.via6;
      }
    else if builtins.isString (route.Gateway or null) && route.Gateway != "" then
      {
        family = if lib.hasInfix ":" route.Gateway then 6 else 4;
        gateway = route.Gateway;
      }
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
    let
      gateway = routeGateway route;
    in
    gateway == null || interfacePeerForFamily gateway.family iface == gateway.gateway;
  routeGatewayExplicitlyMatchesInterface =
    iface: route:
    let
      gateway = routeGateway route;
    in
    gateway != null && interfacePeerForFamily gateway.family iface == gateway.gateway;

  isPolicyOnlyRoute =
    route:
    builtins.isAttrs route
    && ((route.policyOnly or false) == true || (route._s88PolicyOnly or false) == true);

  isServiceIngressRoute =
    route:
    builtins.isAttrs route
    && (route.proto or null) == "service-ingress"
    && (route.policyOnly or false) != true
    && (route._s88PolicyOnly or false) != true;

  isHostDestination =
    destination:
    builtins.isString destination
    && destination != ""
    && (
      !(lib.hasInfix "/" destination)
      || lib.hasSuffix "/32" destination
      || lib.hasSuffix "/128" destination
    );

  isServiceIngressMainRoute =
    route: isServiceIngressRoute route && isHostDestination (route.dst or route.Destination or null);

  isMainTableRoute = route: !(route ? Table) || route.Table == 254;

  isDefaultRoute =
    route:
    (route.Destination or null) == "0.0.0.0/0"
    || (route.Destination or null) == "::/0"
    || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  isMainTableDefaultRoute = route: isMainTableRoute route && isDefaultRoute route;

  stripRouteMetadata =
    route:
    builtins.removeAttrs route [
      "_s88PolicyOnly"
      "_s88IntentKind"
      "sourceFile"
      "delegatedPrefix"
      "family"
      "proto"
      "intent"
      "reason"
      "lane"
      "policyOnly"
    ];
  tenantPrefixOwners =
    if builtins.isAttrs (((containerModel.site or { }).tenantPrefixOwners or null)) then
      (containerModel.site or { }).tenantPrefixOwners
    else
      { };
  prefixOwnerForRoute =
    route:
    let
      destination = route.Destination or route.dst or null;
      family =
        if !(builtins.isString destination) then
          null
        else if lib.hasInfix ":" destination then
          6
        else
          4;
      key = if family == null then null else "${toString family}|${destination}";
      entry =
        if key != null && builtins.hasAttr key tenantPrefixOwners then tenantPrefixOwners.${key} else { };
    in
    entry.owner or null;
  routeReturnsToInterfaceLane =
    iface: route:
    let
      lane = (iface.backingRef or { }).lane or { };
      laneAccess = if builtins.isAttrs lane then lane.access or null else null;
      owner = prefixOwnerForRoute route;
    in
    builtins.isString laneAccess && laneAccess != "" && owner == laneAccess;
  isDiagnosticMainRoute =
    iface: route:
    builtins.isAttrs route
    && !(isPolicyOnlyRoute route)
    && !(isDefaultRoute route)
    && (route._s88IntentKind or null) == "internal-reachability"
    && routeReturnsToInterfaceLane iface route
    && routeGatewayExplicitlyMatchesInterface iface route;

  nixosOwnsInterface =
    iface:
    let
      materialization = ((iface.materialization or { }).nixos or { });
    in
    (materialization.ownsInterface or false) == true
    || (materialization.owner or null) == "network-renderer-nixos";

  isProviderCreatedInterface =
    iface:
    (iface.sourceKind or null) == "overlay" && !nixosOwnsInterface iface;

  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  isPppoeSessionInterface =
    iface:
    let
      connectivity = attrsOrEmpty (iface.connectivity or null);
      backingRef = attrsOrEmpty (iface.backingRef or null);
      connectivityBackingRef = attrsOrEmpty (connectivity.backingRef or null);
    in
    (iface.sourceKind or null) == "pppoe-session"
    || (connectivity.sourceKind or null) == "pppoe-session"
    || (backingRef.kind or null) == "pppoe-session"
    || (connectivityBackingRef.kind or null) == "pppoe-session";

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
          serviceIngressMainRawRoutes = lib.filter (
            route: isServiceIngressMainRoute route && routeGatewayMatchesInterface iface route
          ) staticRawRoutes;
          staticRawRoutes = lib.filter (
            route: !(isExternalValidationDelegatedPrefixRoute route) && !(isPolicyOnlyRoute route)
          ) rawRoutes;
          policyMainRoutes = lib.optionals keepInterfaceRoutesInMain (
            map (route: builtins.removeAttrs route [ "Table" ]) (
              lib.filter (route: !(isPolicyOnlyRoute route)) (policyRoutingByInterface.routes.${ifName} or [ ])
            )
          );
          diagnosticMainRoutes = map (route: builtins.removeAttrs route [ "Table" ]) (
            lib.filter (isDiagnosticMainRoute iface) (policyRoutingByInterface.routes.${ifName} or [ ])
          );
          renderedRoutes =
            (lib.optionals keepStaticRoutesInMain (
              lib.filter (route: route != null) (map mkRoute mainStaticRawRoutes)
            ))
            ++ (lib.optionals (!keepStaticRoutesInMain) (
              lib.filter (route: route != null) (map mkRoute serviceIngressMainRawRoutes)
            ))
            ++ policyMainRoutes
            ++ diagnosticMainRoutes
            ++ (lib.filter (route: route != null) (map mkRoute (policyRoutingByInterface.mainRoutes.${ifName} or [ ])))
            ++ (policyRoutingByInterface.routes.${ifName} or [ ]);
        in
        if
          builtins.elem interfaceName networkManagerInterfaces
          || isProviderCreatedInterface iface
          || isPppoeSessionInterface iface
        then
          null
        else
          {
            name = "10-${interfaceName}";
            value = {
              matchConfig.Name = interfaceName;
              networkConfig = {
                ConfigureWithoutCarrier = true;
              }
              // mkDynamicWanNetworkConfig iface;
              linkConfig = lib.optionalAttrs (builtins.isInt (iface.mtu or null)) {
                MTUBytes = iface.mtu;
              };
              address = iface.addresses or [ ];
              routes = map stripRouteMetadata (
                lib.filter (route: keepStaticRoutesInMain || !(isMainTableDefaultRoute route)) renderedRoutes
              );
              routingPolicyRules = policyRoutingByInterface.rules.${ifName} or [ ];
            };
          }
      ) interfaceNames
    )
  );

  dynamicDelegatedRoutes = import ./interface-units/dynamic-delegated-routes.nix {
    inherit
      lib
      interfaces
      interfaceNames
      renderedInterfaceNames
      policyRoutingByInterface
      ;
    inherit delegatedPrefixSourceForRoute isExternalValidationDelegatedPrefixRoute;
  };

  staticProviderRoutes =
    lib.concatLists (
      map
        (
          ifName:
          let
            iface = interfaces.${ifName};
            interfaceName = renderedInterfaceNames.${ifName};
            isProviderCreated = (iface.sourceKind or null) == "overlay";
          in
          if !isProviderCreated then
            [ ]
          else
            lib.imap0
              (
                index: route:
                if !builtins.isAttrs route || !(builtins.isString (route.Destination or null)) then
                  null
                else
                  {
                    name = "provider-route-${interfaceName}-${builtins.toString index}";
                    inherit interfaceName;
                    destination = route.Destination;
                    gateway = route.Gateway or null;
                    scope = route.Scope or null;
                    table = route.Table or null;
                    metric = route.Metric or null;
                  }
              )
              (policyRoutingByInterface.routes.${ifName} or [ ])
        )
        interfaceNames
    );

  staticProviderPolicyRules =
    lib.concatLists (
      map
        (
          ifName:
          let
            iface = interfaces.${ifName};
            interfaceName = renderedInterfaceNames.${ifName};
            isProviderCreated = (iface.sourceKind or null) == "overlay";
          in
          if !isProviderCreated then
            [ ]
          else
            lib.imap0
              (
                index: rule:
                if !builtins.isAttrs rule then
                  null
                else
                  rule
                  // {
                    name = "provider-policy-rule-${interfaceName}-${builtins.toString index}";
                    outputInterfaceName = interfaceName;
                  }
              )
              (policyRoutingByInterface.rules.${ifName} or [ ])
        )
        interfaceNames
    );
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
  staticProviderRoutes = lib.filter (route: route != null) staticProviderRoutes;
  staticProviderPolicyRules = lib.filter (rule: rule != null) staticProviderPolicyRules;
}
